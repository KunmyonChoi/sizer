import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// Linux 백그라운드 감시 데몬 — macOS WatchCoordinator 의 헤드리스 판(패널·창 스냅 없음).
///
/// 드롭 폴더를 inotify + 30초 재스캔으로 감시해 한 번에 한 파일씩 변환하고, 결과를 버튼 달린 알림으로 알린다.
/// processed 자동 정리(1시간마다)와 설정 파일 자동 재적용(저장 즉시, SIGHUP 도 같음)을 맡는다.
/// 상태는 status.json 으로 트레이(sizer-tray)에 알리고, SIGUSR1/SIGUSR2 로 일시정지/재개한다(`sizer pause|resume`).
/// systemd 사용자 서비스(sizer.service)가 `sizer daemon` 으로 실행한다.
final class Daemon {
    /// 아래 가변 상태는 모두 이 큐에서만 만진다.
    private let queue = DispatchQueue(label: "com.dilly.sizer.daemon")
    private let workQueue = DispatchQueue(label: "com.dilly.sizer.convert")   // 직렬(동시에 1개)
    private let configURL: URL
    private let statusURL: URL
    private let recentURL: URL
    private var settings: LinuxSettings
    private var watcher: FolderWatcher?
    private var configWatcher: FolderWatcher?
    private var active: Set<String> = []       // 큐잉/변환 중인 파일 경로
    private var current: String?               // 변환 중인 파일명
    private var paused = false
    private var recent: [StatusReport.Job]
    private var lastReport: StatusReport?
    private var sources: [DispatchSourceProtocol] = []
    private var reloadWork: DispatchWorkItem?
    private var openOutputWork: DispatchWorkItem?
    private var warnedMissingFFmpeg = false

    init(settings: LinuxSettings, configURL: URL = Paths.configFile,
         statusURL: URL = StatusReport.fileURL, recentURL: URL = StatusReport.recentURL) {
        self.settings = settings
        self.configURL = configURL
        self.statusURL = statusURL
        self.recentURL = recentURL
        self.recent = StatusReport.loadRecent(from: recentURL)
    }

    static func isRunning() -> Bool { InstanceLock.isHeld() }

    /// 감시를 시작한다. 호출한 쪽은 dispatchMain() 으로 메인 스레드를 넘긴다.
    func start() {
        queue.async { [self] in
            settings.ensureFolders()
            logStartup()
            restartWatcher()
            watchConfig()
            repeatEvery(30) { $0.scan() }
            repeatEvery(3600, startNow: true) { $0.runProcessedCleanup() }
            onSignal(SIGHUP) { $0.reloadSettings(reason: "SIGHUP") }
            onSignal(SIGUSR1) { $0.setPaused(true) }
            onSignal(SIGUSR2) { $0.setPaused(false) }
            for sig in [SIGTERM, SIGINT] {
                onSignal(sig) { daemon in
                    try? FileManager.default.removeItem(at: daemon.statusURL)   // 트레이가 낡은 상태를 보이지 않게
                    AppLogger.info("종료")
                    exit(0)
                }
            }
            publishStatus()
            scan()
        }
    }

    // MARK: 스캔 & 변환

    private func scan() {
        defer { publishStatus() }
        guard !paused else { return }
        let config = settings.config
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: settings.dropFolder, includingPropertiesForKeys: nil) else { return }

        for url in items.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let name = url.lastPathComponent
            if name.hasPrefix(".") { continue }
            let ext = url.pathExtension.lowercased()
            if ext == "part" { continue }

            if ConversionConfig.videoExtensions.contains(ext) {
                guard FFmpeg.isAvailable else {
                    if !warnedMissingFFmpeg {
                        AppLogger.error("ffmpeg가 없어 영상을 변환할 수 없습니다 — sudo apt install ffmpeg")
                        warnedMissingFFmpeg = true
                    }
                    continue
                }
            } else if ConversionConfig.imageExtensions.contains(ext) {
                guard config.imageEnabled else { continue }
            } else {
                continue
            }

