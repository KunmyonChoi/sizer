import XCTest
@testable import Sizer

final class FreezeDetectorTests: XCTestCase {

    // MARK: 적응형 임계값 (순수 로직)

    func testAdaptiveKeepsThresholdOnCleanContent() {
        // 깨끗한 콘텐츠(노이즈 floor ~0, trigger 미만) → 변경 없음
        XCTAssertEqual(FreezeDetector.adaptiveNoiseDb(base: -58, floorMafd: 0.0), -58)
        XCTAssertEqual(FreezeDetector.adaptiveNoiseDb(base: -58, floorMafd: 0.001), -58)
    }

    func testAdaptiveLoosensStrictThresholdOnNoisyContent() {
        // 노이즈 floor가 trigger 초과(실측 노이즈판 ~0.14) → 엄격한 -58을 안전 상한 -50까지 완화
        XCTAssertEqual(FreezeDetector.adaptiveNoiseDb(base: -58, floorMafd: 0.14), -50)
    }

    func testAdaptiveNeverExceedsSafeLooseBound() {
        // 완화해도 -50dB(검증된 안전 상한)보다 느슨해지지 않는다
        let result = FreezeDetector.adaptiveNoiseDb(base: -70, floorMafd: 0.2)
        XCTAssertEqual(result, -50)
        XCTAssertLessThanOrEqual(result, FreezeDetector.adaptiveLooseDb)
    }

    func testAdaptiveRespectsUserAggressiveBase() {
        // 사용자가 이미 더 느슨하게(-45) 골랐으면 적응형이 더 조이지 않는다
        XCTAssertEqual(FreezeDetector.adaptiveNoiseDb(base: -45, floorMafd: 0.14), -45)
    }

    func testAdaptiveTriggerBoundaryIsStrict() {
        // 정확히 trigger면 완화 안 함(초과해야 완화)
        XCTAssertEqual(FreezeDetector.adaptiveNoiseDb(base: -58, floorMafd: FreezeDetector.noiseFloorTrigger), -58)
        XCTAssertEqual(FreezeDetector.adaptiveNoiseDb(base: -58, floorMafd: FreezeDetector.noiseFloorTrigger + 0.001), -50)
    }

    // MARK: median

    func testMedianOddEvenEmpty() {
        XCTAssertNil(FreezeDetector.median([]))
        XCTAssertEqual(FreezeDetector.median([5]), 5)
        XCTAssertEqual(FreezeDetector.median([3, 1, 2]), 2)              // 정렬 후 가운데
        XCTAssertEqual(FreezeDetector.median([4, 1, 3, 2]), 2.5)         // 짝수 → 평균
    }
}
