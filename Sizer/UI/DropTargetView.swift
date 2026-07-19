import SwiftUI
import UniformTypeIdentifiers

/// 콤팩트 플로팅 드롭 타겟(필). 드래그 호버 시 확대·글로우, 드롭 성공 시 카운트 플래시.
struct DropTargetView: View {
    @ObservedObject var coordinator: WatchCoordinator
    @State private var targeted = false
    @State private var successCount: Int?
    @State private var flashTask: Task<Void, Never>?

    init(coordinator: WatchCoordinator, previewTargeted: Bool = false) {
        self.coordinator = coordinator
        _targeted = State(initialValue: previewTargeted)
    }

    private let grad = LinearGradient(
        colors: [Color(hex: 0x0EA5E9), Color(hex: 0x6366F1), Color(hex: 0x8B5CF6)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    private var accent: Color { Color(hex: 0x6366F1) }

    var body: some View {
        HStack(spacing: 13) {
            iconBadge
            VStack(alignment: .leading, spacing: 2) {
                Text(primaryText)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.primary)
                Text(secondaryText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 17)
        .frame(width: targeted ? 268 : 224, height: targeted ? 74 : 60)
        .background {
            ZStack {
                VisualEffectBackground()          // 실제 backdrop 블러(글래스)
                Color.black.opacity(0.20)         // 어떤 배경에서도 가독성 확보
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(borderStyle, lineWidth: targeted ? 2.5 : 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 16, y: 8)
        .shadow(color: targeted ? accent.opacity(0.55) : .clear, radius: 26)
        .scaleEffect(targeted ? 1.05 : 1)
        .animation(.spring(response: 0.32, dampingFraction: 0.72), value: targeted)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: successCount)
        .contentShape(RoundedRectangle(cornerRadius: 20))
        .onDrop(of: [.fileURL], isTargeted: $targeted.animation()) { providers in
            handleDrop(providers)
        }
        .frame(width: 300, height: 120)   // 패널 크기에 맞춰 중앙 배치(그림자·확대 여백)
    }

    private var iconBadge: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(successCount != nil ? AnyShapeStyle(Color.green) : AnyShapeStyle(grad))
            .frame(width: 40, height: 40)
            .overlay(
                Image(systemName: successCount != nil ? "checkmark" : "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
            )
            .shadow(color: accent.opacity(0.45), radius: 8, y: 3)
    }

    private var primaryText: String {
        if let n = successCount { return "\(n)개 추가됨" }
        return targeted ? "여기에 놓기" : "드롭하여 변환"
    }

    private var secondaryText: String {
        if successCount != nil { return "변환을 시작합니다" }
        if targeted { return "영상·이미지 파일" }
        switch coordinator.status {
        case .converting: return "변환 중…"
        case .paused: return "일시정지됨"
        default: return "감시 중 · Finder에서 드롭"
        }
    }

    private var borderStyle: AnyShapeStyle {
        if successCount != nil { return AnyShapeStyle(Color.green.opacity(0.85)) }
        return targeted ? AnyShapeStyle(grad) : AnyShapeStyle(Color.primary.opacity(0.10))
    }

    // MARK: 드롭 처리

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []
        for provider in providers where provider.canLoadObject(ofClass: URL.self) {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url, url.isFileURL {
                    lock.lock(); urls.append(url); lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            let n = coordinator.ingest(urls: urls)
            if n > 0 { flashSuccess(n) }
        }
        return true
    }

    private func flashSuccess(_ n: Int) {
        flashTask?.cancel()
        successCount = n
        flashTask = Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            if !Task.isCancelled { successCount = nil }
        }
    }
}

/// 패널 backdrop 블러(HUD 글래스).
private struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

private extension Color {
    init(hex: UInt) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255
        )
    }
}
