import Foundation
import os

/// os.Logger + ~/Movies/Sizer/logs/convert.log 파일 로깅.
enum AppLogger {
    private static let osLog = Logger(subsystem: "com.dilly.sizer", category: "convert")
    private static let queue = DispatchQueue(label: "com.dilly.sizer.log")

    static let logFileURL: URL = {
        let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Movies")
        let dir = movies.appendingPathComponent("Sizer/logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("convert.log")
    }()

    static func info(_ msg: String) { osLog.info("\(msg, privacy: .public)"); write("INFO", msg) }
    static func warn(_ msg: String) { osLog.warning("\(msg, privacy: .public)"); write("WARN", msg) }
    static func error(_ msg: String) { osLog.error("\(msg, privacy: .public)"); write("ERROR", msg) }

    private static func write(_ level: String, _ msg: String) {
        queue.async {
            let line = "\(timestamp()) [\(level)] \(msg)\n"
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: logFileURL) {
                defer { try? handle.close() }
                handle.seekToEndOfFile()
                handle.write(data)
            } else {
                try? data.write(to: logFileURL)
            }
        }
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: Date())
    }
}
