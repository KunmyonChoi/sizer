import SwiftUI
import AppKit

/// 전역 단축키 레코더. "녹음"을 누르면 다음 키 조합을 캡처해 설정에 저장한다.
/// 설정 창이 key 상태이므로 로컬 이벤트 모니터로 키다운을 받아 소비한다.
struct ShortcutRecorder: View {
    @EnvironmentObject var settings: AppSettings
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 8) {
            Text(recording ? "키 조합을 누르세요…" : (settings.hasShortcut ? settings.shortcutDisplay : "없음"))
                .font(recording ? .callout : .body.monospaced())
                .foregroundStyle(recording ? Color.accentColor : (settings.hasShortcut ? .primary : .secondary))
                .frame(minWidth: 96, alignment: .leading)
            Button(recording ? "취소" : "녹음") { recording ? stop() : start() }
            if settings.hasShortcut && !recording {
                Button("지우기") { settings.clearShortcut() }
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil   // 이벤트 소비(다른 동작 방지)
        }
    }

    private func stop() {
        recording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func handle(_ event: NSEvent) {
        if event.keyCode == 53 { stop(); return }   // Esc → 취소
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !mods.isEmpty else { return }          // 최소 한 개의 수정키 필요
        let chars = event.charactersIgnoringModifiers ?? ""
        guard !chars.isEmpty else { return }         // 순수 수정키만 눌린 경우 무시
        let display = GlobalHotKey.displayString(flags: mods, characters: chars)
        settings.setShortcut(keyCode: Int(event.keyCode), modifiers: Int(mods.rawValue), display: display)
        stop()
    }
}
