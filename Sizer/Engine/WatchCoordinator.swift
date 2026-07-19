import Foundation
import Combine
import AppKit
import SwiftUI

enum FolderKind { case drop, output, processed, failed }

/// 앱의 중심 상태. 폴더 감시 + 직렬 변환 큐 + 히스토리/상태 발행 + UI 액션.
@MainActor
final class WatchCoordinator: ObservableObject {
    @Published private(set) var status: WatchStatus = .idle
    @Published private(set) var recentJobs: [JobRecord] = []
    @Published private(set) var ffmpegAvailable: Bool = FFmpeg.isAvailable
    @Published private(set) var dropTargetVisible: Bool = false

    let settings: AppSettings

    private var watcher: FolderWatcher?
    private let workQueue = DispatchQueue(label: "com.dilly.sizer.convert")   // 직렬(동시에 1개)
    private let ingestQueue = DispatchQueue(label: "com.dilly.sizer.ingest")  // 드롭 파일 복사
    private var active: Set<String> = []       // 큐잉/변환 중인 파일 경로
    private var paused = false
    private var cancellables: Set<AnyCancellable> = []
    private var rescanTimer: Timer?
    private var cleanupTimer: Timer?

    var isPaused: Bool { paused }

    /// 상태 변화 스트림(트레이 아이콘 애니메이션 제어용).
    var statusPublisher: AnyPublisher<WatchStatus, Never> { $status.eraseToAnyPublisher() }

    /// 설정 창 컨트롤러(최초 openSettings 시 생성). SettingsRootView에 환경 객체 주입.
    private lazy var settingsWindowController: SettingsWindowController = {
        let root = SettingsRootView()
            .environmentObject(self)
            .environmentObject(settings)
        return SettingsWindowController(rootView: AnyView(root))
    }()

    /// 플로팅 드롭 타겟 패널 컨트롤러.
    private lazy var dropTargetController = DropTargetController(coordinator: self)

    init(settings: AppSettings) {
        self.settings = settings
    }

    // MARK: 생명주기

    func start() {
        settings.ensureFolders()
        Notifier.requestAuthorization()
        LoginItem.setEnabled(settings.launchAtLogin)
        observeSettings()
        restartWatcher()
        startRescanTimer()
        startCleanupTimer()
        scan()
        updateStatus()
        restoreDropTarget()
    }

    // MARK: 플로팅 드롭 타겟

    private func restoreDropTarget() {
        if settings.dropTargetShown {
            dropTargetController.show()
            dropTargetVisible = true
        }
    }

    func toggleDropTarget() {
        dropTargetController.toggle()
        dropTargetVisible = dropTargetController.isVisible
        settings.dropTargetShown = dropTargetVisible
    }

    /// Finder에서 드롭된 URL들을 드롭 폴더로 복사(백그라운드) → 변환 트리거. 복사 예정 개수 반환.
    @discardableResult
    func ingest(urls: [URL]) -> Int {
        let supported = DropIngest.supportedURLs(urls, imageEnabled: settings.imageConversionEnabled)
        guard !supported.isEmpty else { return 0 }
        let dropFolder = settings.dropFolderURL
        ingestQueue.async { [weak self] in
            DropIngest.copy(supported, to: dropFolder)
            Task { @MainActor in self?.scan() }
        }
        return supported.count
    }

