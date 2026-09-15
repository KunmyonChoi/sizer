import Foundation

/// »N× 배속 배지 PNG 를 ffmpeg 로 그린다(macOS 판은 AppKit). FilterGraphBuilder 가 overlay 로 합성한다.
/// 반투명 검정 둥근 사각형 + 흰 굵은 글자 — macOS 배지와 같은 모양. drawtext 가 없는 ffmpeg 면 배지 없이 변환한다.
enum BadgeRenderer {
    static let width = 150
    static let height = 58
    static let cornerRadius = 14

    static func render(speed: Int) -> URL? {
        guard let ffmpeg = FFmpeg.ffmpegURL else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sizer-badge-\(speed)-\(UUID().uuidString).png")
        let r = FFmpeg.run(ffmpeg, arguments(speed: speed, output: url, fontFile: boldFontFile()), timeout: 30)
        guard r.succeeded, FileManager.default.fileExists(atPath: url.path) else {
            let tail = r.stderr.split(separator: "\n").suffix(2).joined(separator: " / ")
            AppLogger.warn("배속 배지 생성 실패(ffmpeg drawtext 필요) — 배지 없이 변환: \(tail)")
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return url
    }

    static func arguments(speed: Int, output: URL, fontFile: String?) -> [String] {
        let r = cornerRadius
        // 모서리 사분원 바깥은 투명, 나머지는 알파 128(50%).
        let dx = "abs(X-W/2)-(W/2-\(r))"
        let dy = "abs(Y-H/2)-(H/2-\(r))"
        let alpha = "if(gt(\(dx),0)*gt(\(dy),0)*gt(hypot(\(dx),\(dy)),\(r)),0,128)"
        var text = "drawtext=text=» \(speed)×:fontsize=30:fontcolor=white:x=(w-text_w)/2:y=(h-text_h)/2"
        if let fontFile { text += ":fontfile=\(fontFile)" }
        return [
            "-hide_banner", "-loglevel", "error", "-y",
            "-f", "lavfi", "-i", "color=c=black:s=\(width)x\(height):d=1",
            "-vf", "format=rgba,geq=r='0':g='0':b='0':a='\(alpha)',\(text)",
            "-frames:v", "1", "-c:v", "png", "-f", "image2", "-update", "1", output.path,
        ]
    }

    /// fontconfig 가 고른 굵은 산세리프 글꼴 파일. 필터 문법과 충돌하는 문자가 든 경로는 쓰지 않는다
    /// (그 경우 drawtext 가 fontconfig 기본 글꼴을 쓴다).
    static func boldFontFile() -> String? {
        guard let fcMatch = Executables.find("fc-match") else { return nil }
        let r = FFmpeg.run(fcMatch, ["--format=%{file}", "sans:bold"], timeout: 5)
        let path = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard r.succeeded, path.hasPrefix("/"),
              path.rangeOfCharacter(from: CharacterSet(charactersIn: ":,;[]'\\")) == nil else { return nil }
        return path
    }
}
