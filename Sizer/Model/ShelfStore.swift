import Foundation

/// 셸프에 담긴 파일 하나(원본 참조).
struct ShelfItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    var name: String { url.lastPathComponent }

    static func == (lhs: ShelfItem, rhs: ShelfItem) -> Bool { lhs.id == rhs.id }
}

/// 임시 파일 보관대. 원본 URL을 참조로 담아 두었다가 드래그로 꺼낸다.
@MainActor
final class ShelfStore: ObservableObject {
    @Published private(set) var items: [ShelfItem] = []

    var isEmpty: Bool { items.isEmpty }
    var count: Int { items.count }

    /// URL들을 추가(같은 경로 중복은 무시). 추가된 개수 반환.
    @discardableResult
    func add(_ urls: [URL]) -> Int {
        var added = 0
        for url in urls where url.isFileURL {
            let std = url.standardizedFileURL
            guard !items.contains(where: { $0.url.standardizedFileURL == std }) else { continue }
            items.append(ShelfItem(url: std))
            added += 1
        }
        return added
    }

    func remove(_ item: ShelfItem) {
        items.removeAll { $0.id == item.id }
    }

    func remove(id: UUID) {
        items.removeAll { $0.id == id }
    }

    func clear() {
        items.removeAll()
    }
}
