import SwiftUI
import Combine

/// 창 스냅(윈도우 타일링) 설정: 사용 여부 · 손쉬운 사용 권한 상태 · 단축키.
struct WindowSnapSettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var trusted = WindowSnapper.isTrusted

    // 설정 창이 열려 있는 동안 권한 상태를 주기적으로 갱신(사용자가 시스템 설정에서 허용 후 돌아오면 자동 반영).
    private let refresh = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section("창 스냅") {
                Toggle("창 스냅 사용", isOn: $settings.windowSnapEnabled)
                Text("전역 단축키로 현재 창을 화면 좌/우 절반 또는 최대화로 정렬합니다. 다중 모니터에서는 창이 있는 화면 기준으로 배치됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("손쉬운 사용 권한") {
                HStack(spacing: 8) {
                    Image(systemName: trusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(trusted ? .green : .orange)
                    Text(trusted ? "권한이 허용되어 있습니다." : "다른 앱의 창을 옮기려면 권한이 필요합니다.")
                        .font(.callout)
                    Spacer(minLength: 0)
                    if !trusted {
                        Button("권한 열기") {
                            WindowSnapper.requestTrust()
                            WindowSnapper.openAccessibilitySettings()
                        }
                    }
                }
                Text("시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용에서 Sizer를 켜세요. 허용 후에도 적용되지 않으면 Sizer를 재실행하세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("단축키") {
                shortcutRow("좌측 반", .leftHalf)
                shortcutRow("우측 반", .rightHalf)
                shortcutRow("최대화", .maximize)
            }
            .disabled(!settings.windowSnapEnabled)
        }
        .formStyle(.grouped)
        .onReceive(refresh) { _ in
            let now = WindowSnapper.isTrusted
            if now != trusted { trusted = now }
        }
    }

    private func shortcutRow(_ title: String, _ action: SnapPosition) -> some View {
        LabeledContent(title) {
            ShortcutRecorder(
                display: settings.snapDisplay(action),
                hasShortcut: settings.snapHasShortcut(action),
                onCapture: { settings.setSnapShortcut(action, keyCode: $0, modifiers: $1, display: $2) },
                onClear: { settings.clearSnapShortcut(action) }
            )
        }
    }
}
