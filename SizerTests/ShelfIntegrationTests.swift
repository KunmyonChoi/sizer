import XCTest
@testable import Sizer

@MainActor
final class ShelfIntegrationTests: XCTestCase {

    private let H = ShelfView.panelHeight(showConvertZone: true)   // 312 (220 + 92)
    private let handle = ShelfView.handleWidth
    private let czH = ShelfView.convertZoneHeight

    // MARK: 드롭 존 라우팅(순수 함수)

    func testTopRegionIsConvertWhenIntegratedAndExpanded() {
        // 상단(y >= panelHeight - convertZoneHeight), 핸들 밖 → 변환
        let p = CGPoint(x: 200, y: H - 10)
        XCTAssertEqual(ShelfDropZone.at(p, panelHeight: H, handleWidth: handle,
                                        convertZoneHeight: czH, integrated: true, expanded: true), .convert)
    }

    func testBottomRegionIsHold() {
        let p = CGPoint(x: 200, y: 60)   // 하단
        XCTAssertEqual(ShelfDropZone.at(p, panelHeight: H, handleWidth: handle,
                                        convertZoneHeight: czH, integrated: true, expanded: true), .hold)
    }

    func testHandleColumnNeverConvert() {
        // 상단이라도 핸들 열(x < handleWidth)이면 보관(안전)
        let p = CGPoint(x: handle - 5, y: H - 10)
        XCTAssertEqual(ShelfDropZone.at(p, panelHeight: H, handleWidth: handle,
                                        convertZoneHeight: czH, integrated: true, expanded: true), .hold)
    }

    func testCollapsedNeverConvert() {
        // 접힘 상태에서는 존을 확정하지 않고 항상 보관(C6)
        let p = CGPoint(x: 200, y: H - 10)
        XCTAssertEqual(ShelfDropZone.at(p, panelHeight: H, handleWidth: handle,
                                        convertZoneHeight: czH, integrated: true, expanded: false), .hold)
    }

    func testNonIntegratedNeverConvert() {
        // 분리 모드 셸프는 변환존이 없으므로 항상 보관
        let p = CGPoint(x: 200, y: H - 10)
        XCTAssertEqual(ShelfDropZone.at(p, panelHeight: H, handleWidth: handle,
                                        convertZoneHeight: czH, integrated: false, expanded: true), .hold)
    }

    func testConvertBoundaryIsInclusive() {
        // 경계(정확히 panelHeight - convertZoneHeight)는 변환에 포함
        let p = CGPoint(x: 200, y: H - czH)
        XCTAssertEqual(ShelfDropZone.at(p, panelHeight: H, handleWidth: handle,
                                        convertZoneHeight: czH, integrated: true, expanded: true), .convert)
        let below = CGPoint(x: 200, y: H - czH - 1)
        XCTAssertEqual(ShelfDropZone.at(below, panelHeight: H, handleWidth: handle,
                                        convertZoneHeight: czH, integrated: true, expanded: true), .hold)
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