    private func startCleanupTimer() {
        runProcessedCleanup()
        cleanupTimer?.invalidate()
        // 장시간 실행 세션 대비 1시간마다 점검.
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.runProcessedCleanup() }
        }
    }

    /// processed 폴더에서 보관 기간을 넘긴 파일을 백그라운드에서 삭제.
    func runProcessedCleanup() {
        guard settings.autoCleanProcessedEnabled else { return }
        let folder = settings.processedFolderURL
        let days = settings.processedRetentionDays
        DispatchQueue.global(qos: .utility).async {
            let n = ProcessedCleaner.clean(folder: folder, olderThanDays: days)
            if n > 0 { AppLogger.info("processed 자동 정리: \(n)개 삭제(\(days)일 초과)") }
        }
    }

    private func observeSettings() {
        settings.$dropFolderPath
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.restartWatcher()
                    self?.scan()
                }
            }
            .store(in: &cancellables)

        settings.$launchAtLogin
            .dropFirst()
            .removeDuplicates()
            .sink { enabled in LoginItem.setEnabled(enabled) }
            .store(in: &cancellables)
    }

    private func restartWatcher() {
        watcher?.stop()
        let path = settings.dropFolderPath
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        let w = FolderWatcher(path: path) { [weak self] in
            Task { @MainActor in self?.scan() }
        }
        w.start()
        watcher = w
    }

    private func startRescanTimer() {
        rescanTimer?.invalidate()
        rescanTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.scan() }
        }
    }

    // MARK: 스캔 & 변환

    func scan() {
        guard !paused else { return }
        let config = settings.config
        let dropURL = settings.dropFolderURL
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: dropURL, includingPropertiesForKeys: nil) else { return }

        for url in items.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let name = url.lastPathComponent
            if name.hasPrefix(".") { continue }
            let ext = url.pathExtension.lowercased()
            if ext == "part" { continue }

            if ConversionConfig.videoExtensions.contains(ext) {
                guard ffmpegAvailable else { continue }
            } else if ConversionConfig.imageExtensions.contains(ext) {
                guard config.imageEnabled else { continue }
            } else {
                continue
            }

            let key = url.path
            if active.contains(key) { continue }

            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { continue }

            active.insert(key)
            submit(url: url, key: key, config: config)
        }
    }

    private func submit(url: URL, key: String, config: ConversionConfig) {
        workQueue.async { [weak self] in
            guard WatchCoordinator.waitUntilStable(url) else {
                AppLogger.info("복사 중으로 판단, 대기: \(url.lastPathComponent)")
                Task { @MainActor in self?.active.remove(key) }
                return
            }
            Task { @MainActor in self?.status = .converting(url.lastPathComponent) }
            let outcome = ConversionEngine.process(url, config: config)
            Task { @MainActor in self?.finish(outcome: outcome, key: key) }
        }
    }

    private func finish(outcome: JobOutcome, key: String) {
        active.remove(key)
        let record = JobRecord(
            sourceName: outcome.sourceName,
            outputName: outcome.outputName,
            outputURL: outcome.outputURL,
            kind: outcome.kind,
            success: outcome.success,
            detail: outcome.detail,
            date: Date()
        )
        recentJobs.insert(record, at: 0)
        if recentJobs.count > 20 {
            recentJobs.removeLast(recentJobs.count - 20)
        }
        updateStatus()
        scan()   // 대기 중이던 다른 파일 픽업
    }

    private func updateStatus() {
        if paused {
            status = .paused
        } else if active.isEmpty {
            status = watcher != nil ? .watching : .idle
        } else {
            status = .watching
        }
    }

    /// 파일 크기가 연속으로 동일해질 때까지 대기(복사 완료 판정). 백그라운드에서 호출.
    nonisolated static func waitUntilStable(_ url: URL, checks: Int = 3, interval: TimeInterval = 1.0) -> Bool {
        func size() -> Int64? {
            (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)??.int64Value
        }
        var last: Int64 = -1
        for _ in 0..<checks {
            guard let s = size() else { return false }
            last = s
            Thread.sleep(forTimeInterval: interval)
        }
        guard let s = size() else { return false }
        return s == last && s > 0
    }

    // MARK: UI 액션

    func togglePause() {
        paused.toggle()
        updateStatus()
        if !paused { scan() }
    }

    func rescanNow() { scan() }

    /// 최근 변환 항목 클릭 → 결과 영상을 기본 플레이어로 재생. 파일이 없으면 출력 폴더를 연다.
    func play(_ record: JobRecord) {
        guard let url = record.outputURL else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
        } else {
            revealOutputFolder()
        }
    }

    func revealDropFolder() { reveal(settings.dropFolderURL) }
    func revealOutputFolder() { reveal(settings.outputFolderURL) }
    func revealLogs() {
        NSWorkspace.shared.activateFileViewerSelecting([AppLogger.logFileURL])
    }

    private func reveal(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }

    func chooseFolder(for kind: FolderKind) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "선택"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        switch kind {
        case .drop: settings.dropFolderPath = url.path
        case .output: settings.outputFolderPath = url.path
        case .processed: settings.processedFolderPath = url.path
        case .failed: settings.failedFolderPath = url.path
        }
        settings.ensureFolders()
    }

    func openSettings() {
        settingsWindowController.show()
    }

    func quit() {
        NSApp.terminate(nil)
    }
}
