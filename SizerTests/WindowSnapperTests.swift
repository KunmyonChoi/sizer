import XCTest
import AppKit
@testable import Sizer

/// 창 스냅의 순수 기하 계산 검증(권한/실제 창 없이).
final class WindowSnapperTests: XCTestCase {

    // 이 개발 머신의 실제 3-모니터 배치(진단으로 확인한 값).
    // 32" U32H85x 가 노트북 '위'에 있고, DELL 이 그 오른쪽에 있다.
    private let U = SnapScreen(frame: NSRect(x: -925, y: 982, width: 3360, height: 1890),
                               visibleFrame: NSRect(x: -925, y: 982, width: 3360, height: 1890))
    private let P = SnapScreen(frame: NSRect(x: 0, y: 0, width: 1512, height: 982),
                               visibleFrame: NSRect(x: 0, y: 0, width: 1512, height: 949))
    private let D = SnapScreen(frame: NSRect(x: 2435, y: 1636, width: 1920, height: 1080),
                               visibleFrame: NSRect(x: 2435, y: 1636, width: 1920, height: 1080))
    private var screens: [SnapScreen] { [U, P, D] }

    private func slot(_ s: SnapSlot, _ screen: SnapScreen) -> NSRect {
        WindowSnapper.frame(for: s, in: screen.visibleFrame)
    }

    // MARK: 여섯 칸의 기하

    func testSlotFrames() {
        let vf = P.visibleFrame   // (0, 0, 1512, 949)
        XCTAssertEqual(WindowSnapper.frame(for: .leftThird, in: vf),
                       NSRect(x: 0, y: 0, width: 504, height: 949))
        XCTAssertEqual(WindowSnapper.frame(for: .leftHalf, in: vf),
                       NSRect(x: 0, y: 0, width: 756, height: 949))
        XCTAssertEqual(WindowSnapper.frame(for: .leftTwoThirds, in: vf),
                       NSRect(x: 0, y: 0, width: 1008, height: 949))
        XCTAssertEqual(WindowSnapper.frame(for: .rightTwoThirds, in: vf),
                       NSRect(x: 504, y: 0, width: 1008, height: 949))
        XCTAssertEqual(WindowSnapper.frame(for: .rightHalf, in: vf),
                       NSRect(x: 756, y: 0, width: 756, height: 949))
        XCTAssertEqual(WindowSnapper.frame(for: .rightThird, in: vf),
                       NSRect(x: 1008, y: 0, width: 504, height: 949))
    }

    /// 짝이 되는 두 칸은 틈도 겹침도 없이 정확히 맞닿아야 한다.
    /// 폭을 각각 나눗셈으로 계산하면 여기서 1pt 가 어긋난다.
    func testComplementarySlotsMeetExactly() {
        for screen in screens {
            let vf = screen.visibleFrame
            let pairs: [(SnapSlot, SnapSlot)] = [
                (.leftThird, .rightTwoThirds),
                (.leftHalf, .rightHalf),
                (.leftTwoThirds, .rightThird),
            ]
            for (l, r) in pairs {
                let left = WindowSnapper.frame(for: l, in: vf)
                let right = WindowSnapper.frame(for: r, in: vf)
                XCTAssertEqual(left.maxX, right.minX, accuracy: 0.0001, "\(l)/\(r) 경계가 어긋났다")
                XCTAssertEqual(left.width + right.width, vf.width, accuracy: 0.0001)
                XCTAssertEqual(left.minX, vf.minX)
                XCTAssertEqual(right.maxX, vf.maxX)
            }
        }
    }

    /// Dock 이 왼쪽에 있어 visibleFrame.minX 가 0이 아닌 화면에서도 여섯 칸이 화면 안에 들어온다.
    func testSlotsStayInsideOffsetVisibleFrame() {
        let vf = NSRect(x: 80, y: 20, width: 1360, height: 855)
        for s in SnapSlot.allCases {
            let f = WindowSnapper.frame(for: s, in: vf)
            XCTAssertGreaterThanOrEqual(f.minX, vf.minX)
            XCTAssertLessThanOrEqual(f.maxX, vf.maxX)
            XCTAssertEqual(f.minY, vf.minY)
            XCTAssertEqual(f.height, vf.height)
        }
        // 폭은 경계 좌표의 뺄셈으로 유도하므로 나눗셈 값과 마지막 자리가 다를 수 있다.
        // 정확히 지켜야 하는 것은 폭이 아니라 경계가 맞닿는 것이다(testComplementarySlotsMeetExactly).
        let third = WindowSnapper.frame(for: .leftThird, in: vf)
        XCTAssertEqual(third.minX, 80)
        XCTAssertEqual(third.width, 1360.0 / 3, accuracy: 0.0001)
        XCTAssertEqual(WindowSnapper.frame(for: .rightThird, in: vf).maxX, 1440)
    }

