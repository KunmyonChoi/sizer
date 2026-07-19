import SwiftUI

/// 엣지-도킹 셸프 내용. 왼쪽 얇은 핸들 + 오른쪽 트레이(카드). 패널 폭이 접힘/펼침을 결정하고
/// 내용은 항상 펼친 크기로 배치되어(핸들이 x=0), 패널이 좁을 땐 핸들만 보인다.
struct ShelfView: View {
    @ObservedObject var store: ShelfStore
    var onDragSession: (Bool) -> Void = { _ in }

    static let handleWidth: CGFloat = 22
    static let trayWidth: CGFloat = 450
    static let height: CGFloat = 220
    static var expandedWidth: CGFloat { handleWidth + trayWidth }

    private let grad = LinearGradient(
        colors: [Color(hex: 0x0EA5E9), Color(hex: 0x6366F1), Color(hex: 0x8B5CF6)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    var body: some View {
        HStack(spacing: 0) {
            handle
            Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1)
            tray
        }
        .frame(width: Self.expandedWidth, height: Self.height)
        .background {
            ZStack {
                VisualEffectBackground()
                Color.black.opacity(0.24)
            }
            .clipShape(edgeShape)
        }
        .overlay(edgeShape.strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.30), radius: 22, x: 8, y: 6)
    }

    private var edgeShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0,
                               bottomTrailingRadius: 24, topTrailingRadius: 24, style: .continuous)
    }

    // MARK: 핸들(접힘 시 보이는 얇은 탭)

    private var handle: some View {
        VStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(grad)
                .frame(width: 15, height: 15)
                .overlay(Image(systemName: "square.stack.3d.up.fill").font(.system(size: 8, weight: .bold)).foregroundStyle(.white))
            Image(systemName: "chevron.compact.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white.opacity(0.4))
            Spacer()
            if !store.isEmpty {
                Text("\(min(store.count, 99))")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color(hex: 0x6366F1)))
            }
        }
        .padding(.vertical, 12)
        .frame(width: Self.handleWidth)
    }

    // MARK: 트레이(펼침 시 카드)

    private var tray: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("파일 셸프").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                if !store.isEmpty {
                    Text("\(store.count)")
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 7).padding(.vertical, 1)
                        .background(Capsule().fill(Color.white.opacity(0.16)))
                }
                Spacer(minLength: 0)
                if !store.isEmpty {
                    Button { store.clear() } label: {
                        Text("전체 지우기").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14).frame(height: 40)

            Divider().overlay(Color.white.opacity(0.10))

            if store.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down").font(.system(size: 24)).foregroundStyle(.white.opacity(0.5))
                    Text("여기에 파일을 모아 두세요").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
                    Text("Finder에서 끌어와 담고, 필요한 곳으로 다시 끌어다 놓으세요").font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ShelfCollectionView(
                    items: store.items,
                    onRemove: { store.remove($0) },
                    onMovedOut: { store.remove($0) },
                    onDragSession: onDragSession
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: Self.trayWidth)
    }
}
