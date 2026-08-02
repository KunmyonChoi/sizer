import XCTest
@testable import Sizer

/// 모니터 꺼짐 방지 어서션 생성/해제/토글 검증(실제 IOKit 경로).
@MainActor
final class WakeGuardTests: XCTestCase {

    func testEnableThenDisable() {
        let guard1 = WakeGuard()
        XCTAssertFalse(guard1.isActive)

        XCTAssertTrue(guard1.enable(), "전원 어서션 생성은 일반 macOS에서 성공해야 한다.")
        XCTAssertTrue(guard1.isActive)

        guard1.disable()
        XCTAssertFalse(guard1.isActive)
    }

    func testToggleFlipsAndReturnsState() {
        let g = WakeGuard()
        XCTAssertTrue(g.toggle(), "꺼진 상태에서 토글하면 켜지고 true를 반환.")
        XCTAssertTrue(g.isActive)
        XCTAssertFalse(g.toggle(), "켜진 상태에서 토글하면 꺼지고 false를 반환.")
        XCTAssertFalse(g.isActive)
        g.disable()   // 정리(이미 꺼져 있으면 무연산)
    }

    func testEnableIsIdempotent() {
        let g = WakeGuard()
        XCTAssertTrue(g.enable())
        XCTAssertTrue(g.enable(), "이미 켜져 있으면 재호출도 true(중복 어서션 생성 안 함).")
        XCTAssertTrue(g.isActive)
        g.disable()
        XCTAssertFalse(g.isActive)
    }
}