    // MARK: 현재 칸 판정

    func testCurrentSlotFindsEachSlot() {
        for s in SnapSlot.allCases {
            XCTAssertEqual(WindowSnapper.currentSlot(of: slot(s, P), in: P.visibleFrame), s)
        }
    }

    func testCurrentSlotIsNilForUnsnappedWindow() {
        let some = NSRect(x: 200, y: 150, width: 900, height: 600)
        XCTAssertNil(WindowSnapper.currentSlot(of: some, in: P.visibleFrame))
        XCTAssertNil(WindowSnapper.currentSlot(of: nil, in: P.visibleFrame))
    }

    func testMaximizedWindowIsNotOnAnySlot() {
        XCTAssertNil(WindowSnapper.currentSlot(of: P.visibleFrame, in: P.visibleFrame))
    }

    // MARK: 2분할 키

    func testHalfSnapsWithinScreen() {
        let some = NSRect(x: 300, y: 200, width: 700, height: 500)
        XCTAssertEqual(WindowSnapper.resolveTarget(.leftHalf, windowFrame: some, currentScreen: P, screens: screens),
                       slot(.leftHalf, P))
        XCTAssertEqual(WindowSnapper.resolveTarget(.rightHalf, windowFrame: some, currentScreen: P, screens: screens),
                       slot(.rightHalf, P))
    }

    /// 반대쪽 절반에 있는 창은 화면을 넘지 않고 이쪽 절반으로 온다.
    func testOppositeHalfDoesNotCross() {
        XCTAssertEqual(WindowSnapper.resolveTarget(.leftHalf, windowFrame: slot(.rightHalf, U), currentScreen: U, screens: screens),
                       slot(.leftHalf, U))
    }

    /// 이미 그 절반이면 한 번 더 눌러 그 방향의 화면으로 넘어간다 — 물리적으로 오른쪽인 DELL 이어야 한다.
    func testHalfCrossesToPhysicalRightScreen() {
        let t = WindowSnapper.resolveTarget(.rightHalf, windowFrame: slot(.rightHalf, U), currentScreen: U, screens: screens)
        XCTAssertEqual(t, slot(.leftHalf, D))
        XCTAssertEqual(t, NSRect(x: 2435, y: 1636, width: 960, height: 1080))
    }

    func testHalfCrossesBackToPhysicalLeftScreen() {
        let t = WindowSnapper.resolveTarget(.leftHalf, windowFrame: slot(.leftHalf, D), currentScreen: D, screens: screens)
        XCTAssertEqual(t, slot(.rightHalf, U))
    }

    /// 내장 화면은 U32H85x 에 가로로 감싸여 있어 왼쪽 이웃이 없다 — 그대로 머문다.
    func testHalfStaysWhenNoScreenOnThatSide() {
        XCTAssertEqual(WindowSnapper.resolveTarget(.leftHalf, windowFrame: slot(.leftHalf, P), currentScreen: P, screens: screens),
                       slot(.leftHalf, P))
        XCTAssertEqual(WindowSnapper.resolveTarget(.leftHalf, windowFrame: slot(.leftHalf, U), currentScreen: U, screens: screens),
                       slot(.leftHalf, U))
        XCTAssertEqual(WindowSnapper.resolveTarget(.rightHalf, windowFrame: slot(.rightHalf, D), currentScreen: D, screens: screens),
                       slot(.rightHalf, D))
    }

    func testHalfCrossesOutOfBuiltInScreen() {
        // 내장 화면 오른쪽에는 DELL 이 있다(가로로 겹치지 않는 유일한 오른쪽 화면).
        let t = WindowSnapper.resolveTarget(.rightHalf, windowFrame: slot(.rightHalf, P), currentScreen: P, screens: screens)
        XCTAssertEqual(t, slot(.leftHalf, D))
    }

