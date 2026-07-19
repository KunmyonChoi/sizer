import AppKit
import SwiftUI

/// 파일 셸프 플로팅 패널. 드롭 타겟과 동일한 패턴(항상 위·이동·위치 기억).
@MainActor
final class ShelfController {
    private var panel: NSPanel?
    let store = ShelfStore()
    private let size = NSSize(width: 472, height: 210)
    private let frameKey = "shelfOrigin"

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() { isVisible ? hide() : show() }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        positionPanel(panel)
        panel.orderFrontRegardless()
    }

    func hide() {
        if let panel { saveOrigin(panel.frame.origin) }
        panel?.orderOut(nil)
    }

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

        let host = NSHostingView(rootView: ShelfView(store: store))
        host.frame = NSRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]
        host.appearance = NSAppearance(named: .darkAqua)
        panel.contentView = host
        return panel
    }

    private func positionPanel(_ panel: NSPanel) {
        if let origin = savedOrigin() {
            panel.setFrameOrigin(origin)
        } else if let screen = NSScreen.main {
            let vf = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: vf.midX - size.width / 2, y: vf.minY + 40))
        } else {
            panel.center()
        }
    }

    private func saveOrigin(_ origin: NSPoint) {
        UserDefaults.standard.set([origin.x, origin.y], forKey: frameKey)
    }

    private func savedOrigin() -> NSPoint? {
        guard let arr = UserDefaults.standard.array(forKey: frameKey) as? [Double], arr.count == 2 else { return nil }
        return NSPoint(x: arr[0], y: arr[1])
    }
}
