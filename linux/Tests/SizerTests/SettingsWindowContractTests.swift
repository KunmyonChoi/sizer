import XCTest
@testable import Sizer

/// 설정 창(linux/packaging/settings/sizer-settings)이 쓰는 키·범위·선택지·기본값을 Swift 설정 파서가
/// 경고 없이 받아들이는지 검사한다. 창에서 고를 수 있는 값이 데몬에서 "기본값 사용" 경고가 되면 안 된다.
final class SettingsWindowContractTests: XCTestCase {

    private let base = URL(fileURLWithPath: "/home/u/Videos/Sizer", isDirectory: true)

    private func spec() throws -> (controls: [String: [String: Any]], presets: [String: [String: Double]]) {
        let python = try XCTUnwrap(Executables.find("python3"), "python3 없음")
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("packaging/settings/sizer-settings")
        let r = FFmpeg.run(python, ["-B", script.path, "--dump-spec"], timeout: 30)
        XCTAssertTrue(r.succeeded, r.stderr)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(r.stdout.utf8)) as? [String: Any])
        let controls = try XCTUnwrap(root["controls"] as? [String: [String: Any]])
        let presets = try XCTUnwrap(root["presets"] as? [String: [String: Double]])
        return (controls, presets)
    }

    private func split(_ key: String) -> (section: String, name: String) {
        let parts = key.split(separator: ".").map(String.init)
        return parts.count == 2 ? (parts[0], parts[1]) : ("", key)
    }

    private func document(_ values: [String: Any]) throws -> Data {
        var object: [String: Any] = [:]
        for (key, value) in values {
            let (section, name) = split(key)
            if section.isEmpty {
                object[name] = value
            } else {
                var nested = object[section] as? [String: Any] ?? [:]
                nested[name] = value
                object[section] = nested
            }
        }
        return try JSONSerialization.data(withJSONObject: object)
    }

    private func parse(_ values: [String: Any]) throws -> (settings: LinuxSettings, warnings: [String]) {
        try LinuxSettings.parse(document(values), baseFolder: base, home: "/home/u")
    }

    func testEveryControlKeyIsInSwiftSchema() throws {
        for key in try spec().controls.keys {
            let (section, name) = split(key)
            XCTAssertTrue(LinuxSettings.schema[section]?.contains(name) == true, "Swift 스키마에 없는 키: \(key)")
        }
    }

    func testEveryValueTheWindowCanWriteIsAccepted() throws {
        for (key, control) in try spec().controls {
            var values: [Any] = []
            switch control["type"] as? String {
            case "number": values = [control["min"]!, control["max"]!, control["default"]!]
            case "choice": values = (control["choices"] as? [[Any]] ?? []).map { $0[0] }
            case "switch": values = [true, false]
            case "text": values = [control["default"]!]
            default: continue   // 폴더는 경로라 범위가 없다
            }
            for value in values {
                let (_, warnings) = try parse([key: value])
                XCTAssertEqual(warnings, [], "\(key) = \(value)")
            }
        }
    }

    func testWindowDefaultsMatchSwiftDefaults() throws {
        let controls = try spec().controls
        var values: [String: Any] = [:]
        for (key, control) in controls where control["type"] as? String != "folder" {
            values[key] = control["default"]
        }
        let (explicit, warnings) = try parse(values)
        XCTAssertEqual(warnings, [])
        let implicit = LinuxSettings(baseFolder: base)
        XCTAssertEqual(explicit.notifications, implicit.notifications)
        XCTAssertEqual(explicit.openOutputAfterAdd, implicit.openOutputAfterAdd)
        XCTAssertEqual(explicit.processedRetentionDays, implicit.processedRetentionDays)
        XCTAssertEqual(explicit.codec, implicit.codec)
        XCTAssertEqual(explicit.crf, implicit.crf)
        XCTAssertEqual(explicit.preset, implicit.preset)
        XCTAssertEqual(explicit.maxLongEdge, implicit.maxLongEdge)
        XCTAssertEqual(explicit.audioBitrate, implicit.audioBitrate)
        XCTAssertEqual(explicit.outputSuffix, implicit.outputSuffix)
        XCTAssertEqual(explicit.stillMode, implicit.stillMode)
        XCTAssertEqual(explicit.sensitivity, implicit.sensitivity)
        XCTAssertEqual(explicit.trimOptions, implicit.trimOptions)
        XCTAssertEqual(explicit.adaptiveThreshold, implicit.adaptiveThreshold)
        XCTAssertEqual(explicit.ffSpeed, implicit.ffSpeed)
        XCTAssertEqual(explicit.ffMinDuration, implicit.ffMinDuration)
        XCTAssertEqual(explicit.ffMuteAudio, implicit.ffMuteAudio)
        XCTAssertEqual(explicit.ffBadge, implicit.ffBadge)
        XCTAssertEqual(explicit.imageEnabled, implicit.imageEnabled)
        XCTAssertEqual(explicit.imageFormat, implicit.imageFormat)
        XCTAssertEqual(explicit.imageQuality, implicit.imageQuality)
        XCTAssertEqual(explicit.imageMaxLongEdge, implicit.imageMaxLongEdge)
    }

    func testPresetsMatchSwiftSensitivityPresets() throws {
        let presets = try spec().presets
        for preset in SensitivityPreset.allCases {
            let window = try XCTUnwrap(presets[preset.rawValue], preset.rawValue)
            XCTAssertEqual(window["noiseDb"], preset.detection.noiseDb, preset.rawValue)
            XCTAssertEqual(window["minStillDuration"], preset.detection.minStill, preset.rawValue)
            XCTAssertEqual(window["mergeGapMax"], preset.detection.mergeGapMax, preset.rawValue)
        }
    }
}
