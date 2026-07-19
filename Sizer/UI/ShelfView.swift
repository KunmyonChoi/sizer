import SwiftUI
import UniformTypeIdentifiers

/// 파일 셸프 패널 내용. 드롭해 담고, 카드에서 개별/다중 선택해 Finder로 드래그-아웃.
struct ShelfView: View {
    @ObservedObject var store: ShelfStore
    @State private var targeted = false

    private let grad = LinearGradient(
        colors: [Color(hex: 0x0EA5E9), Color(hex: 0x6366F1), Color(hex: 0x8B5CF6)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    private var accent: Color { Color(hex: 0x6366F1) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.white.opacity(0.12))
            content
        }
        .frame(width: 440, height: 178)
        .background {
            ZStack {
                VisualEffectBackground()
                Color.black.opacity(0.22)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(targeted ? AnyShapeStyle(grad) : AnyShapeStyle(Color.white.opacity(0.12)),
                              lineWidth: targeted ? 2.5 : 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 20, y: 10)
        .shadow(color: targeted ? accent.opacity(0.5) : .clear, radius: 26)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: targeted)
        .padding(16)
        .onDrop(of: [.fileURL], isTargeted: $targeted.animation()) { providers in handleDrop(providers) }
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
                Button {
                    store.clear()
                } label: {
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
                Image(systemName: "tray.and.arrow.down")
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(.white.opacity(0.55))
                Text("여기에 파일을 모아 두세요")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
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
