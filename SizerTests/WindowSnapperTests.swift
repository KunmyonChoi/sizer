import XCTest
import AppKit
@testable import Sizer

/// 창 스냅의 순수 기하 계산 검증(권한/실제 창 없이).
final class WindowSnapperTests: XCTestCase {

    // 메뉴바·Dock을 제외한 대표적인 visibleFrame(주 화면).
    private let vf = NSRect(x: 0, y: 0, width: 1440, height: 875)

    // 이 개발 머신의 실제 2-모니터 배치(진단으로 확인한 값):
    // 주 화면 P(노트북, 원점) + 외장 E(오른쪽·위로 올라간 배치, 높이 다름).
    private let P = SnapScreen(frame: NSRect(x: 0, y: 0, width: 1512, height: 982),
                               visibleFrame: NSRect(x: 0, y: 0, width: 1512, height: 949))
    private let E = SnapScreen(frame: NSRect(x: 1512, y: 530, width: 1920, height: 1080),
                               visibleFrame: NSRect(x: 1512, y: 530, width: 1920, height: 1080))
    private var screens: [SnapScreen] { [P, E] }

    // MARK: 반쪽/최대화 기본 기하

    func testLeftHalf() {
        XCTAssertEqual(WindowSnapper.targetFrame(for: .leftHalf, in: vf),
                       NSRect(x: 0, y: 0, width: 720, height: 875))
    }

    func testRightHalf() {
        XCTAssertEqual(WindowSnapper.targetFrame(for: .rightHalf, in: vf),
                       NSRect(x: 720, y: 0, width: 720, height: 875))
    }

    func testMaximizeEqualsVisibleFrame() {
        XCTAssertEqual(WindowSnapper.targetFrame(for: .maximize, in: vf), vf)
    }

    func testHalvesTileWithoutOverlapOrGap() {
        let left = WindowSnapper.targetFrame(for: .leftHalf, in: vf)
        let right = WindowSnapper.targetFrame(for: .rightHalf, in: vf)
        XCTAssertEqual(left.maxX, right.minX, "좌/우 반쪽은 정확히 맞닿아야 한다(겹침·틈 없음).")
        XCTAssertEqual(left.width + right.width, vf.width, accuracy: 0.001)
    }

    func testOffsetVisibleFrame() {
        let offset = NSRect(x: 80, y: 20, width: 1360, height: 855)
        XCTAssertEqual(WindowSnapper.targetFrame(for: .leftHalf, in: offset),
                       NSRect(x: 80, y: 20, width: 680, height: 855))
        XCTAssertEqual(WindowSnapper.targetFrame(for: .rightHalf, in: offset),
                       NSRect(x: 760, y: 20, width: 680, height: 855))
    }

    // MARK: 좌표 변환

    func testCocoaToAXFlipsY() {
        let ax = WindowSnapper.cocoaToAXRect(NSRect(x: 0, y: 0, width: 1440, height: 875), primaryHeight: 900)
        XCTAssertEqual(ax.origin.x, 0)
        XCTAssertEqual(ax.origin.y, 25, "상단 메뉴바(25) 아래에서 시작해야 한다.")
        XCTAssertEqual(ax.width, 1440)
        XCTAssertEqual(ax.height, 875)
    }

    func testCocoaToAXRightHalf() {
        let ax = WindowSnapper.cocoaToAXRect(NSRect(x: 720, y: 0, width: 720, height: 875), primaryHeight: 900)
        XCTAssertEqual(ax.origin.x, 720)
        XCTAssertEqual(ax.origin.y, 25)
    }

    func testCocoaToAXSecondaryMonitorNegativeY() {
        // 주 화면(높이 982) 위로 올라간 외장 모니터의 사각형 → 전역 좌상단 기준 음수 Y.
        let ax = WindowSnapper.cocoaToAXRect(NSRect(x: 1512, y: 530, width: 1920, height: 1080), primaryHeight: 982)
        XCTAssertEqual(ax.origin.x, 1512)
        XCTAssertEqual(ax.origin.y, 982 - (530 + 1080))   // = -628
    }

    // MARK: 인접 화면 판정

    func testAdjacency() {
        XCTAssertNil(WindowSnapper.adjacentScreen(of: P, in: screens, toLeft: true), "주 화면 왼쪽엔 화면 없음")
        XCTAssertEqual(WindowSnapper.adjacentScreen(of: P, in: screens, toLeft: false), E, "주 화면 오른쪽 = 외장")
        XCTAssertEqual(WindowSnapper.adjacentScreen(of: E, in: screens, toLeft: true), P, "외장 왼쪽 = 주 화면")
        XCTAssertNil(WindowSnapper.adjacentScreen(of: E, in: screens, toLeft: false), "외장 오른쪽엔 화면 없음")
    }

    // MARK: Magnet식 모니터 간 이동

