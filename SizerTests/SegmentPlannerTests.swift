import XCTest
@testable import Sizer

final class SegmentPlannerTests: XCTestCase {

    // MARK: keepSegments (여집합)

    func testKeepSegmentsBasicComplement() {
        // 정지: [2,4], [7,9]  / 전체 10s → 유지: [0,2],[4,7],[9,10]
        let freezes = [Segment(2, 4), Segment(7, 9)]
        let keep = SegmentPlanner.keepSegments(freezes: freezes, duration: 10)
        XCTAssertEqual(keep, [Segment(0, 2), Segment(4, 7), Segment(9, 10)])
    }

    func testKeepSegmentsLeadingAndTrailingFreeze() {
        // 정지가 처음과 끝: [0,3],[8,10] → 유지: [3,8]
        let freezes = [Segment(0, 3), Segment(8, 10)]
        let keep = SegmentPlanner.keepSegments(freezes: freezes, duration: 10)
        XCTAssertEqual(keep, [Segment(3, 8)])
    }

    func testKeepSegmentsClampsToDuration() {
        // freeze end가 duration을 넘어가면 duration으로 클램프
        let freezes = [Segment(2, 99)]
        let keep = SegmentPlanner.keepSegments(freezes: freezes, duration: 10)
        XCTAssertEqual(keep, [Segment(0, 2)])
    }

    // MARK: mergeShortGaps (부드러움)

    func testMergeShortGapsMergesTinyGap() {
        // 유지 [0,2],[2.3,5] 사이 정지 0.3s ≤ 0.5 → 병합 → [0,5]
        let keep = [Segment(0, 2), Segment(2.3, 5)]
        let merged = SegmentPlanner.mergeShortGaps(keep, mergeGapMax: 0.5)
        XCTAssertEqual(merged, [Segment(0, 5)])
    }

    func testMergeShortGapsKeepsLargeGap() {
        // 사이 정지 1.0s > 0.5 → 병합 안 함
        let keep = [Segment(0, 2), Segment(3, 5)]
        let merged = SegmentPlanner.mergeShortGaps(keep, mergeGapMax: 0.5)
        XCTAssertEqual(merged, [Segment(0, 2), Segment(3, 5)])
    }

    func testMergeShortGapsRespectsSceneChange() {
        // 짧은 gap이라도 그 안에 장면 전환(2.1s)이 있으면 병합하지 않음
        let keep = [Segment(0, 2), Segment(2.3, 5)]
        let merged = SegmentPlanner.mergeShortGaps(keep, mergeGapMax: 0.5, sceneChanges: [2.1])
        XCTAssertEqual(merged, [Segment(0, 2), Segment(2.3, 5)])
    }

    // MARK: dropShortSegments (정확도)

    func testDropShortSegments() {
        let keep = [Segment(0, 2), Segment(2.5, 2.6), Segment(3, 6)]
        let dropped = SegmentPlanner.dropShortSegments(keep, minKeep: 0.3)
        XCTAssertEqual(dropped, [Segment(0, 2), Segment(3, 6)])
    }

    // MARK: pad (부드러움)

    func testPadExpandsAndClamps() {
        // [2,5] 를 0.2 패딩 → [1.8,5.2], duration 10 클램프 영향 없음
        let padded = SegmentPlanner.pad([Segment(2, 5)], by: 0.2, duration: 10)
        XCTAssertEqual(padded, [Segment(1.8, 5.2)])
    }

    func testPadClampsToBounds() {
        // 시작 0 근처와 끝 근처는 [0,duration]로 클램프
        let padded = SegmentPlanner.pad([Segment(0.1, 9.9)], by: 0.5, duration: 10)
        XCTAssertEqual(padded, [Segment(0, 10)])
    }

    func testPadMergesOverlapsCreatedByPadding() {
        // [0,2],[2.3,5] 를 0.2 패딩하면 [−0.2→0,2.2],[2.1,5.2] 가 겹쳐 → [0,5.2]
        let padded = SegmentPlanner.pad([Segment(0, 2), Segment(2.3, 5)], by: 0.2, duration: 10)
        XCTAssertEqual(padded, [Segment(0, 5.2)])
    }

    // MARK: plan (전체 파이프라인 + 안전장치)

    func testPlanReturnsNilWhenNoFreezes() {
        XCTAssertNil(SegmentPlanner.plan(freezes: [], duration: 10, options: TrimOptions()))
    }

    func testPlanReturnsNilWhenOverTrimmed() {
        // 거의 전체가 정지 → 유지가 minKeepRatio 미만 → 트리밍 취소(nil)
        var opts = TrimOptions()
        opts.pad = 0
        opts.minKeep = 0.05
        let freezes = [Segment(0.1, 100)]
        XCTAssertNil(SegmentPlanner.plan(freezes: freezes, duration: 100, options: opts))
    }

    func testPlanReturnsNilWhenRemovalNegligible() {
        // 정지가 있지만 mergeGapMax로 다시 병합되어 실제 제거량 < 0.5s → nil
        var opts = TrimOptions()
        opts.mergeGapMax = 1.0
        opts.pad = 0
        let freezes = [Segment(5, 5.3)] // 0.3s 정지, mergeGap로 흡수
        XCTAssertNil(SegmentPlanner.plan(freezes: freezes, duration: 20, options: opts))
    }

    func testPlanHappyPath() {
        // 명확한 정지 두 곳 제거
        var opts = TrimOptions()
        opts.pad = 0
        opts.minKeep = 0.1
        opts.mergeGapMax = 0.5
        let freezes = [Segment(3, 8), Segment(12, 18)]
        let plan = SegmentPlanner.plan(freezes: freezes, duration: 20, options: opts)
        XCTAssertNotNil(plan)
        // 유지 = [0,3],[8,12],[18,20] = 3+4+2 = 9s
        XCTAssertEqual(plan!.totalDuration, 9, accuracy: 0.001)
    }
}
