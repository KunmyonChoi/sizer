import AppKit
import SwiftUI
import Quartz
import QuickLookThumbnailing

/// 패널을 펼친 채로 붙잡아 두는 이유. 하나라도 남아 있으면 접지 않는다.
enum ShelfHold: Hashable {
    case dragOut       // Finder로 드래그-아웃 중
    case contextMenu   // 우클릭 메뉴 표시 중
    case preview       // 훑어보기(Quick Look) 표시 중
    case info          // 정보 보기 팝오버 표시 중
}

/// 셸프 항목(썸네일 카드) 영역. NSCollectionView로 다중 선택 + Finder로 드래그-아웃을 네이티브 처리.
/// Finder처럼 스페이스=훑어보기, 더블클릭=열기, 우클릭=메뉴, 호버=파일 정보를 제공한다.
struct ShelfCollectionView: NSViewRepresentable {
    var items: [ShelfItem]
    var newIDs: Set<UUID> = []            // 방금 얹힌 결과(NEW 배지)
    var onRemove: (ShelfItem) -> Void
    var onMovedOut: (ShelfItem) -> Void   // Finder가 이동(.move)해 원본이 사라진 항목
    var onHold: (ShelfHold, Bool) -> Void = { _, _ in }   // 펼침 유지 시작/종료

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let collectionView = ShelfNSCollectionView()
        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 100, height: 80)   // 가로형 카드
        layout.minimumInteritemSpacing = 8
        layout.minimumLineSpacing = 8
        layout.sectionInset = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        layout.scrollDirection = .vertical                 // 목업처럼 격자로 감김
        collectionView.collectionViewLayout = layout
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = true
        collectionView.allowsEmptySelection = true
        collectionView.backgroundColors = [.clear]
        collectionView.dataSource = context.coordinator
        collectionView.delegate = context.coordinator
        collectionView.actions = context.coordinator
        collectionView.register(ShelfCardItem.self, forItemWithIdentifier: ShelfCardItem.id)
        collectionView.setDraggingSourceOperationMask([.copy, .move, .generic], forLocal: false)
        collectionView.setDraggingSourceOperationMask([], forLocal: true)

        let scroll = NSScrollView()
        scroll.documentView = collectionView
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = true
        scroll.hasVerticalScroller = false
        scroll.scrollerStyle = .overlay
        context.coordinator.collectionView = collectionView
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.apply(items: items, newIDs: newIDs)
    }

    final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate,
                             NSMenuDelegate, NSPopoverDelegate {
        var parent: ShelfCollectionView
        private(set) var items: [ShelfItem]
        private var newIDs: Set<UUID>
        weak var collectionView: ShelfNSCollectionView?
        private var dragged: [ShelfItem] = []
        private var menuOpen = false
        private var previewing = false
        private lazy var preview: ShelfPreviewWindow = {
            let window = ShelfPreviewWindow()
            window.onClose = { [weak self] in self?.previewDidClose() }
            return window
        }()

        private var infoPopover: NSPopover?
        private var infoItemID: UUID?
        private var infoIsHover = false
        private var infoHold = false
        private var outsideClickMonitor: Any?

        init(_ parent: ShelfCollectionView) {
            self.parent = parent
            self.items = parent.items
            self.newIDs = parent.newIDs
        }

        var selectedItems: [ShelfItem] {
            (collectionView?.selectionIndexPaths ?? []).sorted().compactMap { $0.item < items.count ? items[$0.item] : nil }
        }

        /// 항목이 실제로 바뀐 경우에만 다시 그린다. SwiftUI는 드롭 존 하이라이트 같은 무관한 변화에도
        /// updateNSView를 부르므로, 매번 reloadData하면 선택(과 훑어보기 대상)이 풀린다. 선택은 항목 ID로 보존.
        func apply(items newItems: [ShelfItem], newIDs newNewIDs: Set<UUID>) {
            guard newItems != items || newNewIDs != newIDs else { return }
            let keep = Set(selectedItems.map(\.id))
            items = newItems
            newIDs = newNewIDs
            guard let collectionView else { return }
            dismissHoverInfo()   // 카드가 재사용되므로 호버 팝오버의 기준 뷰가 바뀔 수 있다
            collectionView.reloadData()
            collectionView.resetHover()
            collectionView.selectionIndexPaths = Set(items.indices
                .filter { keep.contains(items[$0].id) }
                .map { IndexPath(item: $0, section: 0) })
            refreshPreview()
        }

        func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
            items.count
        }

        func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
            let card = collectionView.makeItem(withIdentifier: ShelfCardItem.id, for: indexPath) as! ShelfCardItem
            let shelfItem = items[indexPath.item]
            card.configure(
                with: shelfItem, isNew: newIDs.contains(shelfItem.id),
                onRemove: { [weak self] in self?.parent.onRemove(shelfItem) },
                onHoverInfo: { [weak self] in self?.showHoverInfo(for: shelfItem) },
                onHoverEnd: { [weak self] in self?.endHoverInfo(for: shelfItem) }
            )
            return card
        }

        func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
            refreshPreview()
        }

        func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
            refreshPreview()
        }

        // MARK: 드래그 아웃

        func collectionView(_ collectionView: NSCollectionView, canDragItemsAt indexPaths: Set<IndexPath>, with event: NSEvent) -> Bool {
            true
        }

        func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
            guard indexPath.item < items.count else { return nil }
            return items[indexPath.item].url as NSURL
        }

        func collectionView(_ collectionView: NSCollectionView, draggingSession session: NSDraggingSession,
                            willBeginAt screenPoint: NSPoint, forItemsAt indexPaths: Set<IndexPath>) {
            dismissHoverInfo()
            dragged = indexPaths.sorted().compactMap { $0.item < items.count ? items[$0.item] : nil }
            parent.onHold(.dragOut, true)
        }

        func collectionView(_ collectionView: NSCollectionView, draggingSession session: NSDraggingSession,
                            endedAt screenPoint: NSPoint, dragOperation operation: NSDragOperation) {
            if operation.contains(.move) {
                dragged.forEach { parent.onMovedOut($0) }
            }
            dragged = []
            parent.onHold(.dragOut, false)
        }

        // MARK: 항목 동작 — 열기 · Finder에서 보기 · 경로 이름 복사

        /// 더블클릭: 클릭한 항목이 선택에 포함돼 있으면 선택 전체를, 아니면 그 항목만 기본 앱으로 연다(Finder와 동일).
        func open(at indexPath: IndexPath) {
            guard indexPath.item < items.count else { return }
            let clicked = items[indexPath.item]
            let selection = selectedItems
            open(selection.contains(clicked) ? selection : [clicked])
        }

        private func open(_ targets: [ShelfItem]) {
            targets.forEach { NSWorkspace.shared.open($0.url) }
        }

        private func revealInFinder(_ targets: [ShelfItem]) {
            NSWorkspace.shared.activateFileViewerSelecting(targets.map(\.url))
        }

        private func copyPaths(_ targets: [ShelfItem]) {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(ShelfFileInfo.pathsText(targets.map(\.url)), forType: .string)
        }

        // MARK: 우클릭 메뉴

        func contextMenu(clickedAt indexPath: IndexPath) -> NSMenu? {
            guard indexPath.item < items.count else { return nil }
            let clicked = items[indexPath.item]
            let targets = selectedItems.isEmpty ? [clicked] : selectedItems
            let count = targets.count
            let many = count > 1

            let menu = NSMenu()
            menu.delegate = self
            menu.autoenablesItems = false
            menu.addItem(ClosureMenuItem(many ? "\(count)개 항목 열기" : "열기") { [weak self] in self?.open(targets) })
            menu.addItem(ClosureMenuItem(many ? "\(count)개 항목 훑어보기" : "훑어보기") { [weak self] in self?.toggleQuickLook() })
            menu.addItem(.separator())
            menu.addItem(ClosureMenuItem("Finder에서 보기") { [weak self] in self?.revealInFinder(targets) })
            menu.addItem(ClosureMenuItem("정보 보기") { [weak self] in self?.showInfo(for: clicked, hover: false) })
            menu.addItem(.separator())
            menu.addItem(ClosureMenuItem(many ? "\(count)개 경로 이름 복사" : "경로 이름 복사") { [weak self] in self?.copyPaths(targets) })
            return menu
        }

        func menuWillOpen(_ menu: NSMenu) {
            dismissHoverInfo()
            menuOpen = true
            parent.onHold(.contextMenu, true)
        }

        func menuDidClose(_ menu: NSMenu) {
            menuOpen = false
            parent.onHold(.contextMenu, false)
        }

        // MARK: 훑어보기(Quick Look)

        /// 스페이스·메뉴에서 호출. 열려 있으면 닫고, 아니면 선택한 첫 항목으로 연다.
        func toggleQuickLook() {
            guard !closeQuickLook(), let first = selectedItems.first, let collectionView else { return }
            dismissHoverInfo()
            // 미리보기 창은 키가 되지 않으므로 스페이스·Esc·방향키는 계속 셸프 패널의 컬렉션 뷰가 받는다.
            collectionView.window?.makeKey()
            collectionView.window?.makeFirstResponder(collectionView)
            previewing = true
            parent.onHold(.preview, true)
            preview.show(first.url)
        }

        /// 훑어보기가 열려 있으면 닫고 true.
        @discardableResult
        func closeQuickLook() -> Bool {
            guard preview.isVisible else { return false }
            preview.close()   // 정리는 onClose(previewDidClose)에서
            return true
        }

        private func previewDidClose() {
            guard previewing else { return }
            previewing = false
            parent.onHold(.preview, false)
        }

        /// 선택이 바뀌면(방향키·클릭) 첫 선택 항목으로 미리보기를 바꾸고, 선택이 비면 닫는다.
        /// 방향키로 옮기면 didDeselect가 didSelect보다 먼저 와서 순간적으로 선택이 비므로,
        /// 두 콜백이 모두 끝난 다음 런루프에서 판정한다(아니면 방향키가 미리보기를 닫아 버린다).
        private func refreshPreview() {
            guard previewing else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.previewing else { return }
                if let first = self.selectedItems.first {
                    self.preview.show(first.url)
                } else {
                    self.closeQuickLook()
                }
            }
        }

        // MARK: 파일 정보 팝오버(호버 · 정보 보기)

        private func showHoverInfo(for item: ShelfItem) {
            guard infoPopover == nil, !menuOpen, !previewing, dragged.isEmpty,
                  NSEvent.pressedMouseButtons == 0 else { return }
            showInfo(for: item, hover: true)
        }

        private func endHoverInfo(for item: ShelfItem) {
            guard infoIsHover, infoItemID == item.id else { return }
            closeInfo()
        }

        /// 클릭·드래그·메뉴 등 다른 조작이 시작되면 호버 팝오버만 닫는다(정보 보기로 연 것은 유지).
        func dismissHoverInfo() {
            if infoIsHover { closeInfo() }
        }

        /// hover=true: 마우스가 카드를 벗어나면 닫힘. false(정보 보기): 경로를 선택·복사할 수 있고,
        /// 팝오버 밖을 클릭하면 닫히며, 열려 있는 동안 패널을 펼친 상태로 유지한다.
        private func showInfo(for item: ShelfItem, hover: Bool) {
            guard let collectionView, let index = items.firstIndex(of: item),
                  let card = collectionView.item(at: IndexPath(item: index, section: 0)) else { return }
            closeInfo()

            let popover = NSPopover()
            popover.behavior = hover ? .applicationDefined : .transient
            popover.contentViewController = ShelfInfoViewController(url: item.url, selectable: !hover)
            popover.delegate = self
            infoPopover = popover
            infoItemID = item.id
            infoIsHover = hover
            if !hover {
                infoHold = true
                parent.onHold(.info, true)
                // 비활성 앱의 transient 팝오버는 다른 앱을 클릭해도 닫히지 않을 수 있어 직접 감시한다.
                outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                    self?.closeInfo()
                }
            }
            popover.show(relativeTo: card.view.bounds, of: card.view, preferredEdge: .maxY)
        }

        private func closeInfo() {
            guard let popover = infoPopover else { return }
            infoPopover = nil
            popover.delegate = nil
            popover.close()
            endInfoSession()
        }

        func popoverDidClose(_ notification: Notification) {
            guard let popover = notification.object as? NSPopover, popover === infoPopover else { return }
            infoPopover = nil
            endInfoSession()
        }

        private func endInfoSession() {
            infoItemID = nil
            infoIsHover = false
            if let outsideClickMonitor {
                NSEvent.removeMonitor(outsideClickMonitor)
                self.outsideClickMonitor = nil
            }
            if infoHold {
                infoHold = false
                parent.onHold(.info, false)
            }
        }
    }
}

