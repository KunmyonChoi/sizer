import XCTest
@testable import Sizer

final class LinuxSettingsTests: XCTestCase {

    private let home = "/home/u"
    private let base = URL(fileURLWithPath: "/home/u/Videos/Sizer", isDirectory: true)

    private func parse(_ json: String) throws -> (settings: LinuxSettings, warnings: [String]) {
        try LinuxSettings.parse(Data(json.utf8), baseFolder: base, home: home)
    }

    // MARK: 기본값

    func testEmptyObjectUsesMacDefaults() throws {
        let (s, warnings) = try parse("{}")
        XCTAssertEqual(warnings, [])
        XCTAssertEqual(s.dropFolder.path, "/home/u/Videos/Sizer/drop")
        XCTAssertEqual(s.outputFolder.path, "/home/u/Videos/Sizer/output")
        XCTAssertEqual(s.processedFolder.path, "/home/u/Videos/Sizer/processed")
        XCTAssertEqual(s.failedFolder.path, "/home/u/Videos/Sizer/failed")
        XCTAssertTrue(s.notifications)
        XCTAssertEqual(s.processedRetentionDays, 30)
        XCTAssertEqual(s.codec, .h264)
        XCTAssertEqual(s.crf, 26)
        XCTAssertEqual(s.preset, "slow")
        XCTAssertEqual(s.maxLongEdge, 1920)
        XCTAssertEqual(s.outputSuffix, "_resize")
        XCTAssertEqual(s.stillMode, .fastForward)
        XCTAssertEqual(s.sensitivity, .conservative)
        XCTAssertEqual(s.trimOptions, TrimOptions(noiseDb: -58, minStillDuration: 3, mergeGapMax: 0.7, minKeep: 0.3,
                                                  pad: 0.15, minKeepRatio: 0.02, smoothTransitions: false))
        XCTAssertEqual(s.ffSpeed, 4)
        XCTAssertEqual(s.imageFormat, .avif)
        XCTAssertEqual(s.imageQuality, 0.8)
        XCTAssertEqual(s.imageMaxLongEdge, 0)
    }

