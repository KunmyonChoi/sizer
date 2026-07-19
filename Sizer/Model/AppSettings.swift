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

    // MARK: processed 자동 정리
    @Published var autoCleanProcessedEnabled: Bool { didSet { save(autoCleanProcessedEnabled, .autoCleanProcessed) } }
    @Published var processedRetentionDays: Int { didSet { save(processedRetentionDays, .processedRetentionDays) } }

    // MARK: 플로팅 드롭 타겟
    @Published var dropTargetShown: Bool { didSet { save(dropTargetShown, .dropTargetShown) } }

    // MARK: 인코딩
    @Published var videoCodecRaw: String { didSet { save(videoCodecRaw, .videoCodec) } }
    @Published var crf: Int { didSet { save(crf, .crf) } }
    @Published var preset: String { didSet { save(preset, .preset) } }
    @Published var maxLongEdge: Int { didSet { save(maxLongEdge, .maxLongEdge) } }
    @Published var audioBitrate: String { didSet { save(audioBitrate, .audioBitrate) } }
    @Published var outputSuffix: String { didSet { save(outputSuffix, .outputSuffix) } }

    // MARK: 트리밍
    @Published var trimStill: Bool { didSet { save(trimStill, .trimStill) } }
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
            trimStill: trimStill,
            trimOptions: trimOptions,
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

        autoCleanProcessedEnabled = defaults.object(forKey: Key.autoCleanProcessed.rawValue) as? Bool ?? true
        processedRetentionDays = defaults.object(forKey: Key.processedRetentionDays.rawValue) as? Int ?? 30

        videoCodecRaw = defaults.string(forKey: Key.videoCodec.rawValue) ?? VideoCodec.h264.rawValue
        crf = defaults.object(forKey: Key.crf.rawValue) as? Int ?? 26
        preset = defaults.string(forKey: Key.preset.rawValue) ?? "slow"
        maxLongEdge = defaults.object(forKey: Key.maxLongEdge.rawValue) as? Int ?? 1920
        audioBitrate = defaults.string(forKey: Key.audioBitrate.rawValue) ?? "128k"
        outputSuffix = defaults.string(forKey: Key.outputSuffix.rawValue) ?? "_resize"

        trimStill = defaults.object(forKey: Key.trimStill.rawValue) as? Bool ?? true
        sensitivityRaw = defaults.string(forKey: Key.sensitivity.rawValue) ?? SensitivityPreset.balanced.rawValue
        stillNoiseDb = defaults.object(forKey: Key.stillNoiseDb.rawValue) as? Double ?? -50.0
        stillMinDuration = defaults.object(forKey: Key.stillMinDuration.rawValue) as? Double ?? 2.0
        mergeGapMax = defaults.object(forKey: Key.mergeGapMax.rawValue) as? Double ?? 0.5
        minKeep = defaults.object(forKey: Key.minKeep.rawValue) as? Double ?? 0.3
        pad = defaults.object(forKey: Key.pad.rawValue) as? Double ?? 0.15
        smoothTransitions = defaults.object(forKey: Key.smoothTransitions.rawValue) as? Bool ?? false
        minKeepRatio = defaults.object(forKey: Key.minKeepRatio.rawValue) as? Double ?? 0.02

        imageConversionEnabled = defaults.object(forKey: Key.imageEnabled.rawValue) as? Bool ?? true
        imageFormatRaw = defaults.string(forKey: Key.imageFormat.rawValue) ?? ImageFormat.avif.rawValue
        imageQuality = defaults.object(forKey: Key.imageQuality.rawValue) as? Double ?? 0.8
        imageMaxLongEdge = defaults.object(forKey: Key.imageMaxLongEdge.rawValue) as? Int ?? 0

        dropTargetShown = defaults.object(forKey: Key.dropTargetShown.rawValue) as? Bool ?? false
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
        case launchAtLogin, notificationsEnabled
        case autoCleanProcessed, processedRetentionDays
        case videoCodec, crf, preset, maxLongEdge, audioBitrate, outputSuffix
        case trimStill, sensitivity, stillNoiseDb, stillMinDuration
        case mergeGapMax, minKeep, pad, smoothTransitions, minKeepRatio
        case imageEnabled, imageFormat, imageQuality, imageMaxLongEdge
        case dropTargetShown
    }

    private func save(_ value: Any, _ key: Key) {
        defaults.set(value, forKey: key.rawValue)
    }
}
