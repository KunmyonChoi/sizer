import SwiftUI
import AppKit
import Combine

@main
struct SizerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // 메뉴바/설정은 AppDelegate가 직접 관리. 최소 씬만 유지.
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private lazy var coordinator = WatchCoordinator(settings: settings)

    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var cancellables: Set<AnyCancellable> = []

    private var spinTimer: Timer?
    private var spinAngle: CGFloat = 0

    private lazy var idleImage: NSImage? = symbolImage("arrow.down.right.and.arrow.up.left")
    private lazy var spinnerBase: NSImage? = symbolImage("arrow.triangle.2.circlepath")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)   // Dock 아이콘 없음(메뉴바 전용)

        // 상태바 아이템
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = idleImage
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(togglePopover(_:))
        }

        // 메뉴(팝오버)
        popover.behavior = .transient
        let hosting = NSHostingController(
            rootView: MenuBarView()
                .environmentObject(coordinator)
                .environmentObject(settings)
        )
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting

        // 상태 변화 → 아이콘 애니메이션
        coordinator.statusPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] status in self?.updateIcon(for: status) }
            .store(in: &cancellables)

        coordinator.start()
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    // MARK: 아이콘 애니메이션

    private func updateIcon(for status: WatchStatus) {
        if case .converting = status {
            startSpin()
        } else {
            stopSpin()
        }
    }

    private func startSpin() {
        guard spinTimer == nil else { return }
        // 타깃-액션 방식(메인 스레드 호출) — Sendable 클로저 격리 경고 회피.
        let timer = Timer(timeInterval: 0.05, target: self, selector: #selector(spinTick), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        spinTimer = timer
    }

    @objc private func spinTick() {
        spinAngle -= .pi / 15   // 시계방향
        statusItem.button?.image = rotated(spinnerBase, by: spinAngle)
    }

    private func stopSpin() {
        spinTimer?.invalidate()
        spinTimer = nil
        spinAngle = 0
        statusItem.button?.image = idleImage
    }

    // MARK: 이미지 헬퍼

    private func symbolImage(_ name: String) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        image?.isTemplate = true
        return image
    }

    /// 이미지를 중심 기준으로 회전한 새 이미지(정사각 캔버스로 클리핑 방지).
    private func rotated(_ image: NSImage?, by angle: CGFloat) -> NSImage? {
        guard let image else { return nil }
        let size = image.size
        let dim = max(size.width, size.height)
        let canvas = NSSize(width: dim, height: dim)

        let result = NSImage(size: canvas)
        result.lockFocus()
        let transform = NSAffineTransform()
        transform.translateX(by: dim / 2, yBy: dim / 2)
        transform.rotate(byRadians: angle)
        transform.translateX(by: -dim / 2, yBy: -dim / 2)
        transform.concat()
        image.draw(
            at: NSPoint(x: (dim - size.width) / 2, y: (dim - size.height) / 2),
            from: NSRect(origin: .zero, size: size),
            operation: .sourceOver,
            fraction: 1.0
        )
        result.unlockFocus()
        result.isTemplate = true
        return result
    }
}
