import Foundation
import ServiceManagement

/// 로그인 시 자동 시작(SMAppService.mainApp).
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            return true
        } catch {
            AppLogger.error("로그인 항목 설정 실패: \(error.localizedDescription)")
            return false
        }
    }
}