/// 스페이스(훑어보기)·Esc·더블클릭(열기)·우클릭 메뉴와 카드 호버를 처리하는 컬렉션 뷰.
final class ShelfNSCollectionView: NSCollectionView {
    weak var actions: ShelfCollectionView.Coordinator?

    private var hoverTimer: Timer?
    private var hoveredIndexPath: IndexPath?

    /// 카드 호버는 추적 영역 대신 마우스 위치 폴링으로 판정한다. 비활성 앱의 nonactivating 패널에서
    /// 카드의 NSTrackingArea(.activeAlways)가 mouseEntered를 받지 못했다(실측). 패널 펼침 판정과 같은 방식.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        hoverTimer?.invalidate()
        hoverTimer = nil
        guard window != nil else { resetHover(); return }
        let timer = Timer(timeInterval: 0.1, target: self, selector: #selector(pollHover), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        hoverTimer = timer
    }

    @objc private func pollHover() {
        var hovered: IndexPath?
        if let window, window.isVisible {
            let mouse = NSEvent.mouseLocation
            // 훑어보기·팝오버·메뉴 같은 다른 창이 그 지점을 덮고 있으면 호버로 보지 않는다.
            if NSWindow.windowNumber(at: mouse, belowWindowWithWindowNumber: 0) == window.windowNumber {
                let point = convert(window.convertPoint(fromScreen: mouse), from: nil)
                if visibleRect.contains(point) { hovered = indexPathForItem(at: point) }
            }
        }
        guard hovered != hoveredIndexPath else { return }
        if let old = hoveredIndexPath { (item(at: old) as? ShelfCardItem)?.hoverExited() }
        if let new = hovered { (item(at: new) as? ShelfCardItem)?.hoverEntered() }
        hoveredIndexPath = hovered
    }

