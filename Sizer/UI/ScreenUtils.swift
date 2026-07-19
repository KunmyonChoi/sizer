import AppKit

/// 플로팅 패널을 화면 안에 유지하기 위한 헬퍼(모니터 변경·다중 화면 대응).
enum ScreenUtils {

    /// 마우스 커서가 현재 위치한 화면.
    static func screenWithMouse() -> NSScreen? {
        let loc = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(loc, $0.frame, false) } ?? NSScreen.main
    }

    /// 프레임이 어떤 화면과도 충분히(minVisible 이상) 겹치지 않으면 메인 화면 안으로 이동.
    static func clampedOnScreen(_ frame: NSRect, minVisible: CGFloat = 48) -> NSRect {
        let screens = NSScreen.screens
        let visibleEnough = screens.contains { screen in
            let inter = screen.visibleFrame.intersection(frame)
            return inter.width >= min(minVisible, frame.width) && inter.height >= min(minVisible, frame.height)
        }
        if visibleEnough { return frame }

        let target = (NSScreen.main ?? screens.first)?.visibleFrame ?? frame
        var f = frame
        f.origin.x = min(max(f.origin.x, target.minX), max(target.minX, target.maxX - f.width))
        f.origin.y = min(max(f.origin.y, target.minY), max(target.minY, target.maxY - f.height))
        return f
    }
}
