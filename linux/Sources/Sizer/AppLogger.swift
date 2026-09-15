import Foundation

/// ~/.local/state/sizer/convert.log 파일 로깅(macOS 판은 os.Logger + ~/Movies/Sizer/logs).
/// 데몬은 표준 오류에도 써서 systemd 저널(`journalctl --user -u sizer`)에 남긴다.
enum AppLogger {
    private static let queue = DispatchQueue(label: "com.dilly.sizer.log")

    /// 표준 오류에도 쓸지. CLI 는 자기 출력과 섞이지 않게 끈다.
    static var echoToStderr = true

    static var logFileURL: URL { Paths.logFile }

    static func info(_ msg: String) { write("INFO", msg) }
    static func warn(_ msg: String) { write("WARN", msg) }
    static func error(_ msg: String) { write("ERROR", msg) }

    // CLI 는 기록 직후 종료하므로 비동기로 쓰면 마지막 줄을 잃는다 — 동기로 쓴다(로그량이 적다).
    private static func write(_ level: String, _ msg: String) {
        queue.sync {
            if echoToStderr {
                FileHandle.standardError.write(Data("[\(level)] \(msg)\n".utf8))
            }
            let url = logFileURL
            let line = Data("\(timestamp()) [\(level)] \(msg)\n".utf8)
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                handle.seekToEndOfFile()
                handle.write(line)
            } else {
                try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? line.write(to: url)
            }
        }
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: Date())
    }
}
