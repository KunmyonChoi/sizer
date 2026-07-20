import XCTest
@testable import Sizer

@MainActor
final class ShelfIntegrationTests: XCTestCase {

    private let H = ShelfView.panelHeight(showConvertZone: true)   // 324 (220 + 104)
    private let W = ShelfView.expandedWidth
    private let handle = ShelfView.handleWidth
    private let czH = ShelfView.convertZoneHeight

    private func zone(_ p: CGPoint, handleOnLeft: Bool = true,
                      integrated: Bool = true, expanded: Bool = true) -> ShelfDropZone {
        ShelfDropZone.at(p, panelHeight: H, panelWidth: W, handleWidth: handle,
                         convertZoneHeight: czH, handleOnLeft: handleOnLeft,
                         integrated: integrated, expanded: expanded)
    }

    // MARK: 드롭 존 라우팅(순수 함수)

    func testTopRegionIsConvertWhenIntegratedAndExpanded() {
        XCTAssertEqual(zone(CGPoint(x: 200, y: H - 10)), .convert)   // 상단, 핸들 밖
    }

    func testBottomRegionIsHold() {
        XCTAssertEqual(zone(CGPoint(x: 200, y: 60)), .hold)
    }

    func testHandleColumnNeverConvert() {
        // 왼쪽 도킹: 상단이라도 왼쪽 핸들 열이면 보관(안전)
        XCTAssertEqual(zone(CGPoint(x: handle - 5, y: H - 10)), .hold)
    }

    func testRightDockHandleColumnNeverConvert() {
        // 오른쪽 도킹: 핸들은 우측(x > panelWidth - handleWidth)
        XCTAssertEqual(zone(CGPoint(x: W - 5, y: H - 10), handleOnLeft: false), .hold)
    }

    func testRightDockTopIsConvert() {
        // 오른쪽 도킹: 우측 핸들 밖 상단이면 변환
        XCTAssertEqual(zone(CGPoint(x: 200, y: H - 10), handleOnLeft: false), .convert)
    }

    func testCollapsedNeverConvert() {
        XCTAssertEqual(zone(CGPoint(x: 200, y: H - 10), expanded: false), .hold)   // C6
    }

    func testNonIntegratedNeverConvert() {
        XCTAssertEqual(zone(CGPoint(x: 200, y: H - 10), integrated: false), .hold)
    }

    func testConvertBoundaryIsInclusive() {
        XCTAssertEqual(zone(CGPoint(x: 200, y: H - czH)), .convert)
        XCTAssertEqual(zone(CGPoint(x: 200, y: H - czH - 1)), .hold)
    }

    // MARK: S5 — 결과를 트레이 맨 앞에 삽입

    func testInsertFrontPlacesResultFirst() {
        let store = ShelfStore()
        let a = URL(fileURLWithPath: "/tmp/a.mp4")
        let b = URL(fileURLWithPath: "/tmp/b_resize.mp4")
        store.add([a])
        XCTAssertTrue(store.insertFront(b))
        XCTAssertEqual(store.items.map { $0.url.lastPathComponent }, ["b_resize.mp4", "a.mp4"])
    }

    func testInsertFrontDeduplicates() {
        let store = ShelfStore()
        let a = URL(fileURLWithPath: "/tmp/a.mp4")
        store.add([a])
        XCTAssertFalse(store.insertFront(a), "이미 있는 경로는 삽입하지 않아야 함")
        XCTAssertEqual(store.count, 1)
    }
}
