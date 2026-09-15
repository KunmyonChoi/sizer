import Foundation

/// 데스크톱 알림(freedesktop 알림 규격) — libnotify-bin 의 notify-send 를 쓴다(macOS 판은 UserNotifications).
/// notify-send 가 없으면(서버·최소 설치) 로그만 남긴다.
enum Notifier {
    /// 알림을 .desktop 항목과 묶어 GNOME 이 앱 이름·아이콘으로 표시하게 한다.
    static let desktopEntry = "com.dilly.sizer"

    /// ConversionEngine 이 쓰는 기본 알림(버튼 없음).
    static func notify(title: String, body: String, subtitle: String = "") {
        send(title: title, body: subtitle.isEmpty ? body : "\(body)\n\(subtitle)")
    }

    /// 변환 결과 알림.
    /// - withActions: "열기"/"폴더에서 보기" 버튼을 단다. 버튼 응답은 알림이 닫힐 때까지 이 프로세스가 받아야 하므로
    ///   계속 떠 있는 데몬에서만 켠다.
    /// - failureNote: 실패 시 본문 둘째 줄(없으면 엔진의 설명).
    static func notifyOutcome(_ outcome: JobOutcome, withActions: Bool, failureNote: String? = nil) {
        let image = outcome.kind == .image
        guard outcome.success else {
            send(title: image ? "이미지 변환 실패 ❌" : "변환 실패 ❌",
                 body: "\(outcome.sourceName)\n\(failureNote ?? outcome.detail)")
            return
        }
        let title = image ? "이미지 변환 완료 ✅" : "Sizer 변환 완료 ✅"
        let body = "\(outcome.outputName ?? outcome.sourceName)\n\(outcome.detail)"
        guard withActions, let output = outcome.outputURL else {
            send(title: title, body: body)
            return
        }
        // "default" 는 GNOME 에서 버튼이 아니라 알림 자체를 눌렀을 때의 동작이다.
        send(title: title, body: body,
             actions: [("default", "열기"), ("open", "열기"), ("reveal", "폴더에서 보기")]) { key in
            switch key {
            case "default", "open": Desktop.open(output)
            case "reveal": Desktop.reveal(output)
            default: break
            }
        }
    }

    static func arguments(title: String, body: String, actions: [(key: String, label: String)]) -> [String] {
        var args = ["--app-name=Sizer", "--icon=\(desktopEntry)", "--hint=string:desktop-entry:\(desktopEntry)"]
        for action in actions { args.append("--action=\(action.key)=\(action.label)") }
        return args + ["--", title, markupEscaped(body)]
    }

    /// 알림 본문은 간단한 마크업으로 해석되므로 파일명의 &, <, > 를 이스케이프한다.
    static func markupEscaped(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func send(title: String, body: String, actions: [(key: String, label: String)] = [],
                             onAction: ((String) -> Void)? = nil) {
        guard let notifySend = Executables.find("notify-send") else {
            AppLogger.info("알림(notify-send 없음): \(title) — \(body.replacingOccurrences(of: "\n", with: " · "))")
            return
        }
        let process = Process()
        process.executableURL = notifySend
        process.arguments = arguments(title: title, body: body, actions: actions)
        process.standardError = FileHandle.nullDevice
        if let onAction {
            // --action 이 있으면 notify-send 는 알림이 닫힐 때까지 기다렸다가 누른 동작의 키를 출력한다.
            // 오래 떠 있을 수 있으니 스레드를 붙잡지 않고 종료 핸들러에서 읽는다.
            let out = Pipe()
            process.standardOutput = out
            process.terminationHandler = { _ in
                let data = out.fileHandleForReading.readDataToEndOfFile()
                let key = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                if !key.isEmpty { onAction(key) }
            }
        } else {
            process.standardOutput = FileHandle.nullDevice
        }
        do {
            try process.run()
        } catch {
            AppLogger.warn("알림 표시 실패: \(error)")
        }
    }
}
