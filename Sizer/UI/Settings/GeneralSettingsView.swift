import SwiftUI

struct GeneralSettingsView: View {
    @EnvironmentObject var coordinator: WatchCoordinator
    @EnvironmentObject var settings: AppSettings

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