    /// 항목을 다시 불러오면 이전 인덱스가 다른 카드를 가리킬 수 있으므로 호버 상태를 비운다(다음 폴링에서 재판정).
    func resetHover() {
        hoveredIndexPath = nil
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.charactersIgnoringModifiers == " ", modifiers.isEmpty {
            actions?.toggleQuickLook()
            return
        }
        if event.keyCode == 53, actions?.closeQuickLook() == true { return }   // Esc: 훑어보기 닫기
        super.keyDown(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        actions?.dismissHoverInfo()
        super.mouseDown(with: event)   // 선택·드래그 추적(마우스를 뗄 때까지 반환하지 않음)
        guard event.clickCount == 2,
              let indexPath = indexPathForItem(at: convert(event.locationInWindow, from: nil)) else { return }
        actions?.open(at: indexPath)
    }

    /// Finder처럼: 선택 밖의 항목을 우클릭하면 그 항목만 선택한 뒤 메뉴를 띄운다. 빈 곳이면 메뉴 없음.
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let indexPath = indexPathForItem(at: convert(event.locationInWindow, from: nil)) else { return nil }
        if !selectionIndexPaths.contains(indexPath) {
            selectionIndexPaths = [indexPath]
        }
        window?.makeFirstResponder(self)
        return actions?.contextMenu(clickedAt: indexPath)
    }
}

