import Foundation

/// Linux 설정 — ~/.config/sizer/config.json. macOS 의 설정 화면 + UserDefaults(AppSettings)에 해당한다.
///
/// 모든 키는 생략할 수 있고, 없으면 macOS 앱과 같은 기본값을 쓴다. 값이 틀리면 그 항목만 기본값으로 두고 경고를
/// 남긴다(한 줄 실수로 데몬이 멈추지 않게). JSON 자체가 깨졌거나 타입이 틀리면 parse 가 오류를 던진다.
struct LinuxSettings {
    var dropFolder: URL
    var outputFolder: URL
    var processedFolder: URL
    var failedFolder: URL

    var notifications = true
    /// `sizer add`(파일 관리자 우클릭)로 넣은 파일의 변환이 끝나면 출력 폴더를 연다 — macOS 드롭 타겟과 같은 동작.
    var openOutputAfterAdd = true
    /// processed 원본 보관 일수. 0 이면 자동 정리 끔.
    var processedRetentionDays = 30

    var codec: VideoCodec = .h264
    var crf = 26
    var preset = "slow"
    var maxLongEdge = 1920
    var audioBitrate = "128k"
    var outputSuffix = "_resize"

    var stillMode: StillMode = .fastForward
    var sensitivity: SensitivityPreset = .conservative
    var trimOptions = LinuxSettings.trimOptions(for: .conservative)
    var adaptiveThreshold = false
    var ffSpeed = 4
    var ffMinDuration = 2.0
    var ffMuteAudio = true
    var ffBadge = true

    var imageEnabled = true
    var imageFormat: ImageFormat = .avif
    var imageQuality = 0.8
    var imageMaxLongEdge = 0

    init(baseFolder: URL = LinuxSettings.defaultBaseFolder) {
        dropFolder = baseFolder.appendingPathComponent("drop", isDirectory: true)
        outputFolder = baseFolder.appendingPathComponent("output", isDirectory: true)
        processedFolder = baseFolder.appendingPathComponent("processed", isDirectory: true)
        failedFolder = baseFolder.appendingPathComponent("failed", isDirectory: true)
    }

    /// 기본 베이스 폴더: 동영상 폴더/Sizer (예: ~/Videos/Sizer, ~/비디오/Sizer)
    static var defaultBaseFolder: URL { Paths.videosDir.appendingPathComponent("Sizer", isDirectory: true) }

    /// 민감도 프리셋의 감지값 + macOS 기본 후처리값.
    static func trimOptions(for preset: SensitivityPreset) -> TrimOptions {
        let d = preset.detection
        return TrimOptions(noiseDb: d.noiseDb, minStillDuration: d.minStill, mergeGapMax: d.mergeGapMax,
                           minKeep: 0.3, pad: 0.15, minKeepRatio: 0.02, smoothTransitions: false)
    }

    /// 변환 잡용 스냅샷. 알림은 엔진이 아니라 데몬/CLI 가 버튼을 달아 직접 보내므로 끈다.
    var config: ConversionConfig {
        ConversionConfig(
            dropFolder: dropFolder, outputFolder: outputFolder,
            processedFolder: processedFolder, failedFolder: failedFolder,
            codec: codec, crf: crf, preset: preset, maxLongEdge: maxLongEdge,
            audioBitrate: audioBitrate, outputSuffix: outputSuffix,
            stillMode: stillMode, trimOptions: trimOptions, adaptiveThreshold: adaptiveThreshold,
            ffSpeed: ffSpeed, ffMinDuration: ffMinDuration, ffMuteAudio: ffMuteAudio, ffBadge: ffBadge,
            imageEnabled: imageEnabled, imageFormat: imageFormat, imageQuality: imageQuality,
            imageMaxLongEdge: imageMaxLongEdge,
            notificationsEnabled: false
        )
    }

    func ensureFolders() {
        for url in [dropFolder, outputFolder, processedFolder, failedFolder] {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    // MARK: 읽기

    struct ParseError: Error, CustomStringConvertible {
        let description: String
    }

    /// 설정 파일을 읽는다. 없으면 기본 설정 파일을 만들어 두고(찾아서 고칠 수 있게) 기본값을 쓴다.
    static func loadOrCreate(at url: URL = Paths.configFile) throws -> (settings: LinuxSettings, warnings: [String]) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? defaultTemplate().write(to: url, atomically: true, encoding: .utf8)
            return (LinuxSettings(), [])
        }
        return try parse(Data(contentsOf: url))
    }

