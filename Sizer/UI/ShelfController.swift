import AppKit
import SwiftUI
import Combine

/// 셸프의 접힘/펼침 상태 + 드래그 세션 표시(뷰 ↔ 컨트롤러 공유).
@MainActor
final class ShelfPresentation: ObservableObject {
    @Published var expanded = false
    @Published var dragging = false   // 카드를 Finder로 드래그하는 중(접힘 방지)
}

/// 파일 셸프 플로팅 패널. 평상시 좌하단에 최소화, 호버/드래그 시 펼침. 항상 위·이동·위치 기억.
@MainActor
final class ShelfController {
    private var panel: NSPanel?
    let store = ShelfStore()
    let presentation = ShelfPresentation()

    private let collapsedSize = NSSize(width: 168, height: 52)
    private let expandedSize = NSSize(width: 472, height: 210)
    private let frameKey = "shelfOrigin"

    private var cancellables: Set<AnyCancellable> = []
    private var screenObserver: NSObjectProtocol?
    private var moveObserver: NSObjectProtocol?

    init() {
        presentation.$expanded
            .removeDuplicates()
            .sink { [weak self] expanded in self?.applyExpanded(expanded) }
            .store(in: &cancellables)

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.revalidatePosition() }
        }
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() { isVisible ? hide() : show() }

    func show() {
        store.pruneMissing()
        let panel = self.panel ?? makePanel()
        self.panel = panel
        presentation.expanded = false
        let size = collapsedSize
        let origin = PanelPlacement.visibleOrigin(size: size, saved: savedOrigin(), defaultCorner: defaultCorner)
        panel.setFrame(NSRect(origin: origin, size: size), display: false)
        panel.orderFrontRegardless()
    }

    func hide() {
        if let panel { saveOrigin(panel.frame.origin) }
        panel?.orderOut(nil)
    }

    // MARK: 접힘/펼침

    private func applyExpanded(_ expanded: Bool) {
        guard let panel, panel.isVisible else { return }
        if expanded { store.pruneMissing() }
        let origin = panel.frame.origin                  // 좌하단 앵커 유지
        let target = expanded ? expandedSize : collapsedSize
        let vf = PanelPlacement.screenVisibleFrame(containing: origin)
        let clamped = PanelPlacement.clamp(origin: origin, size: target, into: vf)
        panel.setFrame(NSRect(origin: clamped, size: target), display: true, animate: true)
    }

    private func revalidatePosition() {
        guard let panel, panel.isVisible else { return }
        panel.setFrameOrigin(PanelPlacement.visibleOrigin(
            size: panel.frame.size, saved: panel.frame.origin, defaultCorner: defaultCorner
        ))
    }

    private func defaultCorner(_ vf: NSRect) -> NSPoint {
        NSPoint(x: vf.minX + 24, y: vf.minY + 24)   // 좌하단
    }

    // MARK: 패널

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: collapsedSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let host = NSHostingView(rootView: ShelfView(store: store, presentation: presentation))
        host.frame = NSRect(origin: .zero, size: collapsedSize)
        host.autoresizingMask = [.width, .height]
        host.appearance = NSAppearance(named: .darkAqua)
        panel.contentView = host

        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { [weak self, weak panel] _ in
            guard let panel else { return }
            Task { @MainActor in self?.saveOrigin(panel.frame.origin) }
        }
        return panel
    }

    private func saveOrigin(_ origin: NSPoint) {
        UserDefaults.standard.set([origin.x, origin.y], forKey: frameKey)
    }

    private func savedOrigin() -> NSPoint? {
        guard let arr = UserDefaults.standard.array(forKey: frameKey) as? [Double], arr.count == 2 else { return nil }
        return NSPoint(x: arr[0], y: arr[1])
    }
}
