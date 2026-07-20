import Foundation
import Combine

/// 사용자 설정(영속). SwiftUI 설정 화면이 바인딩하고, 코디네이터가 ConversionConfig로 스냅샷한다.
@MainActor
final class AppSettings: ObservableObject {

    private let defaults: UserDefaults

    // MARK: 폴더
    @Published var dropFolderPath: String { didSet { save(dropFolderPath, .dropFolder) } }
    @Published var outputFolderPath: String { didSet { save(outputFolderPath, .outputFolder) } }
    @Published var processedFolderPath: String { didSet { save(processedFolderPath, .processedFolder) } }
    @Published var failedFolderPath: String { didSet { save(failedFolderPath, .failedFolder) } }

    // MARK: 일반
    @Published var launchAtLogin: Bool { didSet { save(launchAtLogin, .launchAtLogin) } }
    @Published var notificationsEnabled: Bool { didSet { save(notificationsEnabled, .notificationsEnabled) } }
    @Published var openOutputAfterDrop: Bool { didSet { save(openOutputAfterDrop, .openOutputAfterDrop) } }

    // MARK: processed 자동 정리
    @Published var autoCleanProcessedEnabled: Bool { didSet { save(autoCleanProcessedEnabled, .autoCleanProcessed) } }
    @Published var processedRetentionDays: Int { didSet { save(processedRetentionDays, .processedRetentionDays) } }

    // MARK: 플로팅 드롭 타겟 / 파일 셸프
    @Published var dropTargetShown: Bool { didSet { save(dropTargetShown, .dropTargetShown) } }
    @Published var shelfShown: Bool { didSet { save(shelfShown, .shelfShown) } }
    @Published var integratedDrop: Bool { didSet { save(integratedDrop, .integratedDrop) } }   // 드롭 타겟을 셸프에 통합
    @Published var addResultToShelf: Bool { didSet { save(addResultToShelf, .addResultToShelf) } }   // S5: 변환 결과 셸프에 얹기
    @Published var shelfSideRaw: String { didSet { save(shelfSideRaw, .shelfSide) } }          // 패널 도킹 가장자리(left/right)

    // MARK: 글로벌 단축키(패널 열기/닫기)
    @Published var shortcutKeyCode: Int { didSet { save(shortcutKeyCode, .shortcutKeyCode) } }        // NSEvent.keyCode(가상 키코드)
    @Published var shortcutModifiers: Int { didSet { save(shortcutModifiers, .shortcutModifiers) } }  // NSEvent.ModifierFlags rawValue
    @Published var shortcutDisplay: String { didSet { save(shortcutDisplay, .shortcutDisplay) } }     // 표시용(예 "⌥⌘S")

    // MARK: 인코딩
    @Published var videoCodecRaw: String { didSet { save(videoCodecRaw, .videoCodec) } }
    @Published var crf: Int { didSet { save(crf, .crf) } }
    @Published var preset: String { didSet { save(preset, .preset) } }
    @Published var maxLongEdge: Int { didSet { save(maxLongEdge, .maxLongEdge) } }
    @Published var audioBitrate: String { didSet { save(audioBitrate, .audioBitrate) } }
    @Published var outputSuffix: String { didSet { save(outputSuffix, .outputSuffix) } }

