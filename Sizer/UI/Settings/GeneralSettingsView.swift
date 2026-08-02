import SwiftUI

struct GeneralSettingsView: View {
    @EnvironmentObject var coordinator: WatchCoordinator
    @EnvironmentObject var settings: AppSettings

    /// 모니터 꺼짐 방지 상태는 코디네이터가 소유(실행 중에만 유지). 값이 바뀔 때만 토글.
    private var keepAwakeBinding: Binding<Bool> {
        Binding(
            get: { coordinator.keepAwake },
            set: { on in if on != coordinator.keepAwake { coordinator.toggleKeepAwake() } }
        )
    }

    var body: some View {
        Form {
            Section("폴더") {
                folderRow(
                    title: "드롭(감시) 폴더",
                    path: settings.dropFolderPath,
                    kind: .drop
                )
                folderRow(
                    title: "출력 폴더",
                    path: settings.outputFolderPath,
                    kind: .output
                )
                folderRow(
                    title: "완료 폴더",
                    path: settings.processedFolderPath,
                    kind: .processed
                )
                folderRow(
                    title: "실패 폴더",
                    path: settings.failedFolderPath,
                    kind: .failed
                )
            }

            Section("일반") {
                Toggle("로그인 시 자동 시작", isOn: $settings.launchAtLogin)
                Toggle("변환 완료·실패 알림 표시", isOn: $settings.notificationsEnabled)
                Toggle("드롭 타겟 변환 후 출력 폴더 열기", isOn: $settings.openOutputAfterDrop)
            }

            Section("모니터 꺼짐 방지") {
                Toggle("지금 켜기", isOn: keepAwakeBinding)
                Text("켜져 있는 동안 화면이 자동으로 꺼지거나 절전되지 않습니다. 메뉴바에서도 켤 수 있고, 앱을 끄면 해제됩니다.")
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
            }

            Section("드롭 & 셸프") {
                Toggle("드롭 타겟을 파일 셸프에 통합", isOn: $settings.integratedDrop)
                Text("한 패널에서 상단은 변환, 하단은 보관. 끄면 드롭 타겟과 셸프가 분리됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("변환 결과를 셸프에 추가", isOn: $settings.addResultToShelf)
                    .disabled(!settings.integratedDrop)
                Text("변환이 끝난 결과 파일을 보관 트레이 맨 앞에 얹어 바로 옮길 수 있게 합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("패널 위치", selection: $settings.shelfSideRaw) {
                    Text("왼쪽").tag(ShelfSide.left.rawValue)
                    Text("오른쪽").tag(ShelfSide.right.rawValue)
                }
                LabeledContent("패널 열기/닫기 단축키") {
                    ShortcutRecorder(
                        display: settings.shortcutDisplay,
                        hasShortcut: settings.hasShortcut,
                        onCapture: { settings.setShortcut(keyCode: $0, modifiers: $1, display: $2) },
                        onClear: { settings.clearShortcut() }
                    )
                }
                Text("어디서든 이 단축키로 패널을 열고 닫습니다. 접근성 권한이 필요 없습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("정리") {
                Toggle("오래된 원본 자동 삭제(processed)", isOn: $settings.autoCleanProcessedEnabled)
                Picker("보관 기간", selection: $settings.processedRetentionDays) {
                    Text("7일").tag(7)
                    Text("30일").tag(30)
                    Text("90일").tag(90)
                    Text("180일").tag(180)
                }
                .disabled(!settings.autoCleanProcessedEnabled)
                Text("보관 기간이 지난 원본을 processed 폴더에서 자동으로 삭제합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("정보") {
                LabeledContent("버전") {
                    Text(AppInfo.fullVersion)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func folderRow(title: String, path: String, kind: FolderKind) -> some View {
        LabeledContent(title) {
            HStack {
                Text(path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Button("변경…") {
                    coordinator.chooseFolder(for: kind)
                }
            }
        }
    }
}
