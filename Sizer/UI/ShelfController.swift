import AppKit
import SwiftUI

/// 통합 파일 셸프 — 화면 왼쪽 가장자리에 접혀 있다가, 파일 드래그가 접근하거나 마우스를 대면 펼쳐진다.
/// 펼침 상태에서 상단은 변환 드롭존, 하단은 보관 트레이. 드롭 지점(존)에 따라 변환/보관으로 분기한다.
/// 접힘 상태에서는 마우스가 있는 화면의 왼쪽 가장자리를 따라 이동한다.
@MainActor
final class ShelfController {
    let store = ShelfStore()
    let dropState = ShelfDropState()

    private let coordinator: WatchCoordinator
    private var panel: NSPanel?
    private var hostingView: NSHostingView<ShelfView>?
    private let handleW = ShelfView.handleWidth
    private let expandedW = ShelfView.expandedWidth

    private var expanded = false
    private var isDraggingOut = false
    private var dockedScreen: NSScreen?

    private var pollTimer: Timer?
    private var screenObserver: NSObjectProtocol?
    private var expandWork: DispatchWorkItem?
    private var collapseWork: DispatchWorkItem?

    private let vFracKey = "shelfVerticalFraction"   // 0(하단)~1(상단)

    init(coordinator: WatchCoordinator) {
        self.coordinator = coordinator
    }

    /// 통합 모드일 때만 상단 변환 드롭존을 노출한다.
    private var showConvertZone: Bool { coordinator.settings.integratedDrop }
    /// 통합 여부에 따른 패널 높이(ShelfView와 일치).
    private var height: CGFloat { ShelfView.panelHeight(showConvertZone: showConvertZone) }

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

    /// 통합 모드 전환 등으로 뷰를 새 설정으로 다시 만들어야 할 때: 다음 show 시 재생성(보관 내용은 유지).
    func rebuild() {
        let wasVisible = isVisible
        hide()
        panel?.orderOut(nil)
        panel = nil
        hostingView = nil
        expanded = false
        dropState.setZone(nil)
        if wasVisible { show() }
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

        let host = NSHostingView(rootView: ShelfView(
            store: store, dropState: dropState, showConvertZone: showConvertZone,
            onDragSession: { [weak self] active in self?.setDraggingOut(active) }
        ))
        host.frame = NSRect(x: 0, y: 0, width: expandedW, height: height)   // 항상 펼친 크기
        host.appearance = NSAppearance(named: .darkAqua)
        hostingView = host

        let catcher = ShelfDragCatchView(frame: NSRect(x: 0, y: 0, width: handleW, height: height))
        catcher.autoresizingMask = [.width, .height]
        catcher.addSubview(host)
        catcher.onExpand = { [weak self] in self?.expand() }
        catcher.onDragActivity = { [weak self] urls, p in self?.evaluateDrag(urls, at: p) ?? true }
        catcher.onDragExited = { [weak self] in
            self?.dropState.setZone(nil)
            self?.scheduleCollapse()
        }
        catcher.onDropAt = { [weak self] urls, p in self?.handleDrop(urls, at: p) }
        panel.contentView = catcher
        return panel
    }

    // MARK: 드롭 라우팅(존 분기)

    private func resolveZone(_ p: NSPoint) -> ShelfDropZone {
        ShelfDropZone.at(p, panelHeight: height, handleWidth: handleW,
                         convertZoneHeight: ShelfView.convertZoneHeight,
                         integrated: showConvertZone, expanded: expanded)
    }

    /// 드래그 중 존/거부 상태를 갱신하고, 이 지점에서 드롭을 수용할지 반환(커서 표시 제어).
    /// 변환존 위인데 변환 가능한 파일이 하나도 없으면 거부(.none) → 놓기 불가 커서.
    private func evaluateDrag(_ urls: [URL], at p: NSPoint) -> Bool {
        switch resolveZone(p) {
        case .convert:
            let supported = DropIngest.supportedURLs(urls, imageEnabled: coordinator.settings.imageConversionEnabled)
            let acceptable = !supported.isEmpty
            dropState.setZone(.convert, reject: !acceptable)
            return acceptable
        case .hold:
            dropState.setZone(.hold, reject: false)   // 보관은 모든 파일 수용
            return true
        }
    }

    private func handleDrop(_ urls: [URL], at p: NSPoint) {
        dropState.setZone(nil)
        let files = urls.filter { $0.isFileURL }
        switch resolveZone(p) {
        case .convert:
            let n = coordinator.ingest(urls: files)   // 변환 큐로(구 드롭 타겟과 동일 경로)
            if n > 0 { dropState.flashConvert(n) } else { dropState.flashReject() }   // C2(방어)
            scheduleCollapse(delay: 1.4)
        case .hold:
            store.add(files)
            scheduleCollapse(delay: 0.8)
        }
    }

    // MARK: 배치

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
        dropState.setZone(nil)
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

/// 접힌 탭/펼친 트레이 위로 오는 파일 드래그를 받는 뷰(펼침 트리거 + 위치별 존 판정 + 수용 여부).
final class ShelfDragCatchView: NSView {
    var onExpand: (() -> Void)?
    var onDragActivity: (([URL], NSPoint) -> Bool)?   // 존/거부 갱신 + 수용 여부(true=.copy)
    var onDragExited: (() -> Void)?
    var onDropAt: (([URL], NSPoint) -> Void)?

    private var draggedURLs: [URL] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
    }

    /// 드래그 지점을 뷰 로컬 좌표(origin 좌하단)로 변환.
    private func localPoint(_ sender: NSDraggingInfo) -> NSPoint {
        convert(sender.draggingLocation, from: nil)
    }

    private func readURLs(_ sender: NSDraggingInfo) -> [URL] {
        (sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []).filter { $0.isFileURL }
    }

    private func operation(_ sender: NSDraggingInfo) -> NSDragOperation {
        let accepted = onDragActivity?(draggedURLs, localPoint(sender)) ?? true
        return accepted ? .copy : []   // []=none → 놓기 불가 커서
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggedURLs = readURLs(sender)
        onExpand?()
        return operation(sender)
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        operation(sender)
    }
    override func draggingExited(_ sender: NSDraggingInfo?) {
        draggedURLs = []
        onDragExited?()
    }
    // 수용 불가(.none) 지점에서 놓으면 이 메서드들이 호출되지 않아 드롭이 무시된다.
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = draggedURLs.isEmpty ? readURLs(sender) : draggedURLs
        onDropAt?(urls, localPoint(sender))
        draggedURLs = []
        return true
    }
}
