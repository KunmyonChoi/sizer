import AppKit
import SwiftUI

/// 설정 창을 직접 소유·표시한다(agent 앱에서 SwiftUI Settings 씬이 앞으로 안 나오는 문제 회피).
/// 창이 열려 있는 동안만 .regular 정책으로 전환해 정상 창처럼 포커스되고, 닫으면 .accessory로 복귀.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let rootView: AnyView

    init(rootView: AnyView) {
        self.rootView = rootView
        super.init()
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: rootView)
            let win = NSWindow(contentViewController: hosting)
            win.title = "Sizer 설정"
            win.styleMask = [.titled, .closable, .miniaturizable]
            win.isReleasedWhenClosed = false
            win.setContentSize(NSSize(width: 480, height: 420))
            win.delegate = self
            window = win
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        centerOnActiveScreen()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    /// 현재 활성 화면 중앙에 배치(win.center()가 레이아웃 전 오프스크린에 두는 문제 회피).
    private func centerOnActiveScreen() {
        guard let win = window else { return }
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { win.center(); return }
        let size = win.frame.size
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2
        )
        win.setFrameOrigin(origin)
    }

    func windowWillClose(_ notification: Notification) {
        // Dock 아이콘 없는 메뉴바 전용 상태로 복귀
        NSApp.setActivationPolicy(.accessory)
    }
}