/// 셸프 전용 훑어보기 창. Finder 훑어보기와 같은 QLPreviewView(이미지·영상 미리보기)를 키가 되지 않는 패널에 띄운다.
/// 시스템 QLPreviewPanel은 표시되면 스스로 키 윈도우가 되는데, 메뉴바 앱은 늘 비활성이라(최신 macOS는 스스로
/// 활성화하는 것도 막는다) 키여도 키 입력을 받지 못해 스페이스·Esc가 앞에 있는 다른 앱으로 샜다(실측).
/// 이 창은 키가 되지 않으므로 셸프 패널이 계속 키 입력을 받는다.
final class ShelfPreviewWindow: NSObject, NSWindowDelegate {
    var onClose: (() -> Void)?
    private var panel: NSPanel?
    private var previewView: QLPreviewView?

    var isVisible: Bool { panel?.isVisible ?? false }

    /// 보이지 않으면 마우스가 있는 화면 가운데에 열고, 이미 열려 있으면 내용만 바꾼다.
    func show(_ url: URL) {
        let panel = self.panel ?? makePanel()
        panel.title = url.lastPathComponent
        previewView?.previewItem = url as NSURL
        if !panel.isVisible {
            center(panel)
            panel.orderFrontRegardless()
        }
    }

    func close() {
        panel?.close()   // windowWillClose에서 정리
    }

    func windowWillClose(_ notification: Notification) {
        previewView?.previewItem = nil   // 영상 재생 중지
        onClose?()
    }

