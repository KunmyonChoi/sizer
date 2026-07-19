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

        // 디스플레이 구성이 바뀌면(모니터 변경 등) 화면 밖으로 나간 패널을 다시 안으로.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.ensureOnScreen() }
        }
        return panel
    }

    private func positionPanel(_ panel: NSPanel) {
        if let origin = savedOrigin(), Self.isVisible(origin: origin, size: size) {
            panel.setFrameOrigin(origin)
        } else {
            panel.setFrameOrigin(defaultOrigin())
        }
    }

    private func ensureOnScreen() {
        guard let panel, panel.isVisible else { return }
        if !Self.isVisible(origin: panel.frame.origin, size: panel.frame.size) {
            panel.setFrameOrigin(defaultOrigin())
        }
    }

    private func defaultOrigin() -> NSPoint {
        guard let vf = NSScreen.main?.visibleFrame else { return .zero }
        return NSPoint(x: vf.maxX - size.width - 24, y: vf.minY + 24)
    }

    /// 프레임이 어떤 화면과도 충분히(가로·세로 40pt 이상) 겹치지 않으면 보이지 않는 것으로 본다.
    static func isVisible(origin: NSPoint, size: NSSize) -> Bool {
        let frame = NSRect(origin: origin, size: size)
        for screen in NSScreen.screens {
            let inter = screen.visibleFrame.intersection(frame)
            if inter.width >= 40, inter.height >= 40 { return true }
        }
        return false
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
