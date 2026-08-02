import Foundation
import IOKit.pwr_mgt

/// 모니터(디스플레이) 꺼짐/절전 방지. IOKit 전원 어서션 사용 — 별도 권한이 필요 없다.
/// 어서션이 살아 있는 동안 유휴 상태여도 화면이 꺼지지 않으며 시스템 절전도 함께 막힌다.
/// (`pmset -g assertions` 또는 활동 모니터 > 에너지에서 확인 가능.)
@MainActor
final class WakeGuard {
    private var assertionID: IOPMAssertionID = 0
    private(set) var isActive = false

    /// 어서션 표시 이름(진단 도구에 노출된다).
    private let reason = "Sizer: 모니터 꺼짐 방지" as CFString

    @discardableResult
    func enable() -> Bool {
        guard !isActive else { return true }
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &id
        )
        guard result == kIOReturnSuccess else {
            AppLogger.warn("모니터 꺼짐 방지 어서션 생성 실패(코드 \(result)).")
            return false
        }
        assertionID = id
        isActive = true
        return true
    }

    func disable() {
        guard isActive else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
        isActive = false
    }

    /// 상태를 뒤집고 최종 활성 여부를 반환.
    @discardableResult
    func toggle() -> Bool {
        if isActive { disable(); return false }
        return enable()
    }

    deinit {
        if isActive { IOPMAssertionRelease(assertionID) }
    }
}
