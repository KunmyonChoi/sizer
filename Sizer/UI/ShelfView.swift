import SwiftUI
import UniformTypeIdentifiers
import QuickLookThumbnailing

/// 파일 셸프 패널 내용. 평상시 정사각형으로 최소화, 호버/드래그 시 썸네일 트레이로 펼침.
struct ShelfView: View {
    @ObservedObject var store: ShelfStore
    @ObservedObject var presentation: ShelfPresentation

    @State private var targeted = false
    @State private var hovering = false
    @State private var collapseTask: Task<Void, Never>?
    @State private var dragResetTask: Task<Void, Never>?

    private let grad = LinearGradient(
        colors: [Color(hex: 0x0EA5E9), Color(hex: 0x6366F1), Color(hex: 0x8B5CF6)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    private var accent: Color { Color(hex: 0x6366F1) }

    var body: some View {
        Group {
            if presentation.expanded { expandedTray } else { collapsedIcon }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                VisualEffectBackground()
                Color.black.opacity(0.24)
            }
            .clipShape(RoundedRectangle(cornerRadius: presentation.expanded ? 22 : 16, style: .continuous))
        }
        .overlay(
            RoundedRectangle(cornerRadius: presentation.expanded ? 22 : 16, style: .continuous)
                .strokeBorder(targeted ? AnyShapeStyle(grad) : AnyShapeStyle(Color.white.opacity(0.12)),
                              lineWidth: targeted ? 2.5 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onHover { h in
            hovering = h
            if h { expand() } else { scheduleCollapse() }
        }
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in handleDrop(providers) }
        .onChange(of: targeted) { t in if t { expand() } else { scheduleCollapse() } }
    }

    // MARK: 최소화(정사각형 아이콘)

    private var collapsedIcon: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(grad)
                .frame(width: 34, height: 34)
                .overlay(Image(systemName: "square.stack.3d.up.fill").font(.system(size: 16, weight: .bold)).foregroundStyle(.white))
                .shadow(color: accent.opacity(0.5), radius: 6, y: 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if !store.isEmpty {
                Text("\(store.count)")
                    .font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
                    .frame(minWidth: 18, minHeight: 18)
                    .background(Circle().fill(accent))
                    .overlay(Circle().stroke(Color.black.opacity(0.35), lineWidth: 1.5))
                    .offset(x: -4, y: 4)
            }
        }
    }

    // MARK: 펼침(트레이)

    private var expandedTray: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.white.opacity(0.12))
            content
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(grad).frame(width: 28, height: 28)
                .overlay(Image(systemName: "square.stack.3d.up.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(.white))
            Text("파일 셸프").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
            if !store.isEmpty {
                Text("\(store.count)")
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Capsule().fill(Color.white.opacity(0.16)))
            }
            Spacer(minLength: 0)
            if !store.isEmpty {
                Button { store.clear() } label: {
                    Text("전체 지우기").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 46)
    }

    @ViewBuilder
    private var content: some View {
        if store.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "tray.and.arrow.down").font(.system(size: 26)).foregroundStyle(.white.opacity(0.55))
                Text("여기에 파일을 모아 두세요").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
                Text("Finder에서 드래그해 담고, 필요한 곳으로 다시 끌어다 놓으세요").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(store.items) { item in
                        ShelfCardView(item: item, accent: accent, onRemove: { store.remove(item) }, onDragStart: { markDragging() })
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: 접힘/펼침 제어

    private func expand() {
        collapseTask?.cancel()
        if !presentation.expanded {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { presentation.expanded = true }
        }
    }

    private func scheduleCollapse() {
        collapseTask?.cancel()
        collapseTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            if !hovering && !targeted && !presentation.dragging {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { presentation.expanded = false }
            }
        }
    }

    /// 카드 드래그 시작 → 잠시 접힘 방지 + 드래그 후 사라진 원본 정리.
    private func markDragging() {
        presentation.dragging = true
        dragResetTask?.cancel()
        dragResetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            presentation.dragging = false
            store.pruneMissing()
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []
        for provider in providers where provider.canLoadObject(ofClass: URL.self) {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url, url.isFileURL { lock.lock(); urls.append(url); lock.unlock() }
                group.leave()
            }
        }
        group.notify(queue: .main) { store.add(urls) }
        return true
    }
}

/// 셸프 카드(썸네일 + 이름). 개별 드래그로 꺼내기, 호버 시 제거 버튼.
private struct ShelfCardView: View {
    let item: ShelfItem
    let accent: Color
    let onRemove: () -> Void
    let onDragStart: () -> Void

    @State private var thumb: NSImage?
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                thumbnail
                    .frame(width: 54, height: 54)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.06)))
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                if hovering {
                    Button(action: onRemove) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15)).symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.55))
                    }
                    .buttonStyle(.plain)
                    .offset(x: 6, y: -6)
                }
            }
            Text(item.name)
                .font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.9))
                .lineLimit(1).truncationMode(.middle).frame(width: 78)
        }
        .padding(7)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(hovering ? 0.10 : 0.04)))
        .onHover { hovering = $0 }
        .onDrag {
            onDragStart()
            return NSItemProvider(object: item.url as NSURL)
        }
        .task(id: item.url) { await loadThumbnail() }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let thumb {
            Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fit).padding(3)
        } else {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path)).resizable().aspectRatio(contentMode: .fit).padding(6)
        }
    }

    private func loadThumbnail() async {
        let request = QLThumbnailGenerator.Request(
            fileAt: item.url, size: CGSize(width: 108, height: 108), scale: 2, representationTypes: .thumbnail
        )
        if let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
            thumb = rep.nsImage
        }
    }
}