            let key = url.path
            if active.contains(key) { continue }
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: key, isDirectory: &isDir), !isDir.boolValue else { continue }

            active.insert(key)
            submit(url, key: key, config: config)
        }
    }

    private func submit(_ url: URL, key: String, config: ConversionConfig) {
        workQueue.async { [weak self] in
            guard let self else { return }
            guard Daemon.waitUntilStable(url) else {
                AppLogger.info("복사 중으로 판단, 대기: \(url.lastPathComponent)")
                self.queue.async {
                    self.active.remove(key)
                    self.publishStatus()
                }
                return
            }
            // 기다리는 사이 일시정지됐으면 시작하지 않는다(재개하면 스캔이 다시 넣는다).
            let proceed = self.queue.sync { () -> Bool in
                guard !self.paused else {
                    self.active.remove(key)
                    self.publishStatus()
                    return false
                }
                self.current = url.lastPathComponent
                self.publishStatus()
                return true
            }
            guard proceed else { return }
            let outcome = ConversionEngine.process(url, config: config)
            self.queue.async { self.finish(outcome, key: key) }
        }
    }

    private func finish(_ outcome: JobOutcome, key: String) {
        active.remove(key)
        current = nil
        recent = StatusReport.appending(StatusReport.Job(outcome), to: recent)
        StatusReport.saveRecent(recent, to: recentURL)
        let added = AddedMarks.take(outcome.sourceName)
        if settings.notifications {
            Notifier.notifyOutcome(outcome, withActions: true)
        }
        if outcome.success, added, settings.openOutputAfterAdd {
            scheduleOpenOutput()
        }
        scan()   // 대기 중이던 다른 파일 픽업(+ 상태 발행)
    }

    private func setPaused(_ value: Bool) {
        guard paused != value else { return }
        paused = value
        AppLogger.info(value ? "감시 일시정지" : "감시 재개")
        scan()
    }

    /// 상태가 바뀌었을 때만 status.json 을 다시 쓴다.
    private func publishStatus() {
        let report = StatusReport(
            version: BuildInfo.version,
            pid: getpid(),
            state: paused ? .paused : (current != nil ? .converting : .watching),
            current: current,
            queued: max(0, active.count - (current == nil ? 0 : 1)),
            ffmpegAvailable: FFmpeg.isAvailable,
            dropFolder: settings.dropFolder.path,
            outputFolder: settings.outputFolder.path,
            failedFolder: settings.failedFolder.path,
            recent: recent
        )
        guard report != lastReport else { return }
        report.write(to: statusURL)
        lastReport = report
    }

    /// 파일 크기가 연속으로 같아질 때까지 대기(복사 완료 판정). WatchCoordinator.waitUntilStable 과 같다.
    static func waitUntilStable(_ url: URL, checks: Int = 3, interval: TimeInterval = 1.0) -> Bool {
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

    /// add 로 넣은 배치가 끝나면 출력 폴더를 한 번만 연다(짧게 디바운스).
    private func scheduleOpenOutput() {
        openOutputWork?.cancel()
        let folder = settings.outputFolder
        let work = DispatchWorkItem { Desktop.open(folder) }
        openOutputWork = work
        queue.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    private func runProcessedCleanup() {
        let days = settings.processedRetentionDays
        guard days > 0 else { return }
        let folder = settings.processedFolder
        DispatchQueue.global(qos: .utility).async {
            let n = ProcessedCleaner.clean(folder: folder, olderThanDays: days)
            if n > 0 { AppLogger.info("processed 자동 정리: \(n)개 삭제(\(days)일 초과)") }
        }
    }

    // MARK: 감시 · 설정

    private func restartWatcher() {
        watcher?.stop()
        let w = FolderWatcher(path: settings.dropFolder.path) { [weak self] in
            guard let self else { return }
            self.queue.async { self.scan() }
        }
        w.start()
        watcher = w
    }

    /// 설정 폴더를 감시해 config.json 이 저장되면 다시 읽는다. 편집기는 임시 파일 저장 → 이름 바꾸기로
    /// 이벤트를 여러 번 내므로 잠깐 모았다가 한 번만 읽는다.
    private func watchConfig() {
        let dir = configURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let w = FolderWatcher(path: dir.path) { [weak self] in
            guard let self else { return }
            self.queue.async {
                self.reloadWork?.cancel()
                let work = DispatchWorkItem { [weak self] in self?.reloadSettings(reason: "설정 파일 변경") }
                self.reloadWork = work
                self.queue.asyncAfter(deadline: .now() + 0.5, execute: work)
            }
        }
        w.start()
        configWatcher = w
    }

    private func reloadSettings(reason: String) {
        do {
            let (new, warnings) = try LinuxSettings.loadOrCreate(at: configURL)
            warnings.forEach { AppLogger.warn("설정: \($0)") }
            let dropChanged = new.dropFolder != settings.dropFolder
            settings = new
            settings.ensureFolders()
            AppLogger.info("설정 다시 읽음(\(reason))")
            if dropChanged { restartWatcher() }
            scan()
        } catch {
            AppLogger.error("설정 파일 오류 — 이전 설정 유지: \(error)")
            if settings.notifications {
                Notifier.notify(title: "Sizer 설정 파일 오류", body: "\(error)", subtitle: "이전 설정으로 계속 동작합니다")
            }
        }
    }

    private func logStartup() {
        AppLogger.info("Sizer \(BuildInfo.version) 데몬 시작 — 드롭 폴더: \(settings.dropFolder.path)")
        AppLogger.info("출력: \(settings.outputFolder.path) · 설정: \(configURL.path)")
        if let ffmpeg = FFmpeg.ffmpegURL {
            AppLogger.info("ffmpeg: \(ffmpeg.path)")
        } else {
            AppLogger.error("ffmpeg 없음 — 영상 변환 불가(sudo apt install ffmpeg)")
            warnedMissingFFmpeg = true
        }
        if settings.notifications, Executables.find("notify-send") == nil {
            AppLogger.warn("notify-send 없음 — 알림을 표시하지 않습니다(sudo apt install libnotify-bin)")
        }
        if settings.imageEnabled, settings.imageFormat == .heic, !ImageConverter.heicEncodingAvailable() {
            AppLogger.warn("HEIC 출력에는 heif-enc와 HEVC 플러그인이 필요합니다(sudo apt install libheif-examples libheif-plugin-x265)")
        }
    }

    // MARK: 타이머 · 시그널

    private func repeatEvery(_ interval: TimeInterval, startNow: Bool = false, _ body: @escaping (Daemon) -> Void) {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: startNow ? .now() : .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            if let self { body(self) }
        }
        timer.resume()
        sources.append(timer)
    }

    private func onSignal(_ sig: Int32, _ body: @escaping (Daemon) -> Void) {
        signal(sig, SIG_IGN)   // 기본 동작(종료)을 끄고 디스패치 소스로 받는다
        let source = DispatchSource.makeSignalSource(signal: sig, queue: queue)
        source.setEventHandler { [weak self] in
            if let self { body(self) }
        }
        source.resume()
        sources.append(source)
    }
}
