import XCTest
@testable import Sizer

@MainActor
final class ShelfStoreTests: XCTestCase {

    func testAddDedupesBySamePath() {
        let store = ShelfStore()
        let a = URL(fileURLWithPath: "/tmp/a.mov")
        let b = URL(fileURLWithPath: "/tmp/b.png")
        XCTAssertEqual(store.add([a, b]), 2)
        XCTAssertEqual(store.add([a]), 0, "이미 있는 경로는 추가되지 않아야 함")
        XCTAssertEqual(store.count, 2)
    }

    func testAddIgnoresNonFileURLs() {
        let store = ShelfStore()
        let web = URL(string: "https://example.com/x.mov")!
        let file = URL(fileURLWithPath: "/tmp/x.mov")
        XCTAssertEqual(store.add([web, file]), 1)
        XCTAssertEqual(store.count, 1)
    }

    func testRemoveAndClear() {
        let store = ShelfStore()
        _ = store.add([URL(fileURLWithPath: "/tmp/a.mov"), URL(fileURLWithPath: "/tmp/b.mov")])
        let first = store.items[0]
        store.remove(first)
        XCTAssertEqual(store.count, 1)
        store.clear()
        XCTAssertTrue(store.isEmpty)
    }
}
