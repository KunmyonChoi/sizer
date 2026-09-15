import XCTest
@testable import Sizer

/// 실제 ffmpeg(·libheif)로 Linux 이미지 변환과 배속 배지를 검증. macOS 의 ImageConversionTests 에 해당.
final class LinuxMediaTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("sizer-media-\(UUID().uuidString)")
        for name in ["drop", "out", "processed", "failed"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func ffmpeg() throws -> URL {
        try XCTUnwrap(FFmpeg.ffmpegURL, "ffmpeg 없음")
    }

    private func makeImage(_ name: String, size: String) throws -> URL {
        let url = root.appendingPathComponent("drop/\(name)")
        let r = FFmpeg.run(try ffmpeg(), ["-y", "-f", "lavfi", "-i", "testsrc2=size=\(size):rate=1:duration=1",
                                          "-frames:v", "1", url.path])
        XCTAssertTrue(r.succeeded, r.stderr)
        return url
    }

    private func config(format: ImageFormat, quality: Double = 0.8, maxEdge: Int = 0) -> ConversionConfig {
        ConversionConfig(
            dropFolder: root.appendingPathComponent("drop"), outputFolder: root.appendingPathComponent("out"),
            processedFolder: root.appendingPathComponent("processed"), failedFolder: root.appendingPathComponent("failed"),
            codec: .h264, crf: 26, preset: "veryfast", maxLongEdge: 1920,
            audioBitrate: "128k", outputSuffix: "_resize",
            stillMode: .off, trimOptions: TrimOptions(),
            imageEnabled: true, imageFormat: format, imageQuality: quality, imageMaxLongEdge: maxEdge,
            notificationsEnabled: false
        )
    }

    /// (코덱, 가로, 세로)
    private func probe(_ url: URL) throws -> (codec: String, width: Int, height: Int) {
        let ffprobe = try XCTUnwrap(FFmpeg.ffprobeURL)
        let r = FFmpeg.run(ffprobe, ["-v", "error", "-select_streams", "v:0",
                                     "-show_entries", "stream=codec_name,width,height", "-of", "csv=p=0", url.path])
        let parts = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ",")
        XCTAssertEqual(parts.count, 3, "ffprobe 출력: \(r.stdout) \(r.stderr)")
        return (String(parts[0]), Int(parts[1]) ?? 0, Int(parts[2]) ?? 0)
    }

    private func fileSize(_ url: URL) -> Int {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    }

    // MARK: 품질 매핑(순수)

    func testQualityMappings() {
        XCTAssertEqual(ImageConverter.avifCRF(1), 0)
        XCTAssertEqual(ImageConverter.avifCRF(0), 63)
        XCTAssertEqual(ImageConverter.avifCRF(0.8), 13)
        XCTAssertEqual(ImageConverter.avifCRF(1.5), 0, "범위 밖은 잘라낸다")
        XCTAssertEqual(ImageConverter.jpegQScale(1), 2)
        XCTAssertEqual(ImageConverter.jpegQScale(0), 31)
        XCTAssertEqual(ImageConverter.heifQuality(0.8), 80)
    }

    // MARK: 이미지 변환

    func testPngConvertsToSmallerAvif() throws {
        let ffmpeg = try ffmpeg()
        try XCTSkipIf(ImageConverter.detectAVIFEncoder(ffmpeg) == nil, "이 ffmpeg 에 AV1 인코더 없음")
        let input = try makeImage("shot.png", size: "1920x1080")
        let origSize = fileSize(input)

        let outcome = ConversionEngine.process(input, config: config(format: .avif, quality: 0.7))
        XCTAssertTrue(outcome.success, outcome.detail)
        let output = try XCTUnwrap(outcome.outputURL)
        XCTAssertEqual(output.lastPathComponent, "shot_resize.avif")
        XCTAssertLessThan(fileSize(output), origSize, "AVIF 가 원본 PNG 보다 작지 않음")
        let info = try probe(output)
        XCTAssertEqual(info.codec, "av1")
        XCTAssertEqual(info.width, 1920)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("processed/shot.png").path))
    }

    func testOddSizedImageConvertsToAvif() throws {
        let ffmpeg = try ffmpeg()
        try XCTSkipIf(ImageConverter.detectAVIFEncoder(ffmpeg) == nil, "이 ffmpeg 에 AV1 인코더 없음")
        let input = try makeImage("odd.png", size: "641x481")
        let outcome = ConversionEngine.process(input, config: config(format: .avif))
        XCTAssertTrue(outcome.success, outcome.detail)
    }

    func testJpegDownscaleKeepsAspectRatio() throws {
        let input = try makeImage("big.png", size: "3000x2000")
        let outcome = ConversionEngine.process(input, config: config(format: .jpeg, maxEdge: 1280))
        XCTAssertTrue(outcome.success, outcome.detail)
        let info = try probe(try XCTUnwrap(outcome.outputURL))
        XCTAssertEqual(info.codec, "mjpeg")
        XCTAssertEqual(info.width, 1280)
        XCTAssertEqual(info.height, 853)
    }

    func testDownscaleNeverUpscales() throws {
        let input = try makeImage("small.png", size: "800x600")
        let outcome = ConversionEngine.process(input, config: config(format: .png, maxEdge: 1280))
        XCTAssertTrue(outcome.success, outcome.detail)
        let info = try probe(try XCTUnwrap(outcome.outputURL))
        XCTAssertEqual([info.width, info.height], [800, 600])
    }

    func testAvifDownscaleProducesEvenDimensions() throws {
        let ffmpeg = try ffmpeg()
        try XCTSkipIf(ImageConverter.detectAVIFEncoder(ffmpeg) == nil, "이 ffmpeg 에 AV1 인코더 없음")
        let input = try makeImage("portrait.png", size: "1001x3000")
        let outcome = ConversionEngine.process(input, config: config(format: .avif, maxEdge: 1280))
        XCTAssertTrue(outcome.success, outcome.detail)
        let info = try probe(try XCTUnwrap(outcome.outputURL))
        XCTAssertEqual(info.height, 1280)
        XCTAssertEqual(info.width % 2, 0, "4:2:0 은 짝수 폭")
    }

    func testHeicOutputAndInputRoundTrip() throws {
        try XCTSkipUnless(ImageConverter.heicEncodingAvailable() && ImageConverter.heifDecoderURL != nil,
                          "libheif-examples + libheif-plugin-x265 없음")
        let input = try makeImage("shot.png", size: "640x480")
        let toHeic = ConversionEngine.process(input, config: config(format: .heic))
        XCTAssertTrue(toHeic.success, toHeic.detail)
        let heic = try XCTUnwrap(toHeic.outputURL)
        XCTAssertEqual(heic.pathExtension, "heic")

        // 이제 HEIC 를 입력으로(아이폰 사진처럼) JPEG 로.
        let dropped = root.appendingPathComponent("drop/photo.heic")
        try FileManager.default.moveItem(at: heic, to: dropped)
        let toJpeg = ConversionEngine.process(dropped, config: config(format: .jpeg))
        XCTAssertTrue(toJpeg.success, toJpeg.detail)
        let info = try probe(try XCTUnwrap(toJpeg.outputURL))
        XCTAssertEqual([info.width, info.height], [640, 480])
    }

    func testUnreadableImageFailsAndMovesToFailed() throws {
        let input = root.appendingPathComponent("drop/broken.png")
        try Data("not a png".utf8).write(to: input)
        let outcome = ConversionEngine.process(input, config: config(format: .jpeg))
        XCTAssertFalse(outcome.success)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("failed/broken.png").path))
    }

    // MARK: 배속 배지

    func testBadgeRendersRoundedTranslucentPNG() throws {
        let ffmpeg = try ffmpeg()
        let filters = FFmpeg.run(ffmpeg, ["-hide_banner", "-filters"]).stdout
        try XCTSkipUnless(filters.contains(" drawtext "), "이 ffmpeg 에 drawtext 없음")

        let badge = try XCTUnwrap(BadgeRenderer.render(speed: 4))
        defer { try? FileManager.default.removeItem(at: badge) }
        let info = try probe(badge)
        XCTAssertEqual(info.codec, "png")
        XCTAssertEqual([info.width, info.height], [BadgeRenderer.width, BadgeRenderer.height])

        // RGBA 로 풀어 모서리는 투명, 가장자리 가운데는 반투명인지 본다.
        let raw = root.appendingPathComponent("badge.rgba")
        XCTAssertTrue(FFmpeg.run(ffmpeg, ["-y", "-i", badge.path, "-f", "rawvideo", "-pix_fmt", "rgba", raw.path]).succeeded)
        let pixels = try Data(contentsOf: raw)
        XCTAssertEqual(pixels.count, BadgeRenderer.width * BadgeRenderer.height * 4)
        func alpha(_ x: Int, _ y: Int) -> UInt8 { pixels[(y * BadgeRenderer.width + x) * 4 + 3] }
        XCTAssertEqual(alpha(0, 0), 0, "둥근 모서리 바깥은 투명")
        XCTAssertEqual(Double(alpha(BadgeRenderer.width / 2, 2)), 128, accuracy: 2, "배경은 50% 검정")
    }
}