    func testEngineConfigLeavesNotificationsToDaemon() throws {
        let (s, _) = try parse(#"{"notifications": true}"#)
        XCTAssertFalse(s.config.notificationsEnabled, "알림은 엔진이 아니라 데몬/CLI 가 버튼을 달아 보낸다")
    }

    func testDefaultTemplateParsesCleanlyToDefaults() throws {
        let template = LinuxSettings.defaultTemplate(baseFolder: base, home: home)
        XCTAssertTrue(template.contains(#""drop": "~/Videos/Sizer/drop""#), "홈 아래 경로는 ~ 로 적는다")
        let (s, warnings) = try parse(template)
        XCTAssertEqual(warnings, [])
        let d = LinuxSettings(baseFolder: base)
        XCTAssertEqual(s.dropFolder, d.dropFolder)
        XCTAssertEqual(s.trimOptions, d.trimOptions)
        XCTAssertEqual(s.stillMode, d.stillMode)
        XCTAssertEqual(s.imageFormat, d.imageFormat)
    }

    /// 템플릿·스키마·File 이 서로 어긋나지 않게 한다.
    func testTemplateKeysMatchSchema() throws {
        let data = Data(LinuxSettings.defaultTemplate(baseFolder: base, home: home).utf8)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(root.keys), LinuxSettings.schema[""])
        // 감지 세부값은 프리셋이 정하도록 템플릿에 일부러 적지 않는다.
        let presetControlled: Set<String> = ["noiseDb", "minStillDuration", "mergeGapMax"]
        for (section, allowed) in LinuxSettings.schema where !section.isEmpty {
            let keys = Set(try XCTUnwrap(root[section] as? [String: Any], section).keys)
            XCTAssertEqual(keys, allowed.subtracting(section == "still" ? presetControlled : []), section)
        }
    }

    // MARK: 값 적용

    func testSensitivityPresetSetsDetectionValues() throws {
        let (s, _) = try parse(#"{"still": {"sensitivity": "aggressive"}}"#)
        XCTAssertEqual(s.trimOptions.noiseDb, -45)
        XCTAssertEqual(s.trimOptions.minStillDuration, 1)
        XCTAssertEqual(s.trimOptions.mergeGapMax, 0.35)
    }

    func testExplicitDetectionValueOverridesPreset() throws {
        let (s, _) = try parse(#"{"still": {"sensitivity": "aggressive", "noiseDb": -52}}"#)
        XCTAssertEqual(s.trimOptions.noiseDb, -52)
        XCTAssertEqual(s.trimOptions.minStillDuration, 1, "나머지는 프리셋값 유지")
    }

    func testEveryKeyApplies() throws {
        let (s, warnings) = try parse("""
        {
          "folders": {"drop": "~/in", "output": "/data/out", "processed": "$HOME/done", "failed": "/data/failed"},
          "notifications": false, "openOutputAfterAdd": false, "processedRetentionDays": 0,
          "video": {"codec": "libx265", "crf": 30, "preset": "veryfast", "maxLongEdge": 1280,
                    "audioBitrate": "96k", "outputSuffix": "_sns"},
          "still": {"mode": "trim", "sensitivity": "balanced", "noiseDb": -40, "minStillDuration": 5,
                    "mergeGapMax": 1, "minKeep": 0.5, "pad": 0.2, "minKeepRatio": 0.1, "smoothTransitions": true,
                    "adaptiveThreshold": true, "fastForwardSpeed": 8, "fastForwardMinDuration": 4,
                    "fastForwardMuteAudio": false, "fastForwardBadge": false},
          "image": {"enabled": false, "format": "jpeg", "quality": 0.5, "maxLongEdge": 2000},
          "panel": {"enabled": false, "side": "left", "addResults": false}
        }
        """)
        XCTAssertEqual(warnings, [])
        XCTAssertEqual(s.dropFolder.path, "/home/u/in")
        XCTAssertEqual(s.outputFolder.path, "/data/out")
        XCTAssertEqual(s.processedFolder.path, "/home/u/done")
        XCTAssertEqual(s.failedFolder.path, "/data/failed")
        XCTAssertFalse(s.notifications)
        XCTAssertFalse(s.openOutputAfterAdd)
        XCTAssertEqual(s.processedRetentionDays, 0)
        XCTAssertEqual(s.codec, .h265)
        XCTAssertEqual(s.crf, 30)
        XCTAssertEqual(s.preset, "veryfast")
        XCTAssertEqual(s.maxLongEdge, 1280)
        XCTAssertEqual(s.audioBitrate, "96k")
        XCTAssertEqual(s.outputSuffix, "_sns")
        XCTAssertEqual(s.stillMode, .trim)
        XCTAssertEqual(s.sensitivity, .balanced)
        XCTAssertEqual(s.trimOptions, TrimOptions(noiseDb: -40, minStillDuration: 5, mergeGapMax: 1, minKeep: 0.5,
                                                  pad: 0.2, minKeepRatio: 0.1, smoothTransitions: true))
        XCTAssertTrue(s.adaptiveThreshold)
        XCTAssertEqual(s.ffSpeed, 8)
        XCTAssertEqual(s.ffMinDuration, 4)
        XCTAssertFalse(s.ffMuteAudio)
        XCTAssertFalse(s.ffBadge)
        XCTAssertFalse(s.imageEnabled)
        XCTAssertEqual(s.imageFormat, .jpeg)
        XCTAssertEqual(s.imageQuality, 0.5)
        XCTAssertEqual(s.imageMaxLongEdge, 2000)
        XCTAssertFalse(s.panelEnabled)
        XCTAssertEqual(s.panelSide, "left")
        XCTAssertFalse(s.panelAddResults)
    }

    // MARK: 잘못된 값

    func testInvalidValuesFallBackToDefaultsWithWarnings() throws {
        let (s, warnings) = try parse("""
        {
          "folders": {"drop": "relative/path"},
          "video": {"codec": "h264_videotoolbox", "crf": 99},
          "still": {"mode": "fast", "fastForwardSpeed": 3},
          "image": {"format": "webp"},
          "panel": {"side": "top"}
        }
        """)
        XCTAssertEqual(s.dropFolder.path, "/home/u/Videos/Sizer/drop")
        XCTAssertEqual(s.codec, .h264, "VideoToolbox 는 macOS 전용")
        XCTAssertEqual(s.crf, 26)
        XCTAssertEqual(s.stillMode, .fastForward)
        XCTAssertEqual(s.ffSpeed, 4)
        XCTAssertEqual(s.imageFormat, .avif)
        XCTAssertEqual(s.panelSide, "right")
        XCTAssertEqual(warnings.count, 7, "\(warnings)")
        for key in ["folders.drop", "video.codec", "video.crf", "still.mode", "still.fastForwardSpeed", "image.format",
                    "panel.side"] {
            XCTAssertTrue(warnings.contains { $0.hasPrefix(key) }, "\(key) 경고 없음: \(warnings)")
        }
    }

    func testUnknownKeysWarn() throws {
        let (_, warnings) = try parse(#"{"notification": false, "video": {"crff": 20}}"#)
        XCTAssertTrue(warnings.contains { $0.contains("\"notification\"") }, "\(warnings)")
        XCTAssertTrue(warnings.contains { $0.contains("\"video.crff\"") }, "\(warnings)")
    }

    func testOutputFolderEqualToDropIsRejected() throws {
        let (s, warnings) = try parse(#"{"folders": {"drop": "/data/x", "output": "/data/x/"}}"#)
        XCTAssertEqual(s.outputFolder.path, "/home/u/Videos/Sizer/output")
        XCTAssertTrue(warnings.contains { $0.hasPrefix("folders.output") })
    }

    func testMalformedJSONThrows() {
        XCTAssertThrowsError(try parse("{"))
    }

    func testTypeMismatchNamesTheKey() {
        XCTAssertThrowsError(try parse(#"{"video": {"crf": "26"}}"#)) { error in
            XCTAssertTrue("\(error)".contains("video.crf"), "\(error)")
        }
    }

    // MARK: 파일

    func testLoadOrCreateWritesDefaultFileOnce() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sizer-cfg-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("config.json")

        _ = try LinuxSettings.loadOrCreate(at: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "설정 파일을 만들어 둬야 사용자가 찾아 고칠 수 있다")
        let (_, warnings) = try LinuxSettings.loadOrCreate(at: url)
        XCTAssertEqual(warnings, [])
    }
}
