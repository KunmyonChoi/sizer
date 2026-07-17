import Foundation

struct ProcessResult {
    let status: Int32
    let stdout: String
    let stderr: String
    var succeeded: Bool { status == 0 }
}

/// ffmpeg/ffprobe 위치 탐색 + 실행 래퍼.
/// 현재(개인용 로컬 빌드): Homebrew 참조. 후속(배포): 번들 Helpers 우선.
enum FFmpeg {
    static let searchPaths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]

    static func locate(_ name: String) -> URL? {
        // 1) 앱 번들에 동봉된 헬퍼(후속 배포용)
        if let helpers = Bundle.main.url(forResource: name, withExtension: nil, subdirectory: "Helpers"),
           FileManager.default.isExecutableFile(atPath: helpers.path) {
            return helpers
        }
        // 2) 일반적인 Homebrew/시스템 경로
        for dir in searchPaths {
            let candidate = URL(fileURLWithPath: dir).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    static var ffmpegURL: URL? { locate("ffmpeg") }
    static var ffprobeURL: URL? { locate("ffprobe") }
    static var isAvailable: Bool { ffmpegURL != nil }

    /// 프로세스를 실행하고 종료까지 대기. stdout/stderr를 데드락 없이 병렬로 읽는다.
    @discardableResult
    static func run(_ executable: URL, _ args: [String], timeout: TimeInterval? = nil) -> ProcessResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = args

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return ProcessResult(status: -1, stdout: "", stderr: "\(error)")
        }

        if let timeout {
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if process.isRunning { process.terminate() }
            }
        }

        var outData = Data()
        var errData = Data()
        let group = DispatchGroup()
        let q = DispatchQueue(label: "com.dilly.sizer.ffmpeg.pipe", attributes: .concurrent)
        group.enter()
        q.async { outData = outPipe.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        group.enter()
        q.async { errData = errPipe.fileHandleForReading.readDataToEndOfFile(); group.leave() }

        process.waitUntilExit()
        group.wait()

        return ProcessResult(
            status: process.terminationStatus,
            stdout: String(decoding: outData, as: UTF8.self),
            stderr: String(decoding: errData, as: UTF8.self)
        )
    }
}
