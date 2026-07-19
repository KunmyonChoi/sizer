import AppKit

/// »N× 배속 배지를 PNG로 렌더(ffmpeg drawtext 미지원 빌드 대응 — overlay 필터로 합성).
enum BadgeRenderer {

    /// 임시 PNG를 만들어 URL 반환. 실패 시 nil. 스레드 안전을 위해 메인에서 그린다.
    static func render(speed: Int) -> URL? {
        if Thread.isMainThread { return draw(speed) }
        var result: URL?
        DispatchQueue.main.sync { result = draw(speed) }
        return result
    }

    private static func draw(_ speed: Int) -> URL? {
        let text = "» \(speed)×" as NSString
        let font = NSFont.systemFont(ofSize: 30, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let textSize = text.size(withAttributes: attrs)
        let padH: CGFloat = 22, padV: CGFloat = 12
        let size = NSSize(width: ceil(textSize.width) + padH * 2, height: ceil(textSize.height) + padV * 2)

        let image = NSImage(size: size)
        image.lockFocus()
        let rect = NSRect(origin: .zero, size: size)
        NSColor.black.withAlphaComponent(0.5).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14).fill()
        text.draw(at: NSPoint(x: padH, y: padV), withAttributes: attrs)
        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sizer-badge-\(speed)-\(UUID().uuidString).png")
        do { try png.write(to: url); return url } catch { return nil }
    }
}
