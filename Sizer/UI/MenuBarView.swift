import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var coordinator: WatchCoordinator
    @EnvironmentObject var settings: AppSettings

    private let maxRecentJobs = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            header

            if !coordinator.ffmpegAvailable {
                ffmpegWarning
            }

            menuDivider

            recentJobsSection

            menuDivider

            MenuActionRow(
                title: coordinator.dropTargetVisible ? "드롭 타겟 숨기기" : "드롭 타겟 표시",
                systemImage: "square.dashed"
            ) {
                coordinator.toggleDropTarget()
            }
            MenuActionRow(
                title: coordinator.shelfVisible ? "파일 셸프 숨기기" : "파일 셸프 표시",
                systemImage: "square.stack.3d.up"
            ) {
                coordinator.toggleShelf()
            }
            MenuActionRow(title: "드롭 폴더 열기", systemImage: "folder") {
                coordinator.revealDropFolder()
            }
            MenuActionRow(title: "출력 폴더 열기", systemImage: "folder.badge.gearshape") {
                coordinator.revealOutputFolder()
            }
            MenuActionRow(title: "지금 다시 스캔", systemImage: "arrow.clockwise") {
                coordinator.rescanNow()
            }
            MenuActionRow(
                title: coordinator.isPaused ? "감시 재개" : "감시 일시정지",
                systemImage: coordinator.isPaused ? "play.fill" : "pause.fill"
            ) {
                coordinator.togglePause()
            }
            MenuActionRow(title: "설정…", systemImage: "gearshape") {
                coordinator.openSettings()
            }

            menuDivider

            MenuActionRow(title: "로그 열기", systemImage: "doc.text") {
                coordinator.revealLogs()
            }
            MenuActionRow(title: "Sizer 종료", systemImage: "power", isDestructive: true) {
                coordinator.quit()
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .frame(width: 320)
    }

    // MARK: 헤더

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "film")
                .font(.system(size: 18))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text("Sizer")
                    .font(.headline)
                Text(coordinator.status.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.top, 2)
        .padding(.bottom, 4)
    }

    private var ffmpegWarning: some View {
        Text("⚠︎ ffmpeg를 찾을 수 없습니다 · brew install ffmpeg")
            .font(.caption)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
    }

    private var menuDivider: some View {
        Divider()
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
    }

    // MARK: 최근 변환

    private var recentJobsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("최근 변환")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)

            if coordinator.recentJobs.isEmpty {
                Text("최근 변환 없음")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            } else {
                ForEach(Array(coordinator.recentJobs.prefix(maxRecentJobs))) { record in
                    RecentJobRow(record: record) {
                        coordinator.play(record)
                    }
                }
            }
        }
    }
}

/// 최근 변환 항목. 성공 항목은 클릭하면 결과 영상을 재생(호버 하이라이트 + 재생 아이콘).
private struct RecentJobRow: View {
    let record: JobRecord
    let onPlay: () -> Void

    @State private var hovering = false

    private var isPlayable: Bool { record.success && record.outputURL != nil }

    private var actionIcon: String {
        record.kind == .video ? "play.circle.fill" : "photo.circle.fill"
    }

    private var helpText: String {
        record.kind == .video ? "클릭하면 재생" : "클릭하면 열기"
    }

    var body: some View {
        if isPlayable {
            Button(action: onPlay) { content }
                .buttonStyle(.plain)
                .onHover { hovering = $0 }
                .help(helpText)
        } else {
            content
        }
    }

    private var content: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(record.success ? "✅" : "❌")
                .font(.callout)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(record.sourceName)
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if isPlayable {
                        Image(systemName: actionIcon)
                            .font(.caption2)
                            .opacity(hovering ? 1 : 0.4)
                    }
                }
                Text(record.detail)
                    .font(.caption)
                    .foregroundStyle(hovering ? Color.white.opacity(0.9) : Color.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .foregroundStyle(hovering ? Color.white : Color.primary)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(hovering && isPlayable ? Color.accentColor : Color.clear)
        )
    }
}

/// 표준 macOS 메뉴 항목처럼 보이는 행: 넉넉한 높이 + 호버 하이라이트.
private struct MenuActionRow: View {
    let title: String
    let systemImage: String
    var isDestructive: Bool = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 13))
                    .frame(width: 18, alignment: .center)
                Text(title)
                    .font(.body)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .foregroundStyle(foreground)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(hovering ? Color.accentColor : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var foreground: Color {
        if hovering { return .white }
        return isDestructive ? .red : .primary
    }
}
