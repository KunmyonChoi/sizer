import XCTest
@testable import Sizer

final class FastForwardTests: XCTestCase {

    // MARK: 순수 로직

    func testPlanFastForwardSpeedsLongStillZone() {
        // 10s 중 3~8s(5s) 정지 → [0-3 1×][3-8 4×][8-10 1×]
        let segs = SegmentPlanner.planFastForward(
            freezes: [Segment(3, 8)], duration: 10, options: TrimOptions(), speed: 4, minFF: 2
        )
        let s = try! XCTUnwrap(segs)
        XCTAssertEqual(s.count, 3)
        XCTAssertEqual(s[0].speed, 1); XCTAssertEqual(s[1].speed, 4); XCTAssertEqual(s[2].speed, 1)
        // 출력 길이 = 3 + 5/4 + 2 = 6.25
        XCTAssertEqual(s.totalOutputDuration, 6.25, accuracy: 0.001)
    }

    func testPlanFastForwardNilWhenNoQualifyingZone() {
        // 정지 구간이 minFF보다 짧으면 nil
        XCTAssertNil(SegmentPlanner.planFastForward(
            freezes: [Segment(3, 4)], duration: 10, options: TrimOptions(), speed: 4, minFF: 2))
        // 정지 없음
        XCTAssertNil(SegmentPlanner.planFastForward(
            freezes: [], duration: 10, options: TrimOptions(), speed: 4, minFF: 2))
    }

    func testAtempoChainDecomposes() {
        func count(_ speed: Double) -> Int {
            FilterGraphBuilder.atempoChain(speed).components(separatedBy: "atempo=").count - 1
        }
        XCTAssertEqual(count(2), 1)
        XCTAssertEqual(count(4), 2)
        XCTAssertEqual(count(8), 3)
    }

    func testMergeSameSpeed() {
        let merged = SegmentPlanner.mergeSameSpeed([
            SpeedSegment(0, 2, speed: 1), SpeedSegment(2, 5, speed: 1), SpeedSegment(5, 8, speed: 4),
        ])
        XCTAssertEqual(merged, [SpeedSegment(0, 5, speed: 1), SpeedSegment(5, 8, speed: 4)])
    }

    // MARK: 실제 ffmpeg 통합

    func testFastForwardConvertShortensViaSpeedup() throws {
        guard let ffmpeg = FFmpeg.ffmpegURL else { throw XCTSkip("ffmpeg 없음") }
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("sizer-ff-\(UUID().uuidString)")
        let drop = root.appendingPathComponent("drop"), out = root.appendingPathComponent("out")
        let processed = root.appendingPathComponent("processed"), failed = root.appendingPathComponent("failed")
        for d in [drop, out, processed, failed] { try fm.createDirectory(at: d, withIntermediateDirectories: true) }
        defer { try? fm.removeItem(at: root) }

        // 10초: 3s 움직임 + 5s 정지(파랑) + 2s 움직임
        let input = drop.appendingPathComponent("clip.mp4")
        let gen = FFmpeg.run(ffmpeg, [
            "-y",
            "-f", "lavfi", "-i", "testsrc2=size=320x240:rate=15:duration=3",
            "-f", "lavfi", "-i", "color=c=blue:size=320x240:rate=15:duration=5",
            "-f", "lavfi", "-i", "testsrc2=size=320x240:rate=15:duration=2",
            "-filter_complex", "[0:v][1:v][2:v]concat=n=3:v=1:a=0[v]",
            "-map", "[v]", "-pix_fmt", "yuv420p", input.path,
        ])
        XCTAssertTrue(gen.succeeded)

        let config = ConversionConfig(
            dropFolder: drop, outputFolder: out, processedFolder: processed, failedFolder: failed,
            codec: .h264, crf: 28, preset: "veryfast", maxLongEdge: 1280,
            audioBitrate: "128k", outputSuffix: "_resize",
            stillMode: .fastForward, trimOptions: TrimOptions(),
            ffSpeed: 4, ffMinDuration: 2, ffMuteAudio: true, ffBadge: true,
            imageEnabled: false, imageFormat: .avif, imageQuality: 0.8, imageMaxLongEdge: 0,
            notificationsEnabled: false
        )
        let outcome = ConversionEngine.convert(input, config: config)
        XCTAssertTrue(outcome.success, "FF 변환 실패: \(outcome.detail)")

        let output = try XCTUnwrap(try fm.contentsOfDirectory(at: out, includingPropertiesForKeys: nil)
            .first { $0.pathExtension == "mp4" })
        // 정지 5s가 4× → 1.25s. 출력 ≈ 3 + 1.25 + 2 = 6.25s (잘라내기 ~5s와 구분됨)
        let dur = Probe.duration(output)
        XCTAssertEqual(dur, 6.25, accuracy: 0.8, "FF 출력 길이 예상 ~6.25s, 실제 \(dur)")
        XCTAssertTrue(fm.fileExists(atPath: processed.appendingPathComponent("clip.mp4").path))
    }
}
