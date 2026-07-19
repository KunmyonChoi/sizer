import AppKit
import SwiftUI

/// 파일 셸프 — 화면 왼쪽 가장자리에 접혀 있다가, 파일 드래그가 접근하거나 마우스를 대면 펼쳐진다.
/// 접힘 상태에서는 마우스가 있는 화면의 왼쪽 가장자리를 따라 이동한다.
@MainActor
final class ShelfController {
    let store = ShelfStore()

    private var panel: NSPanel?
    private var hostingView: NSHostingView<ShelfView>?
    private let handleW = ShelfView.handleWidth
    private let expandedW = ShelfView.expandedWidth
    private let height = ShelfView.height

    private var expanded = false
    private var isDraggingOut = false
    private var dockedScreen: NSScreen?

    private var pollTimer: Timer?
    private var screenObserver: NSObjectProtocol?
    private var expandWork: DispatchWorkItem?
    private var collapseWork: DispatchWorkItem?

    private let vFracKey = "shelfVerticalFraction"   // 0(하단)~1(상단)

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() { isVisible ? hide() : show() }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        dockPanel(to: ScreenUtils.screenWithMouse(), expanded: false)
        panel.orderFrontRegardless()
        startPolling()
        observeScreenChanges()
    }

    func hide() {
        stopPolling()
        panel?.orderOut(nil)
    }

    // MARK: 패널

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: handleW, height: height),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false     // 엣지 고정
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let host = NSHostingView(rootView: ShelfView(store: store, onDragSession: { [weak self] active in
            self?.setDraggingOut(active)
        }))
        host.frame = NSRect(x: 0, y: 0, width: expandedW, height: height)   // 항상 펼친 크기
        host.appearance = NSAppearance(named: .darkAqua)
        hostingView = host

        let catcher = ShelfDragCatchView(frame: NSRect(x: 0, y: 0, width: handleW, height: height))
        catcher.autoresizingMask = [.width, .height]
        catcher.addSubview(host)
        catcher.onDragEntered = { [weak self] in self?.expand() }
        catcher.onDragExited = { [weak self] in self?.scheduleCollapse() }
        catcher.onDropURLs = { [weak self] urls in
            self?.store.add(urls)
            self?.scheduleCollapse(delay: 0.8)
        }
        panel.contentView = catcher
        return panel
    }

    private func dockPanel(to screen: NSScreen?, expanded: Bool) {
        guard let panel, let screen = screen ?? NSScreen.main else { return }
        dockedScreen = screen
        self.expanded = expanded
        let width = expanded ? expandedW : handleW
        panel.setFrame(frame(on: screen, width: width), display: true)
    }

    private func frame(on screen: NSScreen, width: CGFloat) -> NSRect {
        let vf = screen.visibleFrame
        let frac = UserDefaults.standard.object(forKey: vFracKey) as? Double ?? 0.5
        let usable = max(0, vf.height - height)
        let y = vf.minY + usable * CGFloat(frac)
        return NSRect(x: vf.minX, y: y, width: width, height: height)
    }

    private func setPanelWidth(_ width: CGFloat, animate: Bool) {
        guard let panel, let screen = dockedScreen else { return }
        let target = frame(on: screen, width: width)
        if animate {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(target, display: true)
            }
        } else {
            panel.setFrame(target, display: true)
        }
    }

    // MARK: 펼침/접힘

    private func expand() {
        collapseWork?.cancel(); collapseWork = nil
        expandWork?.cancel(); expandWork = nil
        guard !expanded else { return }
        expanded = true
        setPanelWidth(expandedW, animate: true)
    }

    private func scheduleCollapse(delay: TimeInterval = 0.4) {
        collapseWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.collapseIfIdle() }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func collapseIfIdle() {
        guard expanded, !isDraggingOut, let panel else { return }
        // 커서가 아직 패널 위(여유 8px)면 유지
        if panel.frame.insetBy(dx: -8, dy: -8).contains(NSEvent.mouseLocation) {
            scheduleCollapse(); return
        }
        expanded = false
        setPanelWidth(handleW, animate: true)
    }

    private func setDraggingOut(_ active: Bool) {
        isDraggingOut = active
        if active { collapseWork?.cancel() } else { scheduleCollapse() }
    }

    // MARK: 마우스 폴링(호버 펼침 + 화면 따라가기)

    private func startPolling() {
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(timeInterval: 0.08, target: self, selector: #selector(poll), userInfo: nil, repeats: true)
        RunLoop.main.add(pollTimer!, forMode: .common)
    }

    private func stopPolling() {
        pollTimer?.invalidate(); pollTimer = nil
        expandWork?.cancel(); collapseWork?.cancel()
    }

    @objc private func poll() {
        guard let panel, panel.isVisible else { return }
        let mouse = NSEvent.mouseLocation

        // 접힘 상태에서 다른 화면으로 이동하면 그 화면 가장자리로 재도킹
        if !expanded, !isDraggingOut, let mScreen = ScreenUtils.screenWithMouse(),
           mScreen.frame != dockedScreen?.frame {
            dockPanel(to: mScreen, expanded: false)
            return
        }
        guard let screen = dockedScreen else { return }
        let vf = screen.visibleFrame

        if !expanded {
            // 왼쪽 가장자리 탭 밴드 안에 dwell → 펼침
            let inBand = mouse.x <= vf.minX + handleW + 4
                && mouse.y >= panel.frame.minY && mouse.y <= panel.frame.maxY
                && NSMouseInRect(mouse, screen.frame, false)
            if inBand {
                if expandWork == nil {
                    let work = DispatchWorkItem { [weak self] in self?.expandWork = nil; self?.expand() }
                    expandWork = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
                }
            } else {
                expandWork?.cancel(); expandWork = nil
            }
        } else if !isDraggingOut {
            // 펼침 상태: 커서가 패널을 벗어나면 접힘 예약
            if panel.frame.insetBy(dx: -10, dy: -10).contains(mouse) {
                collapseWork?.cancel(); collapseWork = nil
            } else if collapseWork == nil {
                scheduleCollapse()
            }
        }
    }

    // MARK: 화면 변경

    private func observeScreenChanges() {
        guard screenObserver == nil else { return }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reDockAfterScreenChange() }
        }
    }

    private func reDockAfterScreenChange() {
        guard let panel, panel.isVisible else { return }
        let stillThere = dockedScreen.flatMap { docked in
            NSScreen.screens.contains { $0.frame == docked.frame } ? docked : nil
        }
        let screen = stillThere ?? ScreenUtils.screenWithMouse() ?? NSScreen.main
        dockPanel(to: screen, expanded: expanded)
        // 재도킹 후에도 혹시 화면 밖이면 클램프
        panel.setFrame(ScreenUtils.clampedOnScreen(panel.frame), display: true)
    }
}

/// 접힌 탭/펼친 트레이 위로 오는 파일 드래그를 받는 뷰(펼침 트리거 + 드롭 수집).
final class ShelfDragCatchView: NSView {
    var onDropURLs: (([URL]) -> Void)?
    var onDragEntered: (() -> Void)?
    var onDragExited: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onDragEntered?()
        return .copy
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { onDragExited?() }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let objs = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        onDropURLs?(objs.filter { $0.isFileURL })
        return true
    }
}
