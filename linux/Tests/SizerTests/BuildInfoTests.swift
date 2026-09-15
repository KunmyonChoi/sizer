import XCTest
@testable import Sizer

final class BuildInfoTests: XCTestCase {

    /// Linux 버전 상수가 macOS 앱 버전(project.yml)과 어긋나지 않게 한다.
    func testVersionMatchesProjectYml() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let yml = try String(contentsOf: root.appendingPathComponent("project.yml"), encoding: .utf8)
        let line = try XCTUnwrap(yml.split(separator: "\n").first { $0.contains("MARKETING_VERSION") })
        XCTAssertTrue(line.contains("\"\(BuildInfo.version)\""), "project.yml(\(line)) 과 BuildInfo.version(\(BuildInfo.version))이 다름")
    }
}
