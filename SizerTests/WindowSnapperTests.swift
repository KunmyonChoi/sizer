import XCTest
import AppKit
@testable import Sizer

/// 창 스냅의 순수 기하 계산 검증(권한/실제 창 없이).
final class WindowSnapperTests: XCTestCase {

    // 메뉴바·Dock을 제외한 대표적인 visibleFrame(주 화면).
    private let vf = NSRect(x: 0, y: 0, width: 1440, height: 875)

    func testLeftHalf() {
        let f = WindowSnapper.targetFrame(for: .leftHalf, in: vf)
        XCTAssertEqual(f, NSRect(x: 0, y: 0, width: 720, height: 875))
    }

    func testRightHalf() {
        let f = WindowSnapper.targetFrame(for: .rightHalf, in: vf)
        XCTAssertEqual(f, NSRect(x: 720, y: 0, width: 720, height: 875))
    }

    func testMaximizeEqualsVisibleFrame() {
        let f = WindowSnapper.targetFrame(for: .maximize, in: vf)
        XCTAssertEqual(f, vf)
    }

    func testHalvesTileWithoutOverlapOrGap() {
        let left = WindowSnapper.targetFrame(for: .leftHalf, in: vf)
        let right = WindowSnapper.targetFrame(for: .rightHalf, in: vf)
        XCTAssertEqual(left.maxX, right.minX, "좌/우 반쪽은 정확히 맞닿아야 한다(겹침·틈 없음).")
        XCTAssertEqual(left.width + right.width, vf.width, accuracy: 0.001)
    }

    func testOffsetVisibleFrame() {
        // Dock가 왼쪽에 있어 원점이 (80, 0)인 경우 등.
        let offset = NSRect(x: 80, y: 20, width: 1360, height: 855)
        let left = WindowSnapper.targetFrame(for: .leftHalf, in: offset)
        let right = WindowSnapper.targetFrame(for: .rightHalf, in: offset)
        XCTAssertEqual(left, NSRect(x: 80, y: 20, width: 680, height: 855))
        XCTAssertEqual(right, NSRect(x: 760, y: 20, width: 680, height: 855))
    }

    func testCocoaToAXFlipsY() {
        // 주 화면 높이 900. Cocoa 좌하단 원점 → AX 좌상단 원점.
        let cocoa = NSRect(x: 0, y: 0, width: 1440, height: 875)   // 최대화(메뉴바 25 제외)
        let ax = WindowSnapper.cocoaToAXRect(cocoa, primaryHeight: 900)
        XCTAssertEqual(ax.origin.x, 0)
        XCTAssertEqual(ax.origin.y, 25, "상단 메뉴바(25) 아래에서 시작해야 한다.")
        XCTAssertEqual(ax.width, 1440)
        XCTAssertEqual(ax.height, 875)
    }

    func testCocoaToAXRightHalf() {
        let cocoa = NSRect(x: 720, y: 0, width: 720, height: 875)
        let ax = WindowSnapper.cocoaToAXRect(cocoa, primaryHeight: 900)
        XCTAssertEqual(ax.origin.x, 720)
        XCTAssertEqual(ax.origin.y, 25)
        XCTAssertEqual(ax.width, 720)
        XCTAssertEqual(ax.height, 875)
    }
}
