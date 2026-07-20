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
                Toggle("드롭 타겟 변환 후 출력 폴더 열기", isOn: $settings.openOutputAfterDrop)
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
