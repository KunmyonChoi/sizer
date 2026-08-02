import SwiftUI

/// 모니터 꺼짐 방지 설정: 지금 켜기 · 전환 단축키. (창 스냅처럼 별도 탭)
struct KeepAwakeSettingsView: View {
    @EnvironmentObject var coordinator: WatchCoordinator
    @EnvironmentObject var settings: AppSettings

    /// 상태는 코디네이터가 소유(실행 중에만 유지). 값이 바뀔 때만 토글.
    private var keepAwakeBinding: Binding<Bool> {
        Binding(
            get: { coordinator.keepAwake },
            set: { on in if on != coordinator.keepAwake { coordinator.toggleKeepAwake() } }
        )
    }

    var body: some View {
        Form {
            Section("모니터 꺼짐 방지") {
                Toggle("지금 켜기", isOn: keepAwakeBinding)
                Text("켜져 있는 동안 화면이 자동으로 꺼지거나 절전되지 않습니다(발표·긴 다운로드·모니터링 등). 메뉴바에서도 켤 수 있고, 앱을 끄면 해제됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LabeledContent("전환 단축키") {
                    ShortcutRecorder(
                        display: settings.keepAwakeDisplay,
                        hasShortcut: settings.keepAwakeHasShortcut,
                        onCapture: { settings.setKeepAwakeShortcut(keyCode: $0, modifiers: $1, display: $2) },
                        onClear: { settings.clearKeepAwakeShortcut() }
                    )
                }
                Text("별도 권한이 필요 없습니다(IOKit 전원 어서션).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
