import Foundation
import UserNotifications

/// UserNotifications 배너(osascript 대체).
enum Notifier {
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                AppLogger.warn("알림 권한 요청 실패: \(error.localizedDescription)")
            } else if !granted {
                AppLogger.warn("알림 권한이 거부되었습니다.")
            }
        }
    }

    static func notify(title: String, body: String, subtitle: String = "") {
        let content = UNMutableNotificationContent()
        content.title = title
        if !subtitle.isEmpty { content.subtitle = subtitle }
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { AppLogger.warn("알림 표시 실패: \(error.localizedDescription)") }
        }
    }
}
