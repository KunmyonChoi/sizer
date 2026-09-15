import Foundation

/// ffmpeg 기반 이미지 변환(macOS 판은 ImageIO). 선택적 다운스케일 + 포맷/품질 지정.
///
/// - AVIF(libaom-av1 또는 libsvtav1)·JPEG·PNG 는 ffmpeg 로 인코딩한다.
/// - HEIC 출력은 libheif 의 heif-enc 로 인코딩한다(ffmpeg 는 HEIF 를 쓰지 못한다).
/// - HEIC/HEIF 입력은 heif-dec(구 이름 heif-convert)로 먼저 PNG 로 푼다.
enum ImageConverter {
    struct Result {
        let success: Bool
        let error: String?
    }

    static let heifInputExtensions: Set<String> = ["heic", "heif"]

    static func convert(src: URL, dst: URL, format: ImageFormat,
                        quality: Double, maxLongEdge: Int) -> Result {
        guard let ffmpeg = FFmpeg.ffmpegURL else { return failure("ffmpeg 없음") }
        let fm = FileManager.default
        var temps: [URL] = []
        defer { for url in temps { try? fm.removeItem(at: url) } }
        func tempURL(_ ext: String) -> URL {
            let url = fm.temporaryDirectory.appendingPathComponent("sizer-img-\(UUID().uuidString).\(ext)")
            temps.append(url)
            return url
        }

        var input = src
        if heifInputExtensions.contains(src.pathExtension.lowercased()) {
            guard let decoder = heifDecoderURL else {
                return failure("HEIC 입력에는 heif-dec가 필요합니다(sudo apt install libheif-examples)")
            }
            let png = tempURL("png")
            let r = FFmpeg.run(decoder, [src.path, png.path])
            guard r.succeeded, fm.fileExists(atPath: png.path) else {
                return failure("HEIC 디코드 실패(디코더 플러그인: sudo apt install libheif-plugin-libde265): \(tail(r.stderr + r.stdout))")
            }
            input = png
        }

        if format == .heic {
            guard let encoder = Executables.find("heif-enc") else {
                return failure("HEIC 출력에는 heif-enc가 필요합니다(sudo apt install libheif-examples)")
            }
            // 크기 조정은 ffmpeg 로 무손실 PNG 중간본을 만든 뒤 heif-enc 로 인코딩한다.
            let png = tempURL("png")
            let r1 = FFmpeg.run(ffmpeg, ffmpegArguments(input: input, output: png, format: .png,
                                                        quality: quality, maxLongEdge: maxLongEdge, avifEncoder: nil))
            guard r1.succeeded, fm.fileExists(atPath: png.path) else {
                return failure("이미지 디코드 실패: \(tail(r1.stderr))")
            }
            let r2 = FFmpeg.run(encoder, ["-q", String(heifQuality(quality)), "-o", dst.path, png.path])
            guard r2.succeeded, fm.fileExists(atPath: dst.path) else {
                let output = r2.stderr + r2.stdout
                if output.contains("No HEVC encoder") {
                    return failure("HEIC 인코더 플러그인이 없습니다(sudo apt install libheif-plugin-x265)")
                }
                return failure("HEIC 인코딩 실패: \(tail(output))")
            }
            return Result(success: true, error: nil)
        }

        var avifEncoder: String?
        if format == .avif {
            avifEncoder = detectAVIFEncoder(ffmpeg)
            guard avifEncoder != nil else {
                return failure("이 ffmpeg에는 AV1 인코더(libaom-av1/libsvtav1)가 없어 AVIF로 저장할 수 없습니다")
            }
        }
        let r = FFmpeg.run(ffmpeg, ffmpegArguments(input: input, output: dst, format: format, quality: quality,
                                                   maxLongEdge: maxLongEdge, avifEncoder: avifEncoder))
        guard r.succeeded, fm.fileExists(atPath: dst.path) else {
            return failure("\(format.label) 인코딩 실패: \(tail(r.stderr))")
        }
        return Result(success: true, error: nil)
    }

