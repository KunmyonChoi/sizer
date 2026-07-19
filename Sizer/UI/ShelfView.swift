import SwiftUI
import UniformTypeIdentifiers

/// 파일 셸프 패널 내용. 접힘(엣지 탭) / 펼침(트레이) 두 상태를 렌더하고,
/// 호버·드래그 상태를 컨트롤러에 알려 펼침/접힘을 유발한다.
struct ShelfPanelView: View {
    @ObservedObject var store: ShelfStore
    var collapsed: Bool
    var edgeIsLeft: Bool
    var onHoverChange: (Bool) -> Void
    var onDragTargetChange: (Bool) -> Void

    @State private var dropTargeted = false

    private let grad = LinearGradient(
        colors: [Color(hex: 0x0EA5E9), Color(hex: 0x6366F1), Color(hex: 0x8B5CF6)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    private var accent: Color { Color(hex: 0x6366F1) }

    var body: some View {
        Group {
            if collapsed { collapsedTab } else { expandedTray }
        }
        .onHover { onHoverChange($0) }
        .onDrop(of: [.fileURL], isTargeted: Binding(
            get: { dropTargeted },
            set: { value in dropTargeted = value; onDragTargetChange(value) }
        )) { providers in handleDrop(providers) }
    }

    // MARK: 접힘 탭

    private var collapsedTab: some View {
        let corners = UnevenRoundedRectangle(
            topLeadingRadius: edgeIsLeft ? 0 : 10, bottomLeadingRadius: edgeIsLeft ? 0 : 10,
            bottomTrailingRadius: edgeIsLeft ? 10 : 0, topTrailingRadius: edgeIsLeft ? 10 : 0,
            style: .continuous
        )
        return VStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(grad)
                .frame(width: 22, height: 22)
                .overlay(Image(systemName: "square.stack.3d.up.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(.white))
            if !store.isEmpty {
                Text("\(store.count)")
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                    .frame(minWidth: 16)
                    .padding(3)
                    .background(Circle().fill(Color.white.opacity(0.20)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack { VisualEffectBackground(); Color.black.opacity(0.24) }.clipShape(corners)
        }
        .overlay(corners.strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 12, x: edgeIsLeft ? 6 : -6, y: 0)
    }

    // MARK: 펼침 트레이

    private var expandedTray: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.white.opacity(0.12))
            content
        }
        .background {
            ZStack { VisualEffectBackground(); Color.black.opacity(0.22) }
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(dropTargeted ? AnyShapeStyle(grad) : AnyShapeStyle(Color.white.opacity(0.12)),
                              lineWidth: dropTargeted ? 2.5 : 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 22, x: edgeIsLeft ? 10 : -10, y: 6)
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
        .frame(height: 44)
    }

    @ViewBuilder
    private var content: some View {
        if store.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "tray.and.arrow.down").font(.system(size: 24)).foregroundStyle(.white.opacity(0.55))
                Text("여기에 파일을 모아 두세요").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
                Text("Finder에서 드래그해 담고, 필요한 곳으로 다시 끌어다 놓으세요")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ShelfCollectionView(
                items: store.items,
                onRemove: { store.remove($0) },
                onMovedOut: { store.remove($0) }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: 드롭 인

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