    func testLeftFirstPressSnapsWithinCurrentScreen() {
        // 외장에 있는(반쪽 아님) 창 → 외장 좌측 반.
        let some = NSRect(x: 1800, y: 700, width: 800, height: 600)
        let t = WindowSnapper.resolveTarget(.leftHalf, windowFrame: some, currentScreen: E, screens: screens)
        XCTAssertEqual(t, WindowSnapper.targetFrame(for: .leftHalf, in: E.visibleFrame))
        XCTAssertEqual(t, NSRect(x: 1512, y: 530, width: 960, height: 1080))
    }

    func testLeftSecondPressCrossesToLeftMonitor() {
        // 이미 외장 좌측 반 → 왼쪽(주 화면)의 우측 반으로 이동.
        let leftHalfE = WindowSnapper.targetFrame(for: .leftHalf, in: E.visibleFrame)
        let t = WindowSnapper.resolveTarget(.leftHalf, windowFrame: leftHalfE, currentScreen: E, screens: screens)
        XCTAssertEqual(t, WindowSnapper.targetFrame(for: .rightHalf, in: P.visibleFrame))
        XCTAssertEqual(t, NSRect(x: 756, y: 0, width: 756, height: 949))
    }

    func testLeftAtLeftmostScreenStays() {
        // 주 화면 좌측 반에서 다시 왼쪽 → 왼쪽에 화면 없으니 그대로.
        let leftHalfP = WindowSnapper.targetFrame(for: .leftHalf, in: P.visibleFrame)
        let t = WindowSnapper.resolveTarget(.leftHalf, windowFrame: leftHalfP, currentScreen: P, screens: screens)
        XCTAssertEqual(t, leftHalfP)
    }

    func testRightSecondPressCrossesToRightMonitor() {
        // 이미 주 화면 우측 반 → 오른쪽(외장)의 좌측 반으로 이동.
        let rightHalfP = WindowSnapper.targetFrame(for: .rightHalf, in: P.visibleFrame)
        let t = WindowSnapper.resolveTarget(.rightHalf, windowFrame: rightHalfP, currentScreen: P, screens: screens)
        XCTAssertEqual(t, WindowSnapper.targetFrame(for: .leftHalf, in: E.visibleFrame))
        XCTAssertEqual(t, NSRect(x: 1512, y: 530, width: 960, height: 1080))
    }

    func testRightAtRightmostScreenStays() {
        let rightHalfE = WindowSnapper.targetFrame(for: .rightHalf, in: E.visibleFrame)
        let t = WindowSnapper.resolveTarget(.rightHalf, windowFrame: rightHalfE, currentScreen: E, screens: screens)
        XCTAssertEqual(t, rightHalfE)
    }

    func testOppositeHalfDoesNotCross() {
        // 외장 우측 반에서 '왼쪽' → 아직 좌측 반이 아니므로 같은 화면 좌측 반(모니터 이동 아님).
        let rightHalfE = WindowSnapper.targetFrame(for: .rightHalf, in: E.visibleFrame)
        let t = WindowSnapper.resolveTarget(.leftHalf, windowFrame: rightHalfE, currentScreen: E, screens: screens)
        XCTAssertEqual(t, WindowSnapper.targetFrame(for: .leftHalf, in: E.visibleFrame))
    }

    func testMaximizeStaysOnCurrentScreen() {
        let t = WindowSnapper.resolveTarget(.maximize, windowFrame: E.visibleFrame, currentScreen: E, screens: screens)
        XCTAssertEqual(t, E.visibleFrame)
    }

    func testSingleScreenNeverCrosses() {
        // 화면이 하나뿐이면 좌측 반에서 다시 왼쪽 → 그대로.
        let leftHalfP = WindowSnapper.targetFrame(for: .leftHalf, in: P.visibleFrame)
        let t = WindowSnapper.resolveTarget(.leftHalf, windowFrame: leftHalfP, currentScreen: P, screens: [P])
        XCTAssertEqual(t, leftHalfP)
    }

    // MARK: 허용 오차

    func testOccupiesTolerance() {
        let a = NSRect(x: 0, y: 0, width: 756, height: 949)
        XCTAssertTrue(WindowSnapper.occupies(a, NSRect(x: 10, y: 10, width: 760, height: 940)), "30pt 이내는 같은 것으로")
        XCTAssertFalse(WindowSnapper.occupies(a, NSRect(x: 100, y: 0, width: 756, height: 949)), "100pt 차이는 다른 것으로")
    }

    func testNearLeftHalfStillCrosses() {
        // 살짝 어긋난(허용 오차 이내) 좌측 반도 '이미 좌측 반'으로 보고 이동.
        let nudged = NSRect(x: 1512 + 12, y: 530 + 8, width: 960 - 10, height: 1080 - 6)
        let t = WindowSnapper.resolveTarget(.leftHalf, windowFrame: nudged, currentScreen: E, screens: screens)
        XCTAssertEqual(t, WindowSnapper.targetFrame(for: .rightHalf, in: P.visibleFrame))
    }
}