    static func parse(_ data: Data, baseFolder: URL = defaultBaseFolder,
                      home: String = Paths.home.path) throws -> (settings: LinuxSettings, warnings: [String]) {
        let file: File
        do {
            file = try JSONDecoder().decode(File.self, from: data)
        } catch let DecodingError.typeMismatch(type, context) {
            throw ParseError(description: "\(keyPath(context.codingPath)): \(type) 값이어야 합니다")
        } catch let DecodingError.dataCorrupted(context) {
            let detail = (context.underlyingError as NSError?)?.userInfo[NSDebugDescriptionErrorKey] as? String
            throw ParseError(description: "JSON 형식 오류\(detail.map { ": \($0)" } ?? "")")
        } catch {
            throw ParseError(description: "\(error)")
        }

        var warnings = unknownKeys(in: data).map { "알 수 없는 키 \"\($0)\" — 무시" }
        var s = LinuxSettings(baseFolder: baseFolder)

        func folder(_ raw: String?, _ key: String, _ current: URL) -> URL {
            guard let raw else { return current }
            let path = Paths.expand(raw, home: home)
            guard path.hasPrefix("/") else {
                warnings.append("folders.\(key): 절대경로나 ~ 로 시작해야 합니다 — 기본값 사용")
                return current
            }
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        func choice<T>(_ raw: String?, _ key: String, _ current: T, _ make: (String) -> T?, hint: String = "") -> T {
            guard let raw else { return current }
            if let value = make(raw) { return value }
            warnings.append("\(key): 알 수 없는 값 \"\(raw)\"\(hint) — 기본값 사용")
            return current
        }
        func ranged<T: Comparable>(_ raw: T?, _ key: String, _ range: ClosedRange<T>, _ current: T) -> T {
            guard let raw else { return current }
            if range.contains(raw) { return raw }
            warnings.append("\(key): \(range.lowerBound)~\(range.upperBound) 범위여야 합니다 — 기본값 사용")
            return current
        }

        s.dropFolder = folder(file.folders?.drop, "drop", s.dropFolder)
        s.outputFolder = folder(file.folders?.output, "output", s.outputFolder)
        s.processedFolder = folder(file.folders?.processed, "processed", s.processedFolder)
        s.failedFolder = folder(file.folders?.failed, "failed", s.failedFolder)
        // 출력이 드롭 폴더면 결과를 다시 변환하는 무한 반복이 된다.
        if s.outputFolder.standardizedFileURL == s.dropFolder.standardizedFileURL {
            warnings.append("folders.output: 드롭 폴더와 같으면 결과가 다시 변환됩니다 — 기본값 사용")
            s.outputFolder = LinuxSettings(baseFolder: baseFolder).outputFolder
        }

        s.notifications = file.notifications ?? s.notifications
        s.openOutputAfterAdd = file.openOutputAfterAdd ?? s.openOutputAfterAdd
        s.processedRetentionDays = ranged(file.processedRetentionDays, "processedRetentionDays", 0...36500, s.processedRetentionDays)

        if let v = file.video {
            s.codec = choice(v.codec, "video.codec", s.codec, {
                let codec = VideoCodec(rawValue: $0)
                return codec?.usesCRF == true ? codec : nil
            }, hint: " (libx264 또는 libx265)")
            s.crf = ranged(v.crf, "video.crf", 0...51, s.crf)
            s.preset = choice(v.preset, "video.preset", s.preset, { presets.contains($0) ? $0 : nil })
            s.maxLongEdge = ranged(v.maxLongEdge, "video.maxLongEdge", 16...16384, s.maxLongEdge)
            s.audioBitrate = v.audioBitrate ?? s.audioBitrate
            s.outputSuffix = v.outputSuffix ?? s.outputSuffix
        }

        if let st = file.still {
            s.stillMode = choice(st.mode, "still.mode", s.stillMode, StillMode.init(rawValue:),
                                 hint: " (off, trim, fastForward)")
            s.sensitivity = choice(st.sensitivity, "still.sensitivity", s.sensitivity, SensitivityPreset.init(rawValue:),
                                   hint: " (aggressive, balanced, conservative)")
            var t = trimOptions(for: s.sensitivity)
            t.noiseDb = ranged(st.noiseDb, "still.noiseDb", -90...0, t.noiseDb)
            t.minStillDuration = ranged(st.minStillDuration, "still.minStillDuration", 0.1...600, t.minStillDuration)
            t.mergeGapMax = ranged(st.mergeGapMax, "still.mergeGapMax", 0...60, t.mergeGapMax)
            t.minKeep = ranged(st.minKeep, "still.minKeep", 0...60, t.minKeep)
            t.pad = ranged(st.pad, "still.pad", 0...10, t.pad)
            t.minKeepRatio = ranged(st.minKeepRatio, "still.minKeepRatio", 0...1, t.minKeepRatio)
            t.smoothTransitions = st.smoothTransitions ?? t.smoothTransitions
            s.trimOptions = t
            s.adaptiveThreshold = st.adaptiveThreshold ?? s.adaptiveThreshold
            s.ffSpeed = choice(st.fastForwardSpeed.map(String.init), "still.fastForwardSpeed", s.ffSpeed,
                               { [2, 4, 8].contains(Int($0) ?? 0) ? Int($0) : nil }, hint: " (2, 4, 8)")
            s.ffMinDuration = ranged(st.fastForwardMinDuration, "still.fastForwardMinDuration", 0.1...600, s.ffMinDuration)
            s.ffMuteAudio = st.fastForwardMuteAudio ?? s.ffMuteAudio
            s.ffBadge = st.fastForwardBadge ?? s.ffBadge
        }

        if let im = file.image {
            s.imageEnabled = im.enabled ?? s.imageEnabled
            s.imageFormat = choice(im.format, "image.format", s.imageFormat, ImageFormat.init(rawValue:),
                                   hint: " (avif, heic, jpeg, png)")
            s.imageQuality = ranged(im.quality, "image.quality", 0...1, s.imageQuality)
            s.imageMaxLongEdge = ranged(im.maxLongEdge, "image.maxLongEdge", 0...65536, s.imageMaxLongEdge)
        }
        return (s, warnings)
    }

    static let presets: Set<String> = ["ultrafast", "superfast", "veryfast", "faster", "fast",
                                       "medium", "slow", "slower", "veryslow"]

    // MARK: 파일 형식

    /// config.json 구조. 모든 필드는 생략 가능.
    struct File: Decodable {
        struct Folders: Decodable { var drop, output, processed, failed: String? }
        struct Video: Decodable {
            var codec: String?, crf: Int?, preset: String?, maxLongEdge: Int?, audioBitrate: String?, outputSuffix: String?
        }
        struct Still: Decodable {
            var mode: String?, sensitivity: String?
            var noiseDb: Double?, minStillDuration: Double?, mergeGapMax: Double?
            var minKeep: Double?, pad: Double?, minKeepRatio: Double?, smoothTransitions: Bool?
            var adaptiveThreshold: Bool?
            var fastForwardSpeed: Int?, fastForwardMinDuration: Double?, fastForwardMuteAudio: Bool?, fastForwardBadge: Bool?
        }
        struct Image: Decodable { var enabled: Bool?, format: String?, quality: Double?, maxLongEdge: Int? }

        var folders: Folders?
        var notifications: Bool?
        var openOutputAfterAdd: Bool?
        var processedRetentionDays: Int?
        var video: Video?
        var still: Still?
        var image: Image?
    }

    /// 허용 키. 오타(예: "notification")를 조용히 무시하지 않고 경고하기 위해 File 과 같게 유지한다(테스트가 검사).
    static let schema: [String: Set<String>] = [
        "": ["folders", "notifications", "openOutputAfterAdd", "processedRetentionDays", "video", "still", "image"],
        "folders": ["drop", "output", "processed", "failed"],
        "video": ["codec", "crf", "preset", "maxLongEdge", "audioBitrate", "outputSuffix"],
        "still": ["mode", "sensitivity", "noiseDb", "minStillDuration", "mergeGapMax", "minKeep", "pad",
                  "minKeepRatio", "smoothTransitions", "adaptiveThreshold",
                  "fastForwardSpeed", "fastForwardMinDuration", "fastForwardMuteAudio", "fastForwardBadge"],
        "image": ["enabled", "format", "quality", "maxLongEdge"],
    ]

    static func unknownKeys(in data: Data) -> [String] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [] }
        var unknown: [String] = []
        for (key, value) in root.sorted(by: { $0.key < $1.key }) {
            guard schema[""]!.contains(key) else { unknown.append(key); continue }
            guard let allowed = schema[key], let nested = value as? [String: Any] else { continue }
            unknown += nested.keys.sorted().filter { !allowed.contains($0) }.map { "\(key).\($0)" }
        }
        return unknown
    }

    private static func keyPath(_ path: [CodingKey]) -> String {
        path.map(\.stringValue).joined(separator: ".")
    }

    /// 처음 만드는 설정 파일. 감지 세부값(noiseDb 등)은 민감도 프리셋이 정하도록 일부러 적지 않는다.
    static func defaultTemplate(baseFolder: URL = defaultBaseFolder, home: String = Paths.home.path) -> String {
        let base = jsonEscaped(Paths.abbreviate(baseFolder.path, home: home))
        return """
        {
          "folders": {
            "drop": "\(base)/drop",
            "output": "\(base)/output",
            "processed": "\(base)/processed",
            "failed": "\(base)/failed"
          },
          "notifications": true,
          "openOutputAfterAdd": true,
          "processedRetentionDays": 30,
          "video": {
            "codec": "libx264",
            "crf": 26,
            "preset": "slow",
            "maxLongEdge": 1920,
            "audioBitrate": "128k",
            "outputSuffix": "_resize"
          },
          "still": {
            "mode": "fastForward",
            "sensitivity": "conservative",
            "adaptiveThreshold": false,
            "fastForwardSpeed": 4,
            "fastForwardMinDuration": 2.0,
            "fastForwardMuteAudio": true,
            "fastForwardBadge": true,
            "minKeep": 0.3,
            "pad": 0.15,
            "minKeepRatio": 0.02,
            "smoothTransitions": false
          },
          "image": {
            "enabled": true,
            "format": "avif",
            "quality": 0.8,
            "maxLongEdge": 0
          }
        }

        """
    }

    private static func jsonEscaped(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
