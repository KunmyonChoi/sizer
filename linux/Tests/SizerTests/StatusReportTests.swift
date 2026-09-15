import XCTest
@testable import Sizer

final class StatusReportTests: XCTestCase {

    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("sizer-status-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func job(_ name: String, success: Bool = true, at seconds: TimeInterval = 0) -> StatusReport.Job {
        StatusReport.Job(source: name, output: success ? "/o/\(name)" : nil, kind: "video",
                         success: success, detail: "1.0MB → 0.5MB (50% 절감)", date: Date(timeIntervalSince1970: seconds))
    }

    private func sample(state: StatusReport.State = .converting, current: String? = "a.mp4", queued: Int = 2) -> StatusReport {
        StatusReport(version: "1.10.0", pid: 42, state: state, current: current, queued: queued,
                     ffmpegAvailable: true, dropFolder: "/d", outputFolder: "/o", failedFolder: "/f",
                     recent: [job("a_resize.mp4")])
    }

    /// 트레이(linux/packaging/tray/sizer-tray)가 읽는 키. 바꾸면 트레이와 그 테스트도 함께 고친다.
    func testJSONKeysMatchTrayContract() throws {
        let data = try StatusReport.encoder().encode(sample())
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["version", "pid", "state", "current", "queued", "ffmpegAvailable",
                                          "dropFolder", "outputFolder", "failedFolder", "recent"])
        XCTAssertEqual(object["state"] as? String, "converting")
        let first = try XCTUnwrap((object["recent"] as? [[String: Any]])?.first)
        XCTAssertEqual(Set(first.keys), ["source", "output", "kind", "success", "detail", "date"])
        XCTAssertEqual(first["date"] as? String, "1970-01-01T00:00:00Z", "파이썬 datetime.fromisoformat 이 읽는 형식")
    }

    func testWriteAndReadRoundTrip() {
        let url = dir.appendingPathComponent("run/status.json")
        sample().write(to: url)
        XCTAssertEqual(StatusReport.read(from: url), sample())
        XCTAssertNil(StatusReport.read(from: dir.appendingPathComponent("missing.json")))
    }

    func testSummary() {
        XCTAssertEqual(sample().summary, "변환 중: a.mp4 · 대기 2")
        XCTAssertEqual(sample(state: .watching, current: nil, queued: 0).summary, "감시 중")
        XCTAssertEqual(sample(state: .paused, current: "a.mp4", queued: 0).summary, "일시정지 · a.mp4 마무리 중")
    }

    func testJobFromOutcome() {
        let ok = StatusReport.Job(JobOutcome(sourceName: "a.png", outputName: "a_resize.avif",
                                             outputURL: URL(fileURLWithPath: "/o/a_resize.avif"),
                                             kind: .image, success: true, detail: "d"))
        XCTAssertEqual(ok.kind, "image")
        XCTAssertEqual(ok.output, "/o/a_resize.avif")

        let failed = StatusReport.Job(JobOutcome(sourceName: "b.mp4", outputName: nil, outputURL: nil,
                                                 kind: .video, success: false, detail: "실패"))
        XCTAssertEqual(failed.kind, "video")
        XCTAssertNil(failed.output)
        XCTAssertFalse(failed.success)
    }

    func testAppendingPutsNewestFirstAndCaps() {
        var jobs: [StatusReport.Job] = []
        for i in 0..<(StatusReport.recentLimit + 5) {
            jobs = StatusReport.appending(job("\(i).mp4"), to: jobs)
        }
        XCTAssertEqual(jobs.count, StatusReport.recentLimit)
        XCTAssertEqual(jobs.first?.source, "\(StatusReport.recentLimit + 4).mp4")
    }

    func testRecentPersistsAcrossRestarts() {
        let url = dir.appendingPathComponent("state/recent.json")
        XCTAssertEqual(StatusReport.loadRecent(from: url), [], "처음에는 비어 있다")
        let jobs = [job("b.mp4", at: 60), job("a.mp4", success: false)]
        StatusReport.saveRecent(jobs, to: url)
        XCTAssertEqual(StatusReport.loadRecent(from: url), jobs)
    }

    func testHolderPIDReadsLockOwner() {
        let url = dir.appendingPathComponent("daemon.lock")
        XCTAssertNil(InstanceLock.holderPID(at: url))
        let lock = InstanceLock(url: url)
        XCTAssertTrue(lock.tryAcquire())
        XCTAssertEqual(InstanceLock.holderPID(at: url), getpid())
        lock.release()
        XCTAssertNil(InstanceLock.holderPID(at: url), "잠금이 풀리면 PID 가 파일에 남아 있어도 nil")
    }
}