    // MARK: 정지/저모션 구간 처리
    @Published var stillModeRaw: String { didSet { save(stillModeRaw, .stillMode) } }
    @Published var ffSpeed: Int { didSet { save(ffSpeed, .ffSpeed) } }
    @Published var ffMinDuration: Double { didSet { save(ffMinDuration, .ffMinDuration) } }
    @Published var ffMuteAudio: Bool { didSet { save(ffMuteAudio, .ffMuteAudio) } }
    @Published var ffBadge: Bool { didSet { save(ffBadge, .ffBadge) } }
    @Published var sensitivityRaw: String { didSet { save(sensitivityRaw, .sensitivity) } }
    @Published var stillNoiseDb: Double { didSet { save(stillNoiseDb, .stillNoiseDb) } }
    @Published var stillMinDuration: Double { didSet { save(stillMinDuration, .stillMinDuration) } }
    @Published var mergeGapMax: Double { didSet { save(mergeGapMax, .mergeGapMax) } }
    @Published var minKeep: Double { didSet { save(minKeep, .minKeep) } }
    @Published var pad: Double { didSet { save(pad, .pad) } }
    @Published var smoothTransitions: Bool { didSet { save(smoothTransitions, .smoothTransitions) } }
    @Published var minKeepRatio: Double { didSet { save(minKeepRatio, .minKeepRatio) } }

    // MARK: 이미지(캡처)
    @Published var imageConversionEnabled: Bool { didSet { save(imageConversionEnabled, .imageEnabled) } }
    @Published var imageFormatRaw: String { didSet { save(imageFormatRaw, .imageFormat) } }
    @Published var imageQuality: Double { didSet { save(imageQuality, .imageQuality) } }
    @Published var imageMaxLongEdge: Int { didSet { save(imageMaxLongEdge, .imageMaxLongEdge) } }

    // MARK: 파생

    var videoCodec: VideoCodec {
        get { VideoCodec(rawValue: videoCodecRaw) ?? .h264 }
        set { videoCodecRaw = newValue.rawValue }
    }

    var sensitivity: SensitivityPreset {
        get { SensitivityPreset(rawValue: sensitivityRaw) ?? .balanced }
        set { sensitivityRaw = newValue.rawValue }
    }

    var imageFormat: ImageFormat {
        get { ImageFormat(rawValue: imageFormatRaw) ?? .avif }
        set { imageFormatRaw = newValue.rawValue }
    }

    var stillMode: StillMode {
        get { StillMode(rawValue: stillModeRaw) ?? .off }
        set { stillModeRaw = newValue.rawValue }
    }

    var shelfSide: ShelfSide {
        get { ShelfSide(rawValue: shelfSideRaw) ?? .left }
        set { shelfSideRaw = newValue.rawValue }
    }

    var hasShortcut: Bool { shortcutKeyCode != 0 || shortcutModifiers != 0 }

    /// 단축키 저장(레코더에서 호출). 표시 문자열도 함께 보관.
    func setShortcut(keyCode: Int, modifiers: Int, display: String) {
        shortcutKeyCode = keyCode
        shortcutModifiers = modifiers
        shortcutDisplay = display
    }

    func clearShortcut() {
        shortcutKeyCode = 0
        shortcutModifiers = 0
        shortcutDisplay = ""
    }

    var dropFolderURL: URL { URL(fileURLWithPath: dropFolderPath, isDirectory: true) }
    var outputFolderURL: URL { URL(fileURLWithPath: outputFolderPath, isDirectory: true) }
    var processedFolderURL: URL { URL(fileURLWithPath: processedFolderPath, isDirectory: true) }
    var failedFolderURL: URL { URL(fileURLWithPath: failedFolderPath, isDirectory: true) }

    /// 트리밍 후처리/감지 옵션 스냅샷.
    var trimOptions: TrimOptions {
        TrimOptions(
            noiseDb: stillNoiseDb,
            minStillDuration: stillMinDuration,
            mergeGapMax: mergeGapMax,
            minKeep: minKeep,
            pad: pad,
            minKeepRatio: minKeepRatio,
            smoothTransitions: smoothTransitions
        )
    }

