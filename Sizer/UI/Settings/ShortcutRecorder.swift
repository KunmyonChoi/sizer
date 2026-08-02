import SwiftUI
import AppKit

/// 재사용 가능한 전역 단축키 레코더. "녹음"을 누르면 다음 키 조합을 캡처해 콜백으로 넘긴다.
/// 설정 창이 key 상태이므로 로컬 이벤트 모니터로 키다운을 받아 소비한다.
struct ShortcutRecorder: View {
    let display: String
    let hasShortcut: Bool
    var placeholder: String = "없음"
    let onCapture: (_ keyCode: Int, _ modifiers: Int, _ display: String) -> Void
    let onClear: () -> Void

    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 8) {
            Text(recording ? "키 조합을 누르세요…" : (hasShortcut ? display : placeholder))
                .font(recording ? .callout : .body.monospaced())
                .foregroundStyle(recording ? Color.accentColor : (hasShortcut ? .primary : .secondary))
                .frame(minWidth: 96, alignment: .leading)
            Button(recording ? "취소" : "녹음") { recording ? stop() : start() }
            if hasShortcut && !recording {
                Button("지우기") { onClear() }
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
        let label = GlobalHotKey.keyLabel(keyCode: Int(event.keyCode), characters: chars)
        guard !label.isEmpty else { return }         // 순수 수정키만 눌린 경우 무시
        let display = GlobalHotKey.displayString(flags: mods, characters: label)
        onCapture(Int(event.keyCode), Int(mods.rawValue), display)
        stop()
    }
}
