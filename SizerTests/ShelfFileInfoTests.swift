import XCTest
@testable import Sizer

final class ShelfFileInfoTests: XCTestCase {

    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("ShelfFileInfoTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testReadExistingFileHasAbsolutePathSizeAndDates() throws {
        let url = dir.appendingPathComponent("clip.mov")
        try Data(repeating: 7, count: 1234).write(to: url)

        let info = try XCTUnwrap(ShelfFileInfo.read(url))
        XCTAssertEqual(info.path, url.standardizedFileURL.path)
        XCTAssertTrue(info.path.hasPrefix("/"), "절대경로여야 함")
        XCTAssertEqual(info.name, "clip.mov")
        XCTAssertEqual(info.size, 1234)
        XCTAssertNotNil(info.created)
        XCTAssertNotNil(info.modified)
    }

    func testReadStandardizesRelativeComponents() throws {
        let url = dir.appendingPathComponent("a.png")
        try Data([1]).write(to: url)
        let messy = dir.appendingPathComponent("sub/../a.png")

        XCTAssertEqual(ShelfFileInfo.read(messy)?.path, url.standardizedFileURL.path)
    }

    func testReadDirectoryHasNoSize() throws {
        let info = try XCTUnwrap(ShelfFileInfo.read(dir))
        XCTAssertNil(info.size, "폴더 크기는 표시하지 않음")
    }

    func testReadMissingFileIsNil() {
        XCTAssertNil(ShelfFileInfo.read(dir.appendingPathComponent("gone.mp4")))
    }

    func testRowsForExistingFile() throws {
        let url = dir.appendingPathComponent("clip.mov")
        try Data(repeating: 0, count: 10).write(to: url)

        let rows = ShelfFileInfo.rows(for: url)
        XCTAssertEqual(rows.map(\.label), ["경로", "크기", "생성일", "수정일"])
        XCTAssertEqual(rows.first?.value, url.standardizedFileURL.path)
    }

    func testRowsForMissingFileShowPathAndNotice() {
        let url = dir.appendingPathComponent("gone.mp4")
        let rows = ShelfFileInfo.rows(for: url)
        XCTAssertEqual(rows.map(\.label), ["경로", "상태"])
        XCTAssertEqual(rows.first?.value, url.standardizedFileURL.path)
    }

    func testFormatSizeIncludesExactGroupedBytes() {
        XCTAssertTrue(ShelfFileInfo.formatSize(12_345_678).hasSuffix("(12,345,678바이트)"))
        XCTAssertTrue(ShelfFileInfo.formatSize(0).hasSuffix("(0바이트)"))
    }

    func testFormatDateUsesSecondsInGivenTimeZone() throws {
        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let seoul = try XCTUnwrap(TimeZone(identifier: "Asia/Seoul"))
        let date = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(ShelfFileInfo.formatDate(date, timeZone: utc), "1970-01-01 00:00:00")
        XCTAssertEqual(ShelfFileInfo.formatDate(date, timeZone: seoul), "1970-01-01 09:00:00")
    }

    func testPathsTextJoinsAbsolutePathsByNewline() {
        let a = URL(fileURLWithPath: "/tmp/x/a.mov")
        let b = URL(fileURLWithPath: "/tmp/x/../y/b 1.png")
        XCTAssertEqual(ShelfFileInfo.pathsText([a, b]), "/tmp/x/a.mov\n/tmp/y/b 1.png")
        XCTAssertEqual(ShelfFileInfo.pathsText([a]), "/tmp/x/a.mov")
    }
}
