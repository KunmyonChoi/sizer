import Foundation

/// 데몬 상태를 트레이(sizer-tray)·`sizer status` 와 나누는 JSON — $XDG_RUNTIME_DIR/sizer/status.json.
///
/// 데몬이 상태가 바뀔 때마다 통째로 원자적으로 다시 쓴다. 키를 바꾸면 linux/packaging/tray/sizer-tray 도
/// 함께 고쳐야 한다(StatusReportTests 가 키 목록을 고정한다). 최근 변환은 재로그인 뒤에도 트레이에 보이도록
/// ~/.local/state/sizer/recent.json 에도 남긴다.
struct StatusReport: Codable, Equatable {
    enum State: String, Codable {
        case watching, paused, converting
    }

    /// 최근 변환 한 건(macOS JobRecord 에 해당).
    struct Job: Codable, Equatable {
        var source: String
        var output: String?     // 성공 시 결과 파일 절대경로
        var kind: String        // "video" | "image"
        var success: Bool
        var detail: String
        var date: Date
    }

    var version: String
    var pid: Int32
    var state: State
    var current: String?        // 변환 중인 파일명
    var queued: Int             // 변환 대기(변환 중인 파일 제외)
    var ffmpegAvailable: Bool
    var dropFolder: String
    var outputFolder: String
    var failedFolder: String
    var recent: [Job]           // 최신이 앞

    static let recentLimit = 20
    static var fileURL: URL { Paths.runtimeDir.appendingPathComponent("status.json") }
    static var recentURL: URL { Paths.stateDir.appendingPathComponent("recent.json") }

    /// `sizer status` 와 트레이가 보여 주는 한 줄 상태.
    var summary: String {
        let waiting = queued > 0 ? " · 대기 \(queued)" : ""
        switch state {
        case .paused: return "일시정지" + (current.map { " · \($0) 마무리 중" } ?? "") + waiting
        case .converting: return "변환 중: \(current ?? "")" + waiting
        case .watching: return "감시 중" + waiting
        }
    }

    // MARK: 파일

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    func write(to url: URL = StatusReport.fileURL) {
        StatusReport.writeJSON(self, to: url)
    }

    static func read(from url: URL = StatusReport.fileURL) -> StatusReport? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder().decode(StatusReport.self, from: data)
    }

    static func loadRecent(from url: URL = StatusReport.recentURL) -> [Job] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? decoder().decode([Job].self, from: data)) ?? []
    }

    static func saveRecent(_ jobs: [Job], to url: URL = StatusReport.recentURL) {
        writeJSON(jobs, to: url)
    }

    /// 새 결과를 맨 앞에 넣고 recentLimit 개로 자른다.
    static func appending(_ job: Job, to jobs: [Job]) -> [Job] {
        Array(([job] + jobs).prefix(recentLimit))
    }

    // 읽는 쪽이 반쯤 쓰인 파일을 보지 않도록 임시 파일에 쓰고 이름을 바꾼다(.atomic).
    private static func writeJSON<T: Encodable>(_ value: T, to url: URL) {
        guard let data = try? encoder().encode(value) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            AppLogger.warn("상태 파일 쓰기 실패(\(url.lastPathComponent)): \(error.localizedDescription)")
        }
    }
}

extension StatusReport.Job {
    init(_ outcome: JobOutcome, date: Date = Date()) {
        self.init(source: outcome.sourceName,
                  output: outcome.success ? outcome.outputURL?.path : nil,
                  kind: outcome.kind == .image ? "image" : "video",
                  success: outcome.success,
                  detail: outcome.detail,
                  date: date)
    }
}