    func testSingleScreenNeverCrosses() {
        XCTAssertEqual(WindowSnapper.resolveTarget(.rightHalf, windowFrame: slot(.rightHalf, P), currentScreen: P, screens: [P]),
                       slot(.rightHalf, P))
        XCTAssertEqual(WindowSnapper.resolveTarget(.leftHalf, windowFrame: slot(.leftHalf, P), currentScreen: P, screens: [P]),
                       slot(.leftHalf, P))
    }

    // MARK: 3분할 키

    func testThirdTogglesBetweenThirdAndTwoThirds() {
        let some = NSRect(x: 300, y: 200, width: 700, height: 500)
        // 처음에는 1/3.
        let first = WindowSnapper.resolveTarget(.leftThird, windowFrame: some, currentScreen: U, screens: screens)
        XCTAssertEqual(first, slot(.leftThird, U))
        // 1/3 에서 누르면 2/3.
        let second = WindowSnapper.resolveTarget(.leftThird, windowFrame: first, currentScreen: U, screens: screens)
        XCTAssertEqual(second, slot(.leftTwoThirds, U))
        // 2/3 에서 누르면 다시 1/3.
        let third = WindowSnapper.resolveTarget(.leftThird, windowFrame: second, currentScreen: U, screens: screens)
        XCTAssertEqual(third, slot(.leftThird, U))
    }

    func testRightThirdToggles() {
        let first = WindowSnapper.resolveTarget(.rightThird, windowFrame: nil, currentScreen: U, screens: screens)
        XCTAssertEqual(first, slot(.rightThird, U))
        XCTAssertEqual(WindowSnapper.resolveTarget(.rightThird, windowFrame: first, currentScreen: U, screens: screens),
                       slot(.rightTwoThirds, U))
    }

    /// 3분할 키는 화면을 넘지 않는다 — 넘기는 일은 절반 키와 즉시 이동 키가 맡는다.
    func testThirdNeverCrossesScreens() {
        for w in [slot(.rightThird, U), slot(.rightTwoThirds, U), slot(.leftThird, U)] {
            let t = WindowSnapper.resolveTarget(.rightThird, windowFrame: w, currentScreen: U, screens: screens)
            XCTAssertTrue(U.visibleFrame.contains(t), "3분할 키가 화면 밖으로 내보냈다: \(t)")
        }
    }

    /// 와이드 화면 2/3 + 1/3 조합: 두 창 모두 두 번이면 정확히 맞닿는다.
    func testTwoThirdsPlusThirdTileExactly() {
        let a = WindowSnapper.resolveTarget(.leftThird, windowFrame: nil, currentScreen: U, screens: screens)
        let editor = WindowSnapper.resolveTarget(.leftThird, windowFrame: a, currentScreen: U, screens: screens)
        let browser = WindowSnapper.resolveTarget(.rightThird, windowFrame: nil, currentScreen: U, screens: screens)
        XCTAssertEqual(editor, NSRect(x: -925, y: 982, width: 2240, height: 1890))
        XCTAssertEqual(browser, NSRect(x: 1315, y: 982, width: 1120, height: 1890))
        XCTAssertEqual(editor.maxX, browser.minX, accuracy: 0.0001)
        XCTAssertEqual(editor.width + browser.width, U.visibleFrame.width, accuracy: 0.0001)
    }

    // MARK: 그 방향의 화면(절반 키)

    func testSideScreenFollowsPhysicalLayout() {
        XCTAssertEqual(WindowSnapper.sideScreen(of: U, in: screens, toLeft: false), D, "U32H85x 오른쪽은 DELL")
        XCTAssertNil(WindowSnapper.sideScreen(of: U, in: screens, toLeft: true))
        XCTAssertEqual(WindowSnapper.sideScreen(of: P, in: screens, toLeft: false), D, "내장 오른쪽도 DELL")
        XCTAssertNil(WindowSnapper.sideScreen(of: P, in: screens, toLeft: true), "내장은 U32H85x 에 감싸여 왼쪽 이웃이 없다")
        XCTAssertEqual(WindowSnapper.sideScreen(of: D, in: screens, toLeft: true), U)
        XCTAssertNil(WindowSnapper.sideScreen(of: D, in: screens, toLeft: false))
    }

