import AppKit
import SwiftUI
import Combine

/// 셸프의 접힘/펼침 상태 + 드래그 세션 표시(뷰 ↔ 컨트롤러 공유).
@MainActor
final class ShelfPresentation: ObservableObject {
    @Published var expanded = false
    @Published var dragging = false   // 카드를 Finder로 드래그하는 중(접힘 방지)
}

/// 파일 셸프 플로팅 패널. 평상시 정사각형으로 최소화, 호버/드래그 시 모서리 기준으로 펼침.
/// 항상 위, 드래그 시 화면 모서리에 마그넷 스냅, 위치 기억.
@MainActor
final class ShelfController {
    private var panel: NSPanel?
    let store = ShelfStore()
    let presentation = ShelfPresentation()

    private let collapsedSize = NSSize(width: 56, height: 56)
    private let expandedSize = NSSize(width: 472, height: 210)
    private let frameKey = "shelfOrigin"

    // 현재 앵커 모서리(최소화 위치 기준). 이 모서리를 고정하고 안쪽으로 펼친다.
    private var anchorLeft = true
    private var anchorBottom = true
    private var isProgrammaticMove = false
    private var snapTask: Task<Void, Never>?

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
        let origin = PanelPlacement.visibleOrigin(size: collapsedSize, saved: savedOrigin(), defaultCorner: defaultCorner)
        setFramePanel(NSRect(origin: origin, size: collapsedSize), animate: false)
        updateAnchor(from: NSRect(origin: origin, size: collapsedSize))
        panel.orderFrontRegardless()
    }

    func hide() {
        if let panel { saveOrigin(panel.frame.origin) }
        panel?.orderOut(nil)
    }

    // MARK: 접힘/펼침 (모서리 기준)

    private func applyExpanded(_ expanded: Bool) {
        guard let panel, panel.isVisible else { return }
        if expanded { store.pruneMissing() }

        let current = panel.frame
        let vf = PanelPlacement.screenVisibleFrame(containing: current.origin)
        // 앵커 모서리의 고정 점(현재 프레임에서)
        let fixedX = anchorLeft ? current.minX : current.maxX
        let fixedY = anchorBottom ? current.minY : current.maxY
        let target = expanded ? expandedSize : collapsedSize
        var origin = NSPoint(
            x: anchorLeft ? fixedX : fixedX - target.width,
            y: anchorBottom ? fixedY : fixedY - target.height
        )
        origin = PanelPlacement.clamp(origin: origin, size: target, into: vf)
        setFramePanel(NSRect(origin: origin, size: target), animate: true)
    }

    private func revalidatePosition() {
        guard let panel, panel.isVisible else { return }
        let origin = PanelPlacement.visibleOrigin(size: panel.frame.size, saved: panel.frame.origin, defaultCorner: defaultCorner)
        setFramePanel(NSRect(origin: origin, size: panel.frame.size), animate: true)
        updateAnchor(from: NSRect(origin: origin, size: panel.frame.size))
    }

    private func defaultCorner(_ vf: NSRect) -> NSPoint {
        NSPoint(x: vf.minX + 24, y: vf.minY + 24)   // 좌하단(첫 실행)
    }

    // MARK: 앵커 & 마그넷 스냅

    private func updateAnchor(from frame: NSRect) {
        let vf = PanelPlacement.screenVisibleFrame(containing: frame.origin)
        anchorLeft = (frame.midX - vf.minX) <= (vf.maxX - frame.midX)
        anchorBottom = (frame.midY - vf.minY) <= (vf.maxY - frame.midY)
    }

    /// 드래그가 멈추면 가까운 화면 모서리에 스냅.
    private func scheduleSnap() {
        snapTask?.cancel()
        snapTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled, let panel, panel.isVisible, !presentation.expanded else { return }
            let snapped = snappedFrame(panel.frame)
            if snapped != panel.frame {
                setFramePanel(snapped, animate: true)
            }
            updateAnchor(from: snapped)
            saveOrigin(snapped.origin)
        }
    }

    private func snappedFrame(_ frame: NSRect) -> NSRect {
        let vf = PanelPlacement.screenVisibleFrame(containing: frame.origin)
        let margin: CGFloat = 16
        let threshold: CGFloat = 48
        var x = frame.origin.x
        var y = frame.origin.y
        if x - vf.minX < threshold { x = vf.minX + margin }
        else if vf.maxX - frame.maxX < threshold { x = vf.maxX - frame.width - margin }
        if y - vf.minY < threshold { y = vf.minY + margin }
        else if vf.maxY - frame.maxY < threshold { y = vf.maxY - frame.height - margin }
        return NSRect(x: x, y: y, width: frame.width, height: frame.height)
    }

    // MARK: 패널

    private func setFramePanel(_ frame: NSRect, animate: Bool) {
        guard let panel else { return }
        isProgrammaticMove = true
        panel.setFrame(frame, display: true, animate: animate)
        if animate {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) { [weak self] in self?.isProgrammaticMove = false }
        } else {
            isProgrammaticMove = false
        }
    }

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

        let hosting = NSHostingController(rootView: ShelfView(store: store, presentation: presentation))
        hosting.view.frame = NSRect(origin: .zero, size: collapsedSize)
        panel.contentViewController = hosting
        panel.appearance = NSAppearance(named: .darkAqua)

        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { [weak self, weak panel] _ in
            guard let self, let panel else { return }
            Task { @MainActor in
                guard !self.isProgrammaticMove else { return }   // 프로그램적 이동은 무시
                self.saveOrigin(panel.frame.origin)
                if !self.presentation.expanded {
                    self.updateAnchor(from: panel.frame)
                    self.scheduleSnap()   // 사용자 드래그 → 마그넷 스냅
                }
            }
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
