import XCTest
@testable import Sizer

/// 실제 ffmpeg로 합성 영상을 만들어 엔진 전체를 end-to-end로 검증.
final class ConversionEngineIntegrationTests: XCTestCase {

    func testConvertTrimsFrozenMiddleSection() throws {
        guard let ffmpeg = FFmpeg.ffmpegURL else { throw XCTSkip("ffmpeg 없음") }
        let fm = FileManager.default

        // 임시 작업 폴더
        let root = fm.temporaryDirectory.appendingPathComponent("sizer-it-\(UUID().uuidString)")
        let drop = root.appendingPathComponent("drop")
        let out = root.appendingPathComponent("out")
        let processed = root.appendingPathComponent("processed")
        let failed = root.appendingPathComponent("failed")
        for d in [drop, out, processed, failed] {
            try fm.createDirectory(at: d, withIntermediateDirectories: true)
        }
        defer { try? fm.removeItem(at: root) }

        // 10초 영상: 0~3s 움직임, 3~8s 정지(파란 화면), 8~10s 움직임
        let input = drop.appendingPathComponent("clip.mp4")
        let genArgs = [
            "-y",
            "-f", "lavfi", "-i", "testsrc2=size=320x240:rate=15:duration=3",
            "-f", "lavfi", "-i", "color=c=blue:size=320x240:rate=15:duration=5",
            "-f", "lavfi", "-i", "testsrc2=size=320x240:rate=15:duration=2",
            "-filter_complex", "[0:v][1:v][2:v]concat=n=3:v=1:a=0[v]",
            "-map", "[v]", "-pix_fmt", "yuv420p", input.path,
        ]
        let gen = FFmpeg.run(ffmpeg, genArgs)
        XCTAssertTrue(gen.succeeded && fm.fileExists(atPath: input.path), "합성 영상 생성 실패: \(gen.stderr.suffix(300))")

        let sourceDuration = Probe.duration(input)
        XCTAssertEqual(sourceDuration, 10, accuracy: 0.6, "원본 길이 ~10s 예상, 실제 \(sourceDuration)")

        // 변환 실행(알림 비활성)
        var opts = TrimOptions()
        opts.pad = 0.15
        let config = ConversionConfig(
            dropFolder: drop, outputFolder: out, processedFolder: processed, failedFolder: failed,
            codec: .h264, crf: 28, preset: "veryfast", maxLongEdge: 1920,
            audioBitrate: "128k", outputSuffix: "_sns",
            trimStill: true, trimOptions: opts,
            imageEnabled: false, imageFormat: .avif, imageQuality: 0.8, imageMaxLongEdge: 0,
            notificationsEnabled: false
        )

        let outcome = ConversionEngine.convert(input, config: config)
        XCTAssertTrue(outcome.success, "변환 실패: \(outcome.detail)")

        // 클릭 재생용 outputURL이 실제 존재하는 파일을 가리켜야 함
        XCTAssertNotNil(outcome.outputURL)
        XCTAssertTrue(fm.fileExists(atPath: outcome.outputURL?.path ?? ""), "outputURL이 실제 파일을 가리키지 않음")

        // 출력 1개 생성
        let outputs = try fm.contentsOfDirectory(at: out, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "mp4" }
        XCTAssertEqual(outputs.count, 1)
        let output = outputs[0]

        // 정지 5s가 잘려 길이가 ~5s(+패딩)로 줄어야 함
        let outDuration = Probe.duration(output)
        XCTAssertLessThan(outDuration, 8, "정지 구간이 제거되지 않음(길이 \(outDuration))")
        XCTAssertGreaterThan(outDuration, 4, "너무 많이 잘림(길이 \(outDuration))")

        // 원본은 processed로 이동, drop은 비어야 함
        XCTAssertTrue(fm.fileExists(atPath: processed.appendingPathComponent("clip.mp4").path))
        let dropRemain = try fm.contentsOfDirectory(at: drop, includingPropertiesForKeys: nil)
        XCTAssertTrue(dropRemain.isEmpty, "원본이 drop에 남아있음")

        // faststart(moov atom) 확인: 출력이 재생 가능한 유효 mp4인지 duration으로 대체 검증됨
    }

    func testConvertWithoutTrimKeepsFullDuration() throws {
        guard let ffmpeg = FFmpeg.ffmpegURL else { throw XCTSkip("ffmpeg 없음") }
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("sizer-it-\(UUID().uuidString)")
        let drop = root.appendingPathComponent("drop")
        let out = root.appendingPathComponent("out")
        let processed = root.appendingPathComponent("processed")
        let failed = root.appendingPathComponent("failed")
        for d in [drop, out, processed, failed] {
            try fm.createDirectory(at: d, withIntermediateDirectories: true)
        }
        defer { try? fm.removeItem(at: root) }

        // 5초 내내 움직이는 영상(정지 없음)
        let input = drop.appendingPathComponent("motion.mp4")
        let gen = FFmpeg.run(ffmpeg, [
            "-y", "-f", "lavfi", "-i", "testsrc2=size=320x240:rate=15:duration=5",
            "-pix_fmt", "yuv420p", input.path,
        ])
        XCTAssertTrue(gen.succeeded)

        let config = ConversionConfig(
            dropFolder: drop, outputFolder: out, processedFolder: processed, failedFolder: failed,
            codec: .h264, crf: 28, preset: "veryfast", maxLongEdge: 1280,
            audioBitrate: "128k", outputSuffix: "_sns",
            trimStill: true, trimOptions: TrimOptions(),
            imageEnabled: false, imageFormat: .avif, imageQuality: 0.8, imageMaxLongEdge: 0,
            notificationsEnabled: false
        )
        let outcome = ConversionEngine.convert(input, config: config)
        XCTAssertTrue(outcome.success)

        let outputs = try fm.contentsOfDirectory(at: out, includingPropertiesForKeys: nil).filter { $0.pathExtension == "mp4" }
        XCTAssertEqual(outputs.count, 1)
        let outDuration = Probe.duration(outputs[0])
        XCTAssertEqual(outDuration, 5, accuracy: 0.6, "정지 없는 영상은 길이 유지되어야 함(실제 \(outDuration))")
    }
}