    private func makePanel() -> NSPanel {
        let panel = NonKeyPanel(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .hudWindow, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = NSSize(width: 320, height: 240)
        panel.delegate = self

        let view: QLPreviewView = QLPreviewView(frame: NSRect(x: 0, y: 0, width: 760, height: 520), style: .normal)
        view.autostarts = true   // 영상은 열자마자 재생(Finder 훑어보기와 동일)
        view.shouldCloseWithWindow = false   // 기본값(true)이면 창을 닫을 때 뷰가 영구히 닫혀, 다시 열면 예외로 앱이 종료된다
        view.autoresizingMask = [.width, .height]
        panel.contentView = view

        self.panel = panel
        previewView = view
        return panel
    }

    /// 마우스가 있는 화면 가운데. 크기는 사용자가 조절한 값을 유지하되 화면보다 크지 않게.
    private func center(_ panel: NSPanel) {
        guard let screen = ScreenUtils.screenWithMouse() ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        var frame = panel.frame
        frame.size.width = min(frame.width, visible.width * 0.9)
        frame.size.height = min(frame.height, visible.height * 0.9)
        frame.origin = NSPoint(x: visible.midX - frame.width / 2, y: visible.midY - frame.height / 2)
        panel.setFrame(frame, display: false)
    }
}

/// 키·메인 윈도우가 되지 않는 패널(키 입력은 셸프 패널이 받는다).
private final class NonKeyPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// 클로저를 실행하는 메뉴 항목(메뉴가 살아 있는 동안 자신을 target으로 둔다).
private final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func fire() { handler() }
}

/// 파일 정보 팝오버 내용: 파일명, 절대경로, 크기, 생성일·수정일.
final class ShelfInfoViewController: NSViewController {
    private let url: URL
    private let pathSelectable: Bool   // 정보 보기로 연 경우 경로를 선택·복사할 수 있게

    init(url: URL, selectable: Bool) {
        self.url = url
        self.pathSelectable = selectable
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        let maxValueWidth: CGFloat = 340

        let title = NSTextField(labelWithString: url.lastPathComponent)
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.lineBreakMode = .byTruncatingMiddle
        title.widthAnchor.constraint(lessThanOrEqualToConstant: maxValueWidth + 60).isActive = true

        let rows = ShelfFileInfo.rows(for: url).map { row -> [NSView] in
            let key = NSTextField(labelWithString: row.label)
            key.font = .systemFont(ofSize: 11, weight: .medium)
            key.textColor = .secondaryLabelColor
            let value = NSTextField(wrappingLabelWithString: row.value)
            value.font = .systemFont(ofSize: 11)
            value.lineBreakMode = .byCharWrapping   // 긴 경로는 글자 단위로 줄바꿈
            value.preferredMaxLayoutWidth = maxValueWidth
            value.isSelectable = pathSelectable
            return [key, value]
        }
        let grid = NSGridView(views: rows)
        grid.rowSpacing = 4
        grid.columnSpacing = 8
        grid.rowAlignment = .firstBaseline
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).width = maxValueWidth

        let stack = NSStackView(views: [title, grid])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        // 폭은 명시한다. fittingSize에만 맡기면 줄바꿈된 경로 폭이 덜 잡혀 팝오버 오른쪽이 잘렸다(실측).
        // 라벨 열(~45) + 간격 8 + 값 열 + 좌우 여백 28을 넉넉히 덮는 폭.
        let width = maxValueWidth + 100
        stack.widthAnchor.constraint(equalToConstant: width).isActive = true
        view = stack
        stack.layoutSubtreeIfNeeded()
        preferredContentSize = NSSize(width: width, height: stack.fittingSize.height)
    }
}

/// 썸네일 + 이름 카드. 선택 링, 호버 시 제거 버튼, 호버가 이어지면 파일 정보.
final class ShelfCardItem: NSCollectionViewItem {
    static let id = NSUserInterfaceItemIdentifier("ShelfCardItem")
    static let hoverInfoDelay: TimeInterval = 0.9   // 이만큼 머물면 파일 정보 팝오버

    private let card = NSView()
    private let thumb = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let removeButton = NSButton()
    private let newBadge = NSTextField(labelWithString: "NEW")
    private var onRemove: (() -> Void)?
    private var onHoverInfo: (() -> Void)?
    private var onHoverEnd: (() -> Void)?
    private var hoverWork: DispatchWorkItem?
    private var currentURL: URL?
    private var isNewItem = false

    override func loadView() { view = NSView() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.wantsLayer = true

        card.wantsLayer = true
        card.layer?.cornerRadius = 12
        card.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.07).cgColor
        card.layer?.borderWidth = 2
        card.layer?.borderColor = NSColor.clear.cgColor
        card.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(card)

