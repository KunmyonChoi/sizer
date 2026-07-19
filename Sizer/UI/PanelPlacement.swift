import AppKit

/// 플로팅 패널이 항상 화면 안에 보이도록 위치를 계산·보정한다(멀티 모니터/구성 변경 대응).
enum PanelPlacement {

    static func overlapArea(_ a: NSRect, _ b: NSRect) -> CGFloat {
        let i = a.intersection(b)
        return (i.isNull || i.isEmpty) ? 0 : i.width * i.height
    }

    /// origin을 vf 안에 완전히 들어오도록 클램프.
    static func clamp(origin: NSPoint, size: NSSize, into vf: NSRect) -> NSPoint {
        let maxX = max(vf.minX, vf.maxX - size.width)
        let maxY = max(vf.minY, vf.maxY - size.height)
        return NSPoint(x: min(max(origin.x, vf.minX), maxX),
                       y: min(max(origin.y, vf.minY), maxY))
    }

    /// saved가 어떤 화면과도 겹치지 않으면(모니터 변경 등) 기본 코너로. 겹치면 그 화면 안으로 완전 클램프.
    static func visibleOrigin(size: NSSize, saved: NSPoint?, defaultCorner: (NSRect) -> NSPoint) -> NSPoint {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return saved ?? .zero }

        if let saved {
            let frame = NSRect(origin: saved, size: size)
            if let best = screens.max(by: { overlapArea($0.visibleFrame, frame) < overlapArea($1.visibleFrame, frame) }),
               overlapArea(best.visibleFrame, frame) > 0 {
                return clamp(origin: saved, size: size, into: best.visibleFrame)
            }
        }
        let screen = NSScreen.main ?? screens[0]
        return defaultCorner(screen.visibleFrame)
    }

    /// origin(패널 좌하단)이 속한 화면의 visibleFrame. 없으면 main.
    static func screenVisibleFrame(containing origin: NSPoint) -> NSRect {
        let probe = NSPoint(x: origin.x + 4, y: origin.y + 4)
        let screen = NSScreen.screens.first(where: { NSPointInRect(probe, $0.frame) }) ?? NSScreen.main ?? NSScreen.screens.first
        return screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    }
}
