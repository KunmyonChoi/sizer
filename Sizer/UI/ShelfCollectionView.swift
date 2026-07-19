import AppKit
import SwiftUI
import QuickLookThumbnailing

/// 셸프 항목(썸네일 카드) 영역. NSCollectionView로 다중 선택 + Finder로 드래그-아웃을 네이티브 처리.
struct ShelfCollectionView: NSViewRepresentable {
    var items: [ShelfItem]
    var onRemove: (ShelfItem) -> Void
    var onMovedOut: (ShelfItem) -> Void   // Finder가 이동(.move)해 원본이 사라진 항목
    var onDragSession: (Bool) -> Void = { _ in }   // 카드 드래그-아웃 중 여부(셸프 접힘 방지)

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let collectionView = NSCollectionView()
        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 92, height: 104)
        layout.minimumInteritemSpacing = 8
        layout.minimumLineSpacing = 8
        layout.sectionInset = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        layout.scrollDirection = .horizontal
        collectionView.collectionViewLayout = layout
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = true
        collectionView.allowsEmptySelection = true
        collectionView.backgroundColors = [.clear]
        collectionView.dataSource = context.coordinator
        collectionView.delegate = context.coordinator
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
        context.coordinator.items = items
        (nsView.documentView as? NSCollectionView)?.reloadData()
    }

    final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate {
        var parent: ShelfCollectionView
        var items: [ShelfItem]
        weak var collectionView: NSCollectionView?
        private var dragged: [ShelfItem] = []

        init(_ parent: ShelfCollectionView) {
            self.parent = parent
            self.items = parent.items
        }

        func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
            items.count
        }

        func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
            let card = collectionView.makeItem(withIdentifier: ShelfCardItem.id, for: indexPath) as! ShelfCardItem
            let shelfItem = items[indexPath.item]
            card.configure(with: shelfItem) { [weak self] in self?.parent.onRemove(shelfItem) }
            return card
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
            dragged = indexPaths.sorted().compactMap { $0.item < items.count ? items[$0.item] : nil }
            parent.onDragSession(true)
        }

        func collectionView(_ collectionView: NSCollectionView, draggingSession session: NSDraggingSession,
                            endedAt screenPoint: NSPoint, dragOperation operation: NSDragOperation) {
            if operation.contains(.move) {
                dragged.forEach { parent.onMovedOut($0) }
            }
            dragged = []
            parent.onDragSession(false)
        }
    }
}

/// 썸네일 + 이름 카드. 선택 링, 호버 시 제거 버튼.
final class ShelfCardItem: NSCollectionViewItem {
    static let id = NSUserInterfaceItemIdentifier("ShelfCardItem")

    private let card = NSView()
    private let thumb = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let removeButton = NSButton()
    private var onRemove: (() -> Void)?
    private var currentURL: URL?
    private var tracking: NSTrackingArea?

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

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: view.topAnchor),
            card.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            card.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            thumb.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
            thumb.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            thumb.widthAnchor.constraint(equalToConstant: 52),
            thumb.heightAnchor.constraint(equalToConstant: 52),

            nameLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 6),
            nameLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -6),
            nameLabel.topAnchor.constraint(equalTo: thumb.bottomAnchor, constant: 8),

            removeButton.topAnchor.constraint(equalTo: card.topAnchor, constant: 2),
            removeButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -2),
            removeButton.widthAnchor.constraint(equalToConstant: 18),
            removeButton.heightAnchor.constraint(equalToConstant: 18),
        ])
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        if let tracking { view.removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: view.bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        view.addTrackingArea(area)
        tracking = area
    }

    func configure(with item: ShelfItem, onRemove: @escaping () -> Void) {
        self.onRemove = onRemove
        currentURL = item.url
        nameLabel.stringValue = item.name
        thumb.image = NSWorkspace.shared.icon(forFile: item.url.path)   // 즉시 표시(플레이스홀더)
        loadThumbnail(item.url)
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
        didSet {
            card.layer?.borderColor = (isSelected ? NSColor.controlAccentColor : NSColor.clear).cgColor
            card.layer?.backgroundColor = NSColor.white.withAlphaComponent(isSelected ? 0.14 : 0.07).cgColor
        }
    }

    override func mouseEntered(with event: NSEvent) { removeButton.isHidden = false }
    override func mouseExited(with event: NSEvent) { removeButton.isHidden = true }

    @objc private func removeTapped() { onRemove?() }
}