    /// 변환 잡용 불변 스냅샷.
    var config: ConversionConfig {
        ConversionConfig(
            dropFolder: dropFolderURL,
            outputFolder: outputFolderURL,
            processedFolder: processedFolderURL,
            failedFolder: failedFolderURL,
            codec: videoCodec,
            crf: crf,
            preset: preset,
            maxLongEdge: maxLongEdge,
            audioBitrate: audioBitrate,
            outputSuffix: outputSuffix,
            stillMode: stillMode,
            trimOptions: trimOptions,
            ffSpeed: ffSpeed,
            ffMinDuration: ffMinDuration,
            ffMuteAudio: ffMuteAudio,
            ffBadge: ffBadge,
            imageEnabled: imageConversionEnabled,
            imageFormat: imageFormat,
            imageQuality: imageQuality,
            imageMaxLongEdge: imageMaxLongEdge,
            notificationsEnabled: notificationsEnabled
        )
    }

    /// 민감도 프리셋 적용(개별 감지 파라미터를 프리셋값으로 덮어씀).
    func applySensitivityPreset(_ preset: SensitivityPreset) {
        sensitivity = preset
        let d = preset.detection
        stillNoiseDb = d.noiseDb
        stillMinDuration = d.minStill
        mergeGapMax = d.mergeGapMax
    }

    // MARK: 초기화

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let base = AppSettings.defaultBaseFolder

        dropFolderPath = defaults.string(forKey: Key.dropFolder.rawValue) ?? base.appendingPathComponent("drop").path
        outputFolderPath = defaults.string(forKey: Key.outputFolder.rawValue) ?? base.appendingPathComponent("output").path
        processedFolderPath = defaults.string(forKey: Key.processedFolder.rawValue) ?? base.appendingPathComponent("processed").path
        failedFolderPath = defaults.string(forKey: Key.failedFolder.rawValue) ?? base.appendingPathComponent("failed").path

        launchAtLogin = defaults.object(forKey: Key.launchAtLogin.rawValue) as? Bool ?? false
        notificationsEnabled = defaults.object(forKey: Key.notificationsEnabled.rawValue) as? Bool ?? true
        openOutputAfterDrop = defaults.object(forKey: Key.openOutputAfterDrop.rawValue) as? Bool ?? true

        autoCleanProcessedEnabled = defaults.object(forKey: Key.autoCleanProcessed.rawValue) as? Bool ?? true
        processedRetentionDays = defaults.object(forKey: Key.processedRetentionDays.rawValue) as? Int ?? 30

        videoCodecRaw = defaults.string(forKey: Key.videoCodec.rawValue) ?? VideoCodec.h264.rawValue
        crf = defaults.object(forKey: Key.crf.rawValue) as? Int ?? 26
        preset = defaults.string(forKey: Key.preset.rawValue) ?? "slow"
        maxLongEdge = defaults.object(forKey: Key.maxLongEdge.rawValue) as? Int ?? 1920
        audioBitrate = defaults.string(forKey: Key.audioBitrate.rawValue) ?? "128k"
        outputSuffix = defaults.string(forKey: Key.outputSuffix.rawValue) ?? "_resize"

        // stillMode: 신규 기본 '빨리감기'. 기존 trimStill 값이 있으면 마이그레이션(true→잘라내기, false→끔).
        if let saved = defaults.string(forKey: Key.stillMode.rawValue) {
            stillModeRaw = saved
        } else if let legacy = defaults.object(forKey: Key.trimStill.rawValue) as? Bool {
            stillModeRaw = legacy ? StillMode.trim.rawValue : StillMode.off.rawValue
        } else {
            stillModeRaw = StillMode.fastForward.rawValue
        }
        ffSpeed = defaults.object(forKey: Key.ffSpeed.rawValue) as? Int ?? 4
        ffMinDuration = defaults.object(forKey: Key.ffMinDuration.rawValue) as? Double ?? 2.0
        ffMuteAudio = defaults.object(forKey: Key.ffMuteAudio.rawValue) as? Bool ?? true
        ffBadge = defaults.object(forKey: Key.ffBadge.rawValue) as? Bool ?? true
        // 감지 민감도: 신규 기본 '보수적'(-58dB / 최소정지 3.0s / 병합 0.7s).
        sensitivityRaw = defaults.string(forKey: Key.sensitivity.rawValue) ?? SensitivityPreset.conservative.rawValue
        stillNoiseDb = defaults.object(forKey: Key.stillNoiseDb.rawValue) as? Double ?? -58.0
        stillMinDuration = defaults.object(forKey: Key.stillMinDuration.rawValue) as? Double ?? 3.0
        mergeGapMax = defaults.object(forKey: Key.mergeGapMax.rawValue) as? Double ?? 0.7
        minKeep = defaults.object(forKey: Key.minKeep.rawValue) as? Double ?? 0.3
        pad = defaults.object(forKey: Key.pad.rawValue) as? Double ?? 0.15
        smoothTransitions = defaults.object(forKey: Key.smoothTransitions.rawValue) as? Bool ?? false
        minKeepRatio = defaults.object(forKey: Key.minKeepRatio.rawValue) as? Double ?? 0.02

