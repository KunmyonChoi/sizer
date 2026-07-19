import AppKit
import SwiftUI

/// 파일 셸프 플로팅 패널 — 평소엔 화면 가장자리에 접힌 탭, 호버/드래그 시 트레이로 펼침.
@MainActor
final class ShelfController {
    let store = ShelfStore()

    private var panel: NSPanel?
    private var host: NSHostingView<ShelfPanelView>?
    private var collapsed = true
    private var hoverActive = false
    private var dragActive = false
    private var collapseTask: DispatchWorkItem?
    private var hoverExpandTask: DispatchWorkItem?

    private let collapsedWidth: CGFloat = 26
    private let collapsedHeight: CGFloat = 172
    private let expandedWidth: CGFloat = 468
    private let expandedHeight: CGFloat = 206

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() { isVisible ? hide() : show() }

    func show() {
        collapsed = true
        hoverActive = false
        dragActive = false
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.setFrame(anchorFrame(collapsed: true), display: true)
        updateRoot()
        panel.orderFrontRegardless()
    }

    func hide() {
        cancelTasks()
        panel?.orderOut(nil)
    }

    // MARK: 패널

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: anchorFrame(collapsed: true),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false   // 가장자리 고정
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let host = NSHostingView(rootView: makeRoot())
        host.appearance = NSAppearance(named: .darkAqua)
        panel.contentView = host
        self.host = host

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reanchor() }
        }
        return panel
    }

    private func makeRoot() -> ShelfPanelView {
        ShelfPanelView(
            store: store,
            collapsed: collapsed,
            edgeIsLeft: currentEdgeIsLeft(),
            onHoverChange: { [weak self] in self?.hoverChanged($0) },
            onDragTargetChange: { [weak self] in self?.dragChanged($0) }
        )
    }

    private func updateRoot() { host?.rootView = makeRoot() }

    // MARK: 펼침/접힘

    private func hoverChanged(_ hovering: Bool) {
        hoverActive = hovering
        hoverExpandTask?.cancel()
        if hovering {
            let task = DispatchWorkItem { [weak self] in
                guard let self, self.hoverActive else { return }
                self.expand()
            }
            hoverExpandTask = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: task)  // 오작동 방지 지연
        } else {
            scheduleCollapse()
        }
    }

    private func dragChanged(_ targeted: Bool) {
        dragActive = targeted
        if targeted { expand() } else { scheduleCollapse() }
    }

    private func expand() {
        collapseTask?.cancel()
        guard collapsed else { return }
        animate(collapsed: false)
    }

    private func scheduleCollapse() {
        collapseTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            guard let self, !self.hoverActive, !self.dragActive, !self.collapsed else { return }
            self.animate(collapsed: true)
        }
        collapseTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: task)
    }

    private func animate(collapsed: Bool) {
        self.collapsed = collapsed
        updateRoot()
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.26
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(anchorFrame(collapsed: collapsed), display: true)
        }
    }

    private func cancelTasks() {
        collapseTask?.cancel(); hoverExpandTask?.cancel()
    }

    // MARK: 가장자리 앵커링 (왼쪽 기본, 왼쪽에 Dock 있으면 오른쪽)

    private func anchorScreen() -> NSScreen? {
        if let screen = panel?.screen { return screen }
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }

    private func currentEdgeIsLeft() -> Bool {
        guard let screen = anchorScreen() else { return true }
        let dockOnLeft = screen.visibleFrame.minX - screen.frame.minX > 1
        return !dockOnLeft
    }

    private func anchorFrame(collapsed: Bool) -> NSRect {
        let width = collapsed ? collapsedWidth : expandedWidth
        let height = collapsed ? collapsedHeight : expandedHeight
        guard let vf = anchorScreen()?.visibleFrame else {
            return NSRect(x: 0, y: 0, width: width, height: height)
        }
        let y = vf.midY - height / 2
        let x = currentEdgeIsLeft() ? vf.minX : vf.maxX - width
        return NSRect(x: x, y: y, width: width, height: height)
    }

    private func reanchor() {
        guard let panel, panel.isVisible else { return }
        updateRoot()   // 엣지가 바뀌었을 수 있으니 모서리 방향 갱신
        panel.setFrame(anchorFrame(collapsed: collapsed), display: true)
    }
}
