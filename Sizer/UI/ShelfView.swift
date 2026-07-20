import SwiftUI

/// 엣지-도킹 통합 패널. 왼쪽 얇은 핸들 + 오른쪽 트레이. 트레이는 (통합 시) 상단 변환 드롭존과
/// 하단 보관 트레이 두 존으로 구성된다. 패널 폭이 접힘/펼침을 결정하고, 내용은 항상 펼친 크기로
/// 배치되어(핸들이 x=0) 패널이 좁을 땐 핸들만 보인다.
struct ShelfView: View {
    @ObservedObject var store: ShelfStore
    @ObservedObject var dropState: ShelfDropState
    var showConvertZone: Bool = true
    var onDragSession: (Bool) -> Void = { _ in }

    static let handleWidth: CGFloat = 22
    static let trayWidth: CGFloat = 450
    static let baseTrayHeight: CGFloat = 220     // 보관 헤더 + 카드 영역
    static let convertZoneHeight: CGFloat = 104  // 상단 변환 드롭존(카드 외부 여백 포함)
    static var expandedWidth: CGFloat { handleWidth + trayWidth }

    /// 통합 여부에 따른 패널 전체 높이(컨트롤러의 히트테스트와 일치해야 함).
    static func panelHeight(showConvertZone: Bool) -> CGFloat {
        showConvertZone ? baseTrayHeight + convertZoneHeight : baseTrayHeight
    }

    private let grad = LinearGradient(
        colors: [Color(hex: 0x0EA5E9), Color(hex: 0x6366F1), Color(hex: 0x8B5CF6)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    private var accent: Color { Color(hex: 0x6366F1) }
    private var convertActive: Bool { dropState.activeZone == .convert }
    private var holdActive: Bool { dropState.activeZone == .hold }

    var body: some View {
        HStack(spacing: 0) {
            handle
            Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1)
            tray
        }
        .frame(width: Self.expandedWidth, height: Self.panelHeight(showConvertZone: showConvertZone))
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

    // MARK: 트레이(변환 드롭존 + 보관 트레이)

    private var tray: some View {
        VStack(spacing: 0) {
            if showConvertZone {
                convertZone
                Divider().overlay(Color.white.opacity(0.10))
            }
            holdingHeader
            holdingBody
        }
        .frame(width: Self.trayWidth)
    }

    // MARK: 상단 — 변환 드롭존

    private enum CZState { case idle, active, success(Int), reject }
    private var czState: CZState {
        if dropState.rejectFlash { return .reject }
        if let n = dropState.convertFlash { return .success(n) }
        if convertActive { return .active }
        return .idle
    }
    private var czTitle: String {
        switch czState {
        case .reject: return "변환할 수 없는 형식"
        case .success(let n): return "\(n)개 변환 시작"
        case .active: return "여기에 놓기"
        case .idle: return "드롭하여 변환"
        }
    }
    private var czSubtitle: String {
        switch czState {
        case .reject: return "영상·이미지 파일만 가능합니다"
        case .success: return "변환을 시작합니다"
        case .active: return "놓으면 변환을 시작합니다"
        case .idle: return "영상·이미지 · Finder에서 끌어오기"
        }
    }
    private var czIcon: String {
        switch czState {
        case .reject: return "xmark"
        case .success: return "checkmark"
        default: return "tray.and.arrow.down.fill"
        }
    }
    private var czBadgeStyle: AnyShapeStyle {
        switch czState {
        case .reject: return AnyShapeStyle(Color(hex: 0xF59E0B))
        case .success: return AnyShapeStyle(Color(hex: 0x22C55E))
        default: return AnyShapeStyle(grad)
        }
    }

    private var convertZone: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(czBadgeStyle)
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: czIcon)
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(.white)
                )
                .shadow(color: accent.opacity(0.45), radius: 8, y: 3)
            VStack(alignment: .leading, spacing: 3) {
                Text(czTitle).font(.system(size: 15.5, weight: .bold)).foregroundStyle(.white)
                Text(czSubtitle).font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.62))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)   // 콘텐츠 ↔ 테두리(아이콘 왼쪽 여백)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(convertActive
                      ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x0EA5E9).opacity(0.28), Color(hex: 0x8B5CF6).opacity(0.28)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                      : AnyShapeStyle(Color.white.opacity(0.05)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(convertActive ? AnyShapeStyle(grad) : AnyShapeStyle(Color.white.opacity(0.20)),
                              style: StrokeStyle(lineWidth: convertActive ? 2 : 1.5,
                                                 dash: convertActive ? [] : [5, 4]))
        )
        .scaleEffect(convertActive ? 1.015 : 1)
        .shadow(color: convertActive ? accent.opacity(0.38) : .clear, radius: 16)
        .padding(.horizontal, 14)   // 카드 ↔ 패널 가장자리
        .padding(.top, 14).padding(.bottom, 8)
        .frame(height: Self.convertZoneHeight)
        .animation(.spring(response: 0.3, dampingFraction: 0.74), value: convertActive)
        .animation(.easeOut(duration: 0.2), value: dropState.convertFlash)
        .animation(.easeOut(duration: 0.2), value: dropState.rejectFlash)
    }

    // MARK: 하단 — 보관 트레이

    private var holdingHeader: some View {
        HStack(spacing: 8) {
            Text("파일 보관").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
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
    }

    private var holdingBody: some View {
        ZStack {
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
                    newIDs: store.newItemIDs,
                    onRemove: { store.remove($0) },
                    onMovedOut: { store.remove($0) },
                    onDragSession: onDragSession
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(holdActive ? Color.white.opacity(0.06) : Color.clear)
                .padding(6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(holdActive ? accent.opacity(0.85) : Color.clear, lineWidth: holdActive ? 2 : 0)
                .padding(6)
        )
        .animation(.easeOut(duration: 0.18), value: holdActive)
    }
}