        thumb.imageScaling = .scaleProportionallyUpOrDown
        thumb.wantsLayer = true
        thumb.layer?.cornerRadius = 8
        thumb.layer?.masksToBounds = true
        thumb.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(thumb)

        nameLabel.font = .systemFont(ofSize: 11, weight: .medium)
        nameLabel.textColor = .white
        nameLabel.alignment = .center
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.maximumNumberOfLines = 1
        nameLabel.cell?.truncatesLastVisibleLine = true
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(nameLabel)

        removeButton.bezelStyle = .circular
        removeButton.isBordered = false
        removeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "제거")
        removeButton.contentTintColor = .white
        removeButton.target = self
        removeButton.action = #selector(removeTapped)
        removeButton.isHidden = true
        removeButton.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(removeButton)

        newBadge.font = .systemFont(ofSize: 8, weight: .heavy)
        newBadge.textColor = NSColor(calibratedRed: 0.02, green: 0.15, blue: 0.06, alpha: 1)
        newBadge.alignment = .center
        newBadge.drawsBackground = true
        newBadge.backgroundColor = .systemGreen
        newBadge.wantsLayer = true
        newBadge.layer?.cornerRadius = 5
        newBadge.layer?.masksToBounds = true
        newBadge.isHidden = true
        newBadge.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(newBadge)

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: view.topAnchor),
            card.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            card.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // 가로형 썸네일(카드 폭을 채움)
            thumb.topAnchor.constraint(equalTo: card.topAnchor, constant: 8),
            thumb.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 8),
            thumb.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -8),
            thumb.heightAnchor.constraint(equalToConstant: 44),

            nameLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 6),
            nameLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -6),
            nameLabel.topAnchor.constraint(equalTo: thumb.bottomAnchor, constant: 5),

            removeButton.topAnchor.constraint(equalTo: card.topAnchor, constant: 2),
            removeButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -2),
            removeButton.widthAnchor.constraint(equalToConstant: 18),
            removeButton.heightAnchor.constraint(equalToConstant: 18),

            newBadge.topAnchor.constraint(equalTo: card.topAnchor, constant: 4),
            newBadge.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 4),
            newBadge.widthAnchor.constraint(equalToConstant: 32),
            newBadge.heightAnchor.constraint(equalToConstant: 15),
        ])
    }

    func configure(with item: ShelfItem, isNew: Bool, onRemove: @escaping () -> Void,
                   onHoverInfo: @escaping () -> Void, onHoverEnd: @escaping () -> Void) {
        cancelHover()
        removeButton.isHidden = true   // 재사용된 카드에 이전 호버의 제거 버튼이 남지 않게
        self.onRemove = onRemove
        self.onHoverInfo = onHoverInfo
        self.onHoverEnd = onHoverEnd
        currentURL = item.url
        nameLabel.stringValue = item.name
        isNewItem = isNew
        newBadge.isHidden = !isNew
        updateAppearance()
        thumb.image = NSWorkspace.shared.icon(forFile: item.url.path)   // 즉시 표시(플레이스홀더)
        loadThumbnail(item.url)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        cancelHover()
    }

    private func updateAppearance() {
        if isNewItem {
            card.layer?.borderColor = NSColor.systemGreen.cgColor
            card.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.14).cgColor
        } else if isSelected {
            card.layer?.borderColor = NSColor.controlAccentColor.cgColor
            card.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.14).cgColor
        } else {
            card.layer?.borderColor = NSColor.clear.cgColor
            card.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.07).cgColor
        }
    }

    private func loadThumbnail(_ url: URL) {
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: 104, height: 104), scale: 2, representationTypes: .thumbnail
        )
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] rep, _ in
            guard let rep else { return }
            DispatchQueue.main.async {
                guard let self, self.currentURL == url else { return }
                self.thumb.image = rep.nsImage
            }
        }
    }

    override var isSelected: Bool {
        didSet { updateAppearance() }
    }

    /// 마우스가 카드에 올라옴(컬렉션 뷰의 호버 폴링이 호출).
    func hoverEntered() {
        removeButton.isHidden = false
        hoverWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onHoverInfo?() }
        hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.hoverInfoDelay, execute: work)
    }

    /// 마우스가 카드를 벗어남(컬렉션 뷰의 호버 폴링이 호출).
    func hoverExited() {
        removeButton.isHidden = true
        cancelHover()
    }

    private func cancelHover() {
        hoverWork?.cancel()
        hoverWork = nil
        onHoverEnd?()
    }

    @objc private func removeTapped() { onRemove?() }
}