    /// ffmpeg 인자(실행 파일 제외). 출력 경로는 확장자가 .part 인 임시 파일이라 형식을 명시한다. HEIC 는 쓰지 않는다.
    static func ffmpegArguments(input: URL, output: URL, format: ImageFormat, quality: Double,
                                maxLongEdge: Int, avifEncoder: String?) -> [String] {
        var args = ["-hide_banner", "-loglevel", "error", "-y", "-i", input.path, "-frames:v", "1"]
        var filters: [String] = []
        if maxLongEdge > 0 {
            filters.append(scaleFilter(maxLongEdge: maxLongEdge, even: format == .avif))
        }
        switch format {
        case .avif:
            filters.append("format=yuv420p")
            args += ["-vf", filters.joined(separator: ",")]
            let crf = String(avifCRF(quality))
            if avifEncoder == "libsvtav1" {
                args += ["-c:v", "libsvtav1", "-crf", crf, "-preset", "8"]
            } else {
                args += ["-c:v", "libaom-av1", "-crf", crf, "-b:v", "0", "-cpu-used", "6",
                         "-row-mt", "1", "-still-picture", "1"]
            }
            args += ["-f", "avif"]
        case .jpeg:
            filters.append("format=yuvj420p")
            args += ["-vf", filters.joined(separator: ","),
                     "-c:v", "mjpeg", "-q:v", String(jpegQScale(quality)), "-f", "image2", "-update", "1"]
        case .png, .heic:
            if !filters.isEmpty { args += ["-vf", filters.joined(separator: ",")] }
            args += ["-c:v", "png", "-f", "image2", "-update", "1"]
        }
        args.append(output.path)
        return args
    }

    /// 장변을 maxLongEdge 이하로(업스케일 없음). AVIF(4:2:0)는 짝수 크기로 맞춘다.
    static func scaleFilter(maxLongEdge m: Int, even: Bool) -> String {
        let auto = even ? "-2" : "-1"
        return "scale='if(gt(iw,ih),min(\(m),iw),\(auto))':'if(gt(iw,ih),\(auto),min(\(m),ih))':flags=lanczos"
    }

    /// 품질 0~1 → AV1 CRF 63~0 (낮을수록 고화질).
    static func avifCRF(_ quality: Double) -> Int {
        Int(((1 - clamp01(quality)) * 63).rounded())
    }

    /// 품질 0~1 → mjpeg qscale 31~2 (낮을수록 고화질).
    static func jpegQScale(_ quality: Double) -> Int {
        2 + Int(((1 - clamp01(quality)) * 29).rounded())
    }

    /// 품질 0~1 → heif-enc -q 0~100.
    static func heifQuality(_ quality: Double) -> Int {
        Int((clamp01(quality) * 100).rounded())
    }

    static func detectAVIFEncoder(_ ffmpeg: URL) -> String? {
        let r = FFmpeg.run(ffmpeg, ["-hide_banner", "-encoders"], timeout: 10)
        return ["libaom-av1", "libsvtav1"].first { r.stdout.contains(" \($0) ") }
    }

    static var heifDecoderURL: URL? { Executables.find("heif-dec") ?? Executables.find("heif-convert") }

    /// heif-enc 에 HEVC 인코더가 있는지. Ubuntu 는 인코더 플러그인(libheif-plugin-x265)이 별도 패키지다.
    static func heicEncodingAvailable() -> Bool {
        guard let encoder = Executables.find("heif-enc") else { return false }
        let lines = FFmpeg.run(encoder, ["--list-encoders"], timeout: 5).stdout.split(separator: "\n")
        guard let header = lines.firstIndex(where: { $0.hasPrefix("HEIC encoders") }),
              header + 1 < lines.count else { return false }
        return lines[header + 1].hasPrefix("- ")
    }

    private static func clamp01(_ v: Double) -> Double { max(0, min(1, v)) }

    private static func failure(_ message: String) -> Result { Result(success: false, error: message) }

    private static func tail(_ text: String) -> String {
        text.split(separator: "\n").suffix(2).joined(separator: " / ")
    }
}
