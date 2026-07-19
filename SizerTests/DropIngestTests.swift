import XCTest
@testable import Sizer

final class DropIngestTests: XCTestCase {

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sizer-drop-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeFile(_ dir: URL, _ name: String) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try Data("x".utf8).write(to: url)
        return url
    }

    func testSupportedFiltersByType() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let mp4 = try makeFile(dir, "a.mp4")
        let mov = try makeFile(dir, "b.MOV")   // 대소문자 무관
        let png = try makeFile(dir, "c.png")
        let txt = try makeFile(dir, "d.txt")
        let all = [mp4, mov, png, txt]

        let withImages = DropIngest.supportedURLs(all, imageEnabled: true)
        XCTAssertEqual(Set(withImages.map { $0.lastPathComponent }), ["a.mp4", "b.MOV", "c.png"])

        let noImages = DropIngest.supportedURLs(all, imageEnabled: false)
        XCTAssertEqual(Set(noImages.map { $0.lastPathComponent }), ["a.mp4", "b.MOV"])
    }

    func testCopyCopiesAndDedupes() throws {
        let src = try tempDir()
        let drop = try tempDir()
        defer { try? FileManager.default.removeItem(at: src); try? FileManager.default.removeItem(at: drop) }

        let a = try makeFile(src, "clip.mp4")
        // 드롭 폴더에 같은 이름 선점 → 복사 시 번호 부여되어야 함
        try Data("existing".utf8).write(to: drop.appendingPathComponent("clip.mp4"))

        let count = DropIngest.copy([a], to: drop).count
        XCTAssertEqual(count, 1)
        let names = try FileManager.default.contentsOfDirectory(at: drop, includingPropertiesForKeys: nil)
            .map { $0.lastPathComponent }
        XCTAssertTrue(names.contains("clip.mp4"))
        XCTAssertTrue(names.contains("clip_1.mp4"), "이름 충돌 시 번호가 붙어야 함")
    }

    func testCopySkipsDirectories() throws {
        let src = try tempDir()
        let drop = try tempDir()
        defer { try? FileManager.default.removeItem(at: src); try? FileManager.default.removeItem(at: drop) }
        let subdir = src.appendingPathComponent("folder")
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)

        let count = DropIngest.copy([subdir], to: drop).count
        XCTAssertEqual(count, 0, "디렉터리는 복사하지 않아야 함")
    }
}
