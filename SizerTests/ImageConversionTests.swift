import XCTest
import ImageIO
@testable import Sizer

/// 실제 ImageIO로 이미지 변환 검증(고화질 저용량).
final class ImageConversionTests: XCTestCase {

    private func makeConfig(drop: URL, out: URL, processed: URL, failed: URL,
                            format: ImageFormat, quality: Double, maxEdge: Int) -> ConversionConfig {
        ConversionConfig(
            dropFolder: drop, outputFolder: out, processedFolder: processed, failedFolder: failed,
            codec: .h264, crf: 26, preset: "veryfast", maxLongEdge: 1920,
            audioBitrate: "128k", outputSuffix: "_resize",
            trimStill: false, trimOptions: TrimOptions(),
            imageEnabled: true, imageFormat: format, imageQuality: quality, imageMaxLongEdge: maxEdge,
            notificationsEnabled: false
        )
    }

    func testPngConvertsToAvifAndShrinks() throws {
        guard let ffmpeg = FFmpeg.ffmpegURL else { throw XCTSkip("ffmpeg 없음(PNG 픽스처 생성용)") }
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("sizer-img-\(UUID().uuidString)")
        let drop = root.appendingPathComponent("drop")
        let out = root.appendingPathComponent("out")
        let processed = root.appendingPathComponent("processed")
        let failed = root.appendingPathComponent("failed")
        for d in [drop, out, processed, failed] { try fm.createDirectory(at: d, withIntermediateDirectories: true) }
        defer { try? fm.removeItem(at: root) }

        // 1920x1080 PNG 픽스처 생성
        let input = drop.appendingPathComponent("shot.png")
        let gen = FFmpeg.run(ffmpeg, [
            "-y", "-f", "lavfi", "-i", "testsrc2=size=1920x1080:rate=1:duration=1",
            "-frames:v", "1", input.path,
        ])
        XCTAssertTrue(gen.succeeded && fm.fileExists(atPath: input.path), "PNG 생성 실패")
        let origSize = try fm.attributesOfItem(atPath: input.path)[.size] as? Int ?? 0

        let config = makeConfig(drop: drop, out: out, processed: processed, failed: failed,
                                format: .avif, quality: 0.7, maxEdge: 0)
        let outcome = ConversionEngine.process(input, config: config)

        XCTAssertTrue(outcome.success, "변환 실패: \(outcome.detail)")
        guard case .image = outcome.kind else { return XCTFail("kind가 image가 아님") }

        let outputs = try fm.contentsOfDirectory(at: out, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "avif" }
        XCTAssertEqual(outputs.count, 1, "avif 출력이 정확히 1개가 아님")

        let newSize = try fm.attributesOfItem(atPath: outputs[0].path)[.size] as? Int ?? 0
        XCTAssertGreaterThan(newSize, 0)
        XCTAssertLessThan(newSize, origSize, "AVIF가 원본 PNG보다 작지 않음 (\(newSize) vs \(origSize))")

        // outputURL 유효 + 원본 processed 이동
        XCTAssertNotNil(outcome.outputURL)
        XCTAssertTrue(fm.fileExists(atPath: processed.appendingPathComponent("shot.png").path))
    }

    func testDownscaleReducesDimensions() throws {
        guard let ffmpeg = FFmpeg.ffmpegURL else { throw XCTSkip("ffmpeg 없음") }
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("sizer-img-\(UUID().uuidString)")
        let drop = root.appendingPathComponent("drop")
        let out = root.appendingPathComponent("out")
        let processed = root.appendingPathComponent("processed")
        let failed = root.appendingPathComponent("failed")
        for d in [drop, out, processed, failed] { try fm.createDirectory(at: d, withIntermediateDirectories: true) }
        defer { try? fm.removeItem(at: root) }

        let input = drop.appendingPathComponent("big.png")
        _ = FFmpeg.run(ffmpeg, [
            "-y", "-f", "lavfi", "-i", "testsrc2=size=3000x2000:rate=1:duration=1",
            "-frames:v", "1", input.path,
        ])

        // JPEG + 장변 1280 제한
        let config = makeConfig(drop: drop, out: out, processed: processed, failed: failed,
                                format: .jpeg, quality: 0.8, maxEdge: 1280)
        let outcome = ConversionEngine.process(input, config: config)
        XCTAssertTrue(outcome.success)

        let output = try fm.contentsOfDirectory(at: out, includingPropertiesForKeys: nil)
            .first { $0.pathExtension == "jpg" }
        let unwrapped = try XCTUnwrap(output)

        // 출력 장변이 1280 이하인지 확인
        guard let srcImg = CGImageSourceCreateWithURL(unwrapped as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(srcImg, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int else {
            return XCTFail("출력 이미지 크기 조회 실패")
        }
        XCTAssertLessThanOrEqual(max(w, h), 1280, "다운스케일이 적용되지 않음 (\(w)x\(h))")
    }
}
