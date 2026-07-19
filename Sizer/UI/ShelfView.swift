import SwiftUI
import UniformTypeIdentifiers

/// 파일 셸프 패널 내용. 평상시 접힘(작은 필), 호버/드래그 시 펼침(썸네일 트레이).
struct ShelfView: View {
    @ObservedObject var store: ShelfStore
    @ObservedObject var presentation: ShelfPresentation

    @State private var targeted = false
    @State private var hovering = false
    @State private var collapseTask: Task<Void, Never>?

    private let grad = LinearGradient(
        colors: [Color(hex: 0x0EA5E9), Color(hex: 0x6366F1), Color(hex: 0x8B5CF6)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    private var accent: Color { Color(hex: 0x6366F1) }

    var body: some View {
        Group {
            if presentation.expanded { expandedTray } else { collapsedPill }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                VisualEffectBackground()
                Color.black.opacity(0.22)
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
        .onChange(of: presentation.dragging) { d in if !d { scheduleCollapse() } }
    }

    // MARK: 접힘(작은 필)

    private var collapsedPill: some View {
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(grad)
                .frame(width: 30, height: 30)
                .overlay(Image(systemName: "square.stack.3d.up.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(.white))
            Text("셸프").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
            if !store.isEmpty {
                Text("\(store.count)")
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(.white.opacity(0.95))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(Color.white.opacity(0.18)))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
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
                .fill(grad)
                .frame(width: 28, height: 28)
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
            ShelfCollectionView(
                items: store.items,
                onRemove: { store.remove($0) },
                onMovedOut: { store.remove($0) },
                onDragSession: { presentation.dragging = $0 }
            )
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
