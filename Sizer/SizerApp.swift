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

    /// 다른 Sizer 인스턴스가 이미 실행 중이면 false(호출자가 종료). 테스트 실행 중에는 가드하지 않는다.
    ///
    /// 인스턴스가 둘이면 각자 드롭 폴더를 감시해 **같은 파일을 동시에 변환**하고,
    /// 같은 출력 경로로 인코딩해 결과물이 스트림 없는 깨진 파일이 된다(실제 사고 사례).
    static func ensureSingleInstance() -> Bool {
        // XCTest 호스트에서는 예외 — 설치본이 떠 있어도 테스트가 죽지 않도록.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return true }
        guard let bundleID = Bundle.main.bundleIdentifier else { return true }
        let mine = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != mine && !$0.isTerminated }
        guard let existing = others.first else { return true }

        AppLogger.warn("이미 실행 중인 Sizer가 있어 이 인스턴스를 종료합니다(기존 PID \(existing.processIdentifier)).")
        NSApp.setActivationPolicy(.regular)      // 경고창이 보이도록 잠시 일반 앱으로
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Sizer가 이미 실행 중입니다"
        alert.informativeText = "두 개를 동시에 실행하면 같은 파일을 중복 변환해 결과물이 손상될 수 있습니다. 이 인스턴스는 종료합니다."
        alert.addButton(withTitle: "확인")
        alert.runModal()
        return false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 중복 실행 방지: 인스턴스가 둘이면 같은 드롭 폴더를 동시에 처리해 결과물이 깨질 수 있다.
        guard Self.ensureSingleInstance() else {
            NSApp.terminate(nil)
            return
        }

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
