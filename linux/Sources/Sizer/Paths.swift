import Foundation

/// XDG 기본 디렉터리 규약에 따른 Linux 경로.
enum Paths {
    private static var env: [String: String] { ProcessInfo.processInfo.environment }

    static var home: URL { URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true) }

    private static func xdg(_ key: String, _ fallback: String) -> URL {
        if let value = env[key], value.hasPrefix("/") {
            return URL(fileURLWithPath: value, isDirectory: true)
        }
        return home.appendingPathComponent(fallback, isDirectory: true)
    }

    static var configDir: URL { xdg("XDG_CONFIG_HOME", ".config").appendingPathComponent("sizer", isDirectory: true) }
    static var stateDir: URL { xdg("XDG_STATE_HOME", ".local/state").appendingPathComponent("sizer", isDirectory: true) }
    static var cacheDir: URL { xdg("XDG_CACHE_HOME", ".cache").appendingPathComponent("sizer", isDirectory: true) }

    /// 실행 중에만 의미 있는 파일(데몬 잠금, add 표식). 로그아웃하면 비워진다. 없으면 상태 디렉터리 아래.
    static var runtimeDir: URL {
        if let value = env["XDG_RUNTIME_DIR"], value.hasPrefix("/") {
            return URL(fileURLWithPath: value, isDirectory: true).appendingPathComponent("sizer", isDirectory: true)
        }
        return stateDir.appendingPathComponent("run", isDirectory: true)
    }

    static var configFile: URL { configDir.appendingPathComponent("config.json") }
    static var logFile: URL { stateDir.appendingPathComponent("convert.log") }

    /// 사용자 동영상 폴더(user-dirs.dirs 의 XDG_VIDEOS_DIR). 한국어 데스크톱이면 보통 ~/비디오.
    static var videosDir: URL {
        let file = xdg("XDG_CONFIG_HOME", ".config").appendingPathComponent("user-dirs.dirs")
        if let text = try? String(contentsOf: file, encoding: .utf8),
           let dir = parseUserDirs(text, home: home.path)["XDG_VIDEOS_DIR"],
           dir.hasPrefix("/"),
           URL(fileURLWithPath: dir).standardizedFileURL != home.standardizedFileURL {   // 비활성이면 $HOME 으로 적힌다
            return URL(fileURLWithPath: dir, isDirectory: true)
        }
        return home.appendingPathComponent("Videos", isDirectory: true)
    }

    /// user-dirs.dirs(`XDG_VIDEOS_DIR="$HOME/Videos"` 형식)를 키→절대경로로 읽는다.
    static func parseUserDirs(_ text: String, home: String) -> [String: String] {
        var result: [String: String] = [:]
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.hasPrefix("#"), let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<eq])
            var value = String(line[line.index(after: eq)...])
            if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            result[key] = value.replacingOccurrences(of: "$HOME", with: home)
        }
        return result
    }

    /// "~", "~/x", "$HOME/x" 를 절대경로로 펼친다.
    static func expand(_ path: String, home: String = Paths.home.path) -> String {
        if path == "~" { return home }
        if path.hasPrefix("~/") { return home + path.dropFirst() }
        if path.hasPrefix("$HOME") { return home + path.dropFirst("$HOME".count) }
        return path
    }

    /// 홈 아래 경로를 "~/..." 로 줄여 보여 준다.
    static func abbreviate(_ path: String, home: String = Paths.home.path) -> String {
        let h = home.hasSuffix("/") ? String(home.dropLast()) : home
        if path == h { return "~" }
        if path.hasPrefix(h + "/") { return "~" + path.dropFirst(h.count) }
        return path
    }
}

/// PATH 와 표준 위치에서 실행 파일을 찾는다.
enum Executables {
    static let standardDirs = ["/usr/local/bin", "/usr/bin", "/bin"]

    static func find(_ name: String) -> URL? {
        let pathDirs = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        for dir in pathDirs + standardDirs {
            let candidate = URL(fileURLWithPath: dir).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }
}
