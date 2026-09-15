import XCTest
@testable import Sizer

/// 경로·잠금·감시·알림 인자 등 Linux 플랫폼 계층.
final class LinuxPlatformTests: XCTestCase {

    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("sizer-linux-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: Paths

    func testParseUserDirs() {
        let text = """
        # This file is written by xdg-user-dirs-update
        XDG_DESKTOP_DIR="$HOME/바탕화면"
        XDG_VIDEOS_DIR="$HOME/비디오"
        XDG_MUSIC_DIR="/mnt/music"
        """
        let dirs = Paths.parseUserDirs(text, home: "/home/u")
        XCTAssertEqual(dirs["XDG_VIDEOS_DIR"], "/home/u/비디오")
        XCTAssertEqual(dirs["XDG_MUSIC_DIR"], "/mnt/music")
        XCTAssertNil(dirs["# This file is written by xdg-user-dirs-update"])
    }

    func testExpandAndAbbreviate() {
        XCTAssertEqual(Paths.expand("~", home: "/home/u"), "/home/u")
        XCTAssertEqual(Paths.expand("~/Videos", home: "/home/u"), "/home/u/Videos")
        XCTAssertEqual(Paths.expand("$HOME/Videos", home: "/home/u"), "/home/u/Videos")
        XCTAssertEqual(Paths.expand("/abs", home: "/home/u"), "/abs")
        XCTAssertEqual(Paths.abbreviate("/home/u/Videos", home: "/home/u"), "~/Videos")
        XCTAssertEqual(Paths.abbreviate("/home/user2/x", home: "/home/u"), "/home/user2/x", "접두사만 같은 다른 홈은 줄이지 않음")
    }

    // MARK: InstanceLock · AddedMarks

    func testInstanceLockIsExclusive() {
        let url = dir.appendingPathComponent("daemon.lock")
        XCTAssertFalse(InstanceLock.isHeld(at: url), "잠금 파일이 없으면 데몬이 없다")

        let a = InstanceLock(url: url)
        XCTAssertTrue(a.tryAcquire())
        XCTAssertTrue(InstanceLock.isHeld(at: url))

        let b = InstanceLock(url: url)
        XCTAssertFalse(b.tryAcquire(), "두 번째 데몬은 잠금을 잡지 못해야 한다")

        a.release()
        XCTAssertFalse(InstanceLock.isHeld(at: url), "잠금 파일이 남아 있어도 풀린 잠금은 실행 중이 아니다")
        XCTAssertTrue(b.tryAcquire())
        b.release()
    }

    func testAddedMarksAreTakenOnce() {
        AddedMarks.mark("clip.mp4", in: dir)
        XCTAssertTrue(AddedMarks.take("clip.mp4", in: dir))
        XCTAssertFalse(AddedMarks.take("clip.mp4", in: dir))
        XCTAssertFalse(AddedMarks.take("other.mp4", in: dir))
    }

    // MARK: FolderWatcher

    func testFolderWatcherReportsNewFile() {
        let fired = expectation(description: "onChange")
        fired.assertForOverFulfill = false
        let watcher = FolderWatcher(path: dir.path) { fired.fulfill() }
        watcher.start()
        defer { watcher.stop() }

        XCTAssertTrue(FileManager.default.createFile(atPath: dir.appendingPathComponent("clip.mp4").path, contents: Data("x".utf8)))
        wait(for: [fired], timeout: 3)
    }

    // MARK: 알림 · 데스크톱

    func testNotificationBodyIsMarkupEscaped() {
        XCTAssertEqual(Notifier.markupEscaped("Tom & Jerry <1>.mp4"), "Tom &amp; Jerry &lt;1&gt;.mp4")
    }

    func testNotificationArguments() {
        let args = Notifier.arguments(title: "-제목", body: "a&b", actions: [("reveal", "폴더에서 보기")])
        XCTAssertTrue(args.contains("--action=reveal=폴더에서 보기"))
        XCTAssertTrue(args.contains("--hint=string:desktop-entry:com.dilly.sizer"))
        XCTAssertEqual(Array(args.suffix(3)), ["--", "-제목", "a&amp;b"], "제목이 - 로 시작해도 옵션으로 읽히지 않게")
    }

    func testDesktopFileLookupFollowsDataDirOrder() throws {
        let home = dir.appendingPathComponent("home"), system = dir.appendingPathComponent("system")
        for base in [home, system] {
            try FileManager.default.createDirectory(at: base.appendingPathComponent("applications"), withIntermediateDirectories: true)
        }
        FileManager.default.createFile(atPath: system.appendingPathComponent("applications/org.gnome.TextEditor.desktop").path, contents: nil)
        let dirs = [home.path, system.path]
        XCTAssertEqual(Desktop.desktopFilePath(id: "org.gnome.TextEditor.desktop", dataDirs: dirs),
                       system.appendingPathComponent("applications/org.gnome.TextEditor.desktop").path)

        FileManager.default.createFile(atPath: home.appendingPathComponent("applications/org.gnome.TextEditor.desktop").path, contents: nil)
        XCTAssertEqual(Desktop.desktopFilePath(id: "org.gnome.TextEditor.desktop", dataDirs: dirs),
                       home.appendingPathComponent("applications/org.gnome.TextEditor.desktop").path, "사용자 항목이 우선")

        XCTAssertNil(Desktop.desktopFilePath(id: "missing.desktop", dataDirs: dirs))
        XCTAssertNil(Desktop.desktopFilePath(id: "", dataDirs: dirs), "기본 앱이 없으면 xdg-mime 은 빈 줄을 낸다")
        XCTAssertNil(Desktop.desktopFilePath(id: "../applications/x.desktop", dataDirs: dirs))
    }

    func testRevealArgumentsEscapeQuotes() {
        let args = Desktop.revealArguments(URL(fileURLWithPath: "/tmp/it's 한글.mp4"))
        let items = try? XCTUnwrap(args.dropLast().last)
        XCTAssertEqual(args.last, "''")
        XCTAssertTrue(items?.hasPrefix("['file:///tmp/it\\'s") == true, "\(items ?? "")")
        XCTAssertTrue(items?.hasSuffix(".mp4']") == true, "\(items ?? "")")
        XCTAssertFalse(items?.contains(" ") == true, "URI 는 퍼센트 인코딩되어야 함")
    }

    // MARK: Files(Nautilus) 확장

    /// 우클릭 메뉴가 뜨는 확장자와 엔진이 변환하는 확장자가 어긋나지 않게 한다.
    func testNautilusExtensionListsSameExtensionsAsEngine() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let script = try String(contentsOf: root.appendingPathComponent("packaging/nautilus/sizer-nautilus.py"), encoding: .utf8)

        func set(named name: String) throws -> Set<String> {
            let re = try NSRegularExpression(pattern: name + #"\s*=\s*\{([^}]*)\}"#)
            let ns = script as NSString
            let match = try XCTUnwrap(re.firstMatch(in: script, range: NSRange(location: 0, length: ns.length)), name)
            let body = ns.substring(with: match.range(at: 1))
            return Set(body.split(separator: ",").map {
                $0.trimmingCharacters(in: CharacterSet(charactersIn: " \n\"'"))
            }.filter { !$0.isEmpty })
        }
        XCTAssertEqual(try set(named: "VIDEO_EXTENSIONS"), ConversionConfig.videoExtensions)
        XCTAssertEqual(try set(named: "IMAGE_EXTENSIONS"), ConversionConfig.imageExtensions)
    }
}