        imageConversionEnabled = defaults.object(forKey: Key.imageEnabled.rawValue) as? Bool ?? true
        imageFormatRaw = defaults.string(forKey: Key.imageFormat.rawValue) ?? ImageFormat.avif.rawValue
        imageQuality = defaults.object(forKey: Key.imageQuality.rawValue) as? Double ?? 0.8
        imageMaxLongEdge = defaults.object(forKey: Key.imageMaxLongEdge.rawValue) as? Int ?? 0

        let integrated = defaults.object(forKey: Key.integratedDrop.rawValue) as? Bool ?? true      // 통합이 기본
        integratedDrop = integrated
        addResultToShelf = defaults.object(forKey: Key.addResultToShelf.rawValue) as? Bool ?? true
        shelfSideRaw = defaults.string(forKey: Key.shelfSide.rawValue) ?? ShelfSide.right.rawValue
        shortcutKeyCode = defaults.object(forKey: Key.shortcutKeyCode.rawValue) as? Int ?? 0
        shortcutModifiers = defaults.object(forKey: Key.shortcutModifiers.rawValue) as? Int ?? 0
        shortcutDisplay = defaults.string(forKey: Key.shortcutDisplay.rawValue) ?? ""

        dropTargetShown = defaults.object(forKey: Key.dropTargetShown.rawValue) as? Bool ?? true   // 기본 보이기(분리 모드에서만 의미)
        // 통합 모드에선 셸프가 드롭 표면이므로 기본 표시, 분리 모드에선 기본 감춤.
        if let shown = defaults.object(forKey: Key.shelfShown.rawValue) as? Bool {
            shelfShown = shown
        } else {
            shelfShown = integrated
        }
    }

    /// 기본 베이스 폴더: ~/Movies/Sizer
    static var defaultBaseFolder: URL {
        let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Movies")
        return movies.appendingPathComponent("Sizer", isDirectory: true)
    }

    /// 설정된 모든 폴더를 생성.
    func ensureFolders() {
        for url in [dropFolderURL, outputFolderURL, processedFolderURL, failedFolderURL] {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    // MARK: 영속화 헬퍼

    private enum Key: String {
        case dropFolder, outputFolder, processedFolder, failedFolder
        case launchAtLogin, notificationsEnabled, openOutputAfterDrop
        case autoCleanProcessed, processedRetentionDays
        case videoCodec, crf, preset, maxLongEdge, audioBitrate, outputSuffix
        case trimStill   // 레거시(마이그레이션용)
        case stillMode, ffSpeed, ffMinDuration, ffMuteAudio, ffBadge
        case sensitivity, stillNoiseDb, stillMinDuration
        case mergeGapMax, minKeep, pad, smoothTransitions, minKeepRatio
        case imageEnabled, imageFormat, imageQuality, imageMaxLongEdge
        case dropTargetShown, shelfShown, integratedDrop, addResultToShelf, shelfSide
        case shortcutKeyCode, shortcutModifiers, shortcutDisplay
    }

    private func save(_ value: Any, _ key: Key) {
        defaults.set(value, forKey: key.rawValue)
    }
}
