import XCTest
import AppKit
@testable import Sizer

final class PanelPlacementTests: XCTestCase {

    func testClampKeepsPanelFullyInside() {
        let vf = NSRect(x: 0, y: 0, width: 1000, height: 800)
        let size = NSSize(width: 200, height: 100)

        // 오른쪽/위로 넘어간 origin → 안으로
        let over = PanelPlacement.clamp(origin: NSPoint(x: 950, y: 780), size: size, into: vf)
        XCTAssertEqual(over.x, 800, accuracy: 0.001)   // 1000 - 200
        XCTAssertEqual(over.y, 700, accuracy: 0.001)   // 800 - 100

        // 왼쪽/아래로 넘어간 origin → 안으로
        let under = PanelPlacement.clamp(origin: NSPoint(x: -50, y: -30), size: size, into: vf)
        XCTAssertEqual(under.x, 0, accuracy: 0.001)
        XCTAssertEqual(under.y, 0, accuracy: 0.001)

        // 이미 안에 있으면 그대로
        let inside = PanelPlacement.clamp(origin: NSPoint(x: 100, y: 100), size: size, into: vf)
        XCTAssertEqual(inside.x, 100, accuracy: 0.001)
        XCTAssertEqual(inside.y, 100, accuracy: 0.001)
    }

    func testOverlapArea() {
        let a = NSRect(x: 0, y: 0, width: 100, height: 100)
        XCTAssertEqual(PanelPlacement.overlapArea(a, NSRect(x: 50, y: 50, width: 100, height: 100)), 2500, accuracy: 0.001)
        XCTAssertEqual(PanelPlacement.overlapArea(a, NSRect(x: 200, y: 200, width: 50, height: 50)), 0, accuracy: 0.001)
    }

    func testVisibleOriginFallsBackWhenOffAllScreens() {
        let size = NSSize(width: 200, height: 100)
        // 아주 먼 좌표(어떤 화면과도 안 겹침) → defaultCorner 사용
        var usedDefault = false
        let origin = PanelPlacement.visibleOrigin(size: size, saved: NSPoint(x: -99999, y: -99999)) { vf in
            usedDefault = true
            return NSPoint(x: vf.minX + 10, y: vf.minY + 10)
        }
        XCTAssertTrue(usedDefault, "화면 밖 저장값이면 기본 코너로 폴백해야 함")
        // 반환 origin은 현재 어떤 화면 안에 있어야 함
        let frame = NSRect(origin: origin, size: size)
        XCTAssertTrue(NSScreen.screens.contains { PanelPlacement.overlapArea($0.visibleFrame, frame) > 0 })
    }
}
