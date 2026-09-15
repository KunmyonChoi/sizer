import XCTest
@testable import Sizer

/// `sizer` 명령 end-to-end. XDG 경로를 임시 폴더로 돌려 사용자 설정·로그를 건드리지 않는다.
final class CLITests: XCTestCase {

    private var root: URL!
    private let xdgKeys = ["XDG_CONFIG_HOME", "XDG_STATE_HOME", "XDG_CACHE_HOME", "XDG_RUNTIME_DIR"]

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("sizer-cli-\(UUID().uuidString)")
        for key in xdgKeys {
            let dir = root.appendingPathComponent(key.lowercased())
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            setenv(key, dir.path, 1)
        }
        let config = root.appendingPathComponent("xdg_config_home/sizer/config.json")
        try FileManager.default.createDirectory(at: config.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        {
          "folders": {
            "drop": "\(root.path)/drop", "output": "\(root.path)/output",
            "processed": "\(root.path)/processed", "failed": "\(root.path)/failed"
          },
          "notifications": false,
          "video": {"preset": "veryfast"},
          "still": {"mode": "off"}
        }
        """.write(to: config, atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        xdgKeys.forEach { unsetenv($0) }
        try? FileManager.default.removeItem(at: root)
    }

    func testVersionHelpAndUnknownCommand() {
        XCTAssertEqual(SizerCLI.main(["sizer", "--version"]), 0)
        XCTAssertEqual(SizerCLI.main(["sizer", "help"]), 0)
        XCTAssertEqual(SizerCLI.main(["sizer", "nope"]), 2)
        XCTAssertEqual(SizerCLI.main(["sizer", "convert"]), 2, "파일 없이 convert 는 사용법 오류")
        XCTAssertEqual(SizerCLI.main(["sizer", "convert", "-o"]), 2)
    }

    func testConvertKeepsOriginalAndCleansUp() throws {
        let ffmpeg = try XCTUnwrap(FFmpeg.ffmpegURL, "ffmpeg 없음")
        let source = root.appendingPathComponent("my clip.mp4")
        XCTAssertTrue(FFmpeg.run(ffmpeg, ["-y", "-f", "lavfi", "-i", "testsrc2=size=320x240:rate=15:duration=2",
                                          "-pix_fmt", "yuv420p", source.path]).succeeded)
        let out = root.appendingPathComponent("custom-out")

        XCTAssertEqual(SizerCLI.main(["sizer", "convert", "-o", out.path, source.path]), 0)

        let fm = FileManager.default
        XCTAssertTrue(fm.fileExists(atPath: source.path), "convert 는 원본을 옮기지 않는다")
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: out.path), ["my clip_resize.mp4"])
        let staging = root.appendingPathComponent("xdg_cache_home/sizer/staging")
        XCTAssertEqual((try? fm.contentsOfDirectory(atPath: staging.path)) ?? [], [], "작업 폴더를 남기지 않는다")
        XCTAssertEqual((try? fm.contentsOfDirectory(atPath: root.appendingPathComponent("processed").path)) ?? [], [],
                       "설정의 processed 폴더에 사본을 쌓지 않는다")
    }

    func testPauseResumeRescanWithoutDaemonFail() {
        XCTAssertEqual(SizerCLI.main(["sizer", "pause"]), 1)
        XCTAssertEqual(SizerCLI.main(["sizer", "resume"]), 1)
        XCTAssertEqual(SizerCLI.main(["sizer", "rescan"]), 1)
    }

    func testConvertRejectsUnsupportedFiles() throws {
        let text = root.appendingPathComponent("notes.txt")
        try Data("x".utf8).write(to: text)
        XCTAssertEqual(SizerCLI.main(["sizer", "convert", text.path]), 1)
    }

    func testConfigPathUsesXDGConfigHome() {
        XCTAssertEqual(Paths.configFile.path, root.appendingPathComponent("xdg_config_home/sizer/config.json").path)
        XCTAssertEqual(SizerCLI.main(["sizer", "config"]), 0)
        XCTAssertEqual(SizerCLI.main(["sizer", "status"]), 0)
    }
}
