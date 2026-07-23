import XCTest
@testable import Sizer

final class ConversionEngineTests: XCTestCase {

    private let dst = URL(fileURLWithPath: "/tmp/sizer-out/클립_resize.mp4")

    /// 회귀 방지: 임시 경로가 결정적이면 인스턴스가 둘일 때 두 ffmpeg가 같은 파일에 동시 기록해
    /// 결과물이 깨진다(실제 사고). 호출마다 반드시 달라야 한다.
    func testTempOutputURLIsUniquePerCall() {
        let a = ConversionEngine.tempOutputURL(for: dst)
        let b = ConversionEngine.tempOutputURL(for: dst)
        XCTAssertNotEqual(a, b, "임시 경로는 실행마다 고유해야 함")
    }

    func testTempOutputURLStaysBesideDestination() {
        let tmp = ConversionEngine.tempOutputURL(for: dst)
        // 같은 폴더(같은 볼륨) → 최종 이동이 rename이 되어 원자적
        XCTAssertEqual(tmp.deletingLastPathComponent(), dst.deletingLastPathComponent())
        XCTAssertEqual(tmp.pathExtension, "part")
        XCTAssertTrue(tmp.lastPathComponent.hasPrefix("."), "출력 폴더에 보이지 않도록 숨김 파일")
    }

    func testTempOutputURLNeverEqualsDestination() {
        XCTAssertNotEqual(ConversionEngine.tempOutputURL(for: dst), dst)
    }
}
