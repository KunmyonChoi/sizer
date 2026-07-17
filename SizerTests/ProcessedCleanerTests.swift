import XCTest
@testable import Sizer

final class ProcessedCleanerTests: XCTestCase {

    private func makeFile(_ dir: URL, _ name: String, daysAgo: Double) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try "x".data(using: .utf8)!.write(to: url)
        let date = Date().addingTimeInterval(-daysAgo * 86_400)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        return url
    }

    func testDeletesOldKeepsRecent() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("sizer-clean-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        let old = try makeFile(dir, "old.mov", daysAgo: 40)
        let recent = try makeFile(dir, "recent.mov", daysAgo: 5)
        let borderlineNew = try makeFile(dir, "borderline.mov", daysAgo: 29)

        let deleted = ProcessedCleaner.clean(folder: dir, olderThanDays: 30)

        XCTAssertEqual(deleted, 1)
        XCTAssertFalse(fm.fileExists(atPath: old.path), "40일 된 파일이 삭제되지 않음")
        XCTAssertTrue(fm.fileExists(atPath: recent.path), "5일 된 파일이 삭제됨")
        XCTAssertTrue(fm.fileExists(atPath: borderlineNew.path), "29일 된 파일이 삭제됨")
    }

    func testDaysZeroDeletesNothing() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("sizer-clean-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        _ = try makeFile(dir, "veryold.mov", daysAgo: 999)
        let deleted = ProcessedCleaner.clean(folder: dir, olderThanDays: 0)
        XCTAssertEqual(deleted, 0, "days=0이면 아무 것도 삭제하지 않아야 함")
    }

    func testSkipsHiddenFiles() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("sizer-clean-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        let hidden = try makeFile(dir, ".DS_Store", daysAgo: 100)
        let deleted = ProcessedCleaner.clean(folder: dir, olderThanDays: 30)
        XCTAssertEqual(deleted, 0)
        XCTAssertTrue(fm.fileExists(atPath: hidden.path), "숨김 파일은 건드리지 않아야 함")
    }
}