    /// 회귀 방지: 화면 중심(midX)으로 좌우를 가르면 1pt 차이로 U32H85x 와 내장이 좌우로 갈렸다.
    /// 가로가 겹치는 두 화면은 좌우 관계가 아니다.
    func testHorizontallyOverlappingScreensAreNotSideBySide() {
        XCTAssertEqual(U.frame.midX, 755)
        XCTAssertEqual(P.frame.midX, 756)
        XCTAssertNotEqual(WindowSnapper.sideScreen(of: P, in: screens, toLeft: true), U)
        XCTAssertNotEqual(WindowSnapper.sideScreen(of: U, in: screens, toLeft: false), P)
    }

    func testSideScreenIsIndependentOfInputOrder() {
        let permutations: [[SnapScreen]] = [[U, P, D], [D, P, U], [P, D, U], [P, U, D], [D, U, P], [U, D, P]]
        for input in permutations {
            XCTAssertEqual(WindowSnapper.sideScreen(of: U, in: input, toLeft: false), D)
            XCTAssertEqual(WindowSnapper.sideScreen(of: D, in: input, toLeft: true), U)
        }
    }

    // MARK: 좌표 변환

    func testCocoaToAXFlipsY() {
        let ax = WindowSnapper.cocoaToAXRect(NSRect(x: 0, y: 0, width: 1440, height: 875), primaryHeight: 900)
        XCTAssertEqual(ax.origin.x, 0)
        XCTAssertEqual(ax.origin.y, 25, "상단 메뉴바(25) 아래에서 시작해야 한다.")
        XCTAssertEqual(ax.width, 1440)
        XCTAssertEqual(ax.height, 875)
    }

    func testCocoaToAXSecondaryMonitorNegativeY() {
        // 주 화면(높이 982) 위로 올라간 외장 모니터의 사각형 → 전역 좌상단 기준 음수 Y.
        let ax = WindowSnapper.cocoaToAXRect(NSRect(x: -925, y: 982, width: 3360, height: 1890), primaryHeight: 982)
        XCTAssertEqual(ax.origin.x, -925)
        XCTAssertEqual(ax.origin.y, 982 - (982 + 1890))   // = -1890
    }

    // MARK: 허용 오차

    func testOccupiesTolerance() {
        let a = NSRect(x: 0, y: 0, width: 756, height: 949)
        XCTAssertTrue(WindowSnapper.occupies(a, NSRect(x: 10, y: 10, width: 760, height: 940)), "30pt 이내는 같은 것으로")
        XCTAssertFalse(WindowSnapper.occupies(a, NSRect(x: 100, y: 0, width: 756, height: 949)), "100pt 차이는 다른 것으로")
    }

    /// 살짝 어긋난(허용 오차 이내) 칸도 그 칸으로 보고 다음 칸으로 옮긴다.
    func testNudgedSlotStillAdvances() {
        let nudged = slot(.leftHalf, P).insetBy(dx: -8, dy: 6).offsetBy(dx: 12, dy: -4)
        XCTAssertEqual(WindowSnapper.currentSlot(of: nudged, in: P.visibleFrame), .leftHalf)
        XCTAssertEqual(WindowSnapper.resolveTarget(.leftThird, windowFrame: slot(.leftThird, P), currentScreen: P, screens: screens),
                       slot(.leftTwoThirds, P))
    }

    /// 이웃한 두 칸은 화면 폭의 1/6 만큼 떨어져 있어 30pt 오차 안에서 서로 헷갈리지 않는다.
    func testAdjacentSlotsAreFarApartEnough() {
        for screen in screens {
            let vf = screen.visibleFrame
            for s in SnapSlot.allCases.dropLast() {
                guard let next = SnapSlot(rawValue: s.rawValue + 1) else { continue }
                XCTAssertFalse(WindowSnapper.occupies(WindowSnapper.frame(for: s, in: vf),
                                                      WindowSnapper.frame(for: next, in: vf)),
                               "\(s) 와 \(next) 가 허용 오차 안에서 겹쳐 보인다")
            }
        }
    }

}
