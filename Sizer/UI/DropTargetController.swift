import AppKit
import SwiftUI

/// 화면 위에 떠 있는 콤팩트 드롭 타겟 패널. 항상 위, 모든 Space, 드래그로 이동, 위치 기억.
@MainActor
final class DropTargetController {
    private var panel: NSPanel?
    private let coordinator: WatchCoordinator
    private let size = NSSize(width: 300, height: 120)
    private let frameKey = "dropTargetOrigin"

    init(coordinator: WatchCoordinator) {
        self.coordinator = coordinator
    }

    private var screenObserver: NSObjectProtocol?

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() { isVisible ? hide() : show() }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        positionPanel(panel)
        panel.orderFrontRegardless()
        observeScreenChanges()
    }

    private func observeScreenChanges() {
        guard screenObserver == nil else { return }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.keepOnScreen() }
        }
    }

    private func keepOnScreen() {
        guard let panel, panel.isVisible else { return }
        let clamped = ScreenUtils.clampedOnScreen(panel.frame)
        if clamped != panel.frame { panel.setFrame(clamped, display: true, animate: true) }
    }

    func hide() {
        if let panel { saveOrigin(panel.frame.origin) }
        panel?.orderOut(nil)
    }

    // MARK: 패널 구성

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let host = NSHostingView(rootView: DropTargetView(coordinator: coordinator))
        host.frame = NSRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]
        host.appearance = NSAppearance(named: .darkAqua)   // HUD 다크 글래스 + 흰 텍스트
        panel.contentView = host
        return panel
    }

    private func positionPanel(_ panel: NSPanel) {
        var frame = panel.frame
        frame.size = size
        if let origin = savedOrigin() {
            frame.origin = origin
        } else if let screen = NSScreen.main {
            // 기본 위치: 우하단 여백
            let vf = screen.visibleFrame
            frame.origin = NSPoint(x: vf.maxX - size.width - 24, y: vf.minY + 24)
        }
        panel.setFrame(ScreenUtils.clampedOnScreen(frame), display: false)   // 오프스크린 방지
    }

    // MARK: 위치 저장

    private func saveOrigin(_ origin: NSPoint) {
        UserDefaults.standard.set([origin.x, origin.y], forKey: frameKey)
    }

    private func savedOrigin() -> NSPoint? {
        guard let arr = UserDefaults.standard.array(forKey: frameKey) as? [Double], arr.count == 2 else { return nil }
        return NSPoint(x: arr[0], y: arr[1])
    }
}
