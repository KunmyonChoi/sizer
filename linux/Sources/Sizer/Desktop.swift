import Foundation

/// 데스크톱 연동: 기본 앱으로 열기, 파일 관리자에서 항목을 선택해 보여 주기.
enum Desktop {

    /// 기본 앱(폴더면 파일 관리자)으로 연다. 기다리지 않는다.
    static func open(_ url: URL) {
        guard let xdgOpen = Executables.find("xdg-open") else {
            AppLogger.warn("xdg-open 이 없어 열 수 없음: \(url.path)")
            return
        }
        spawn(xdgOpen, [url.path])
    }

    /// 사람이 고칠 텍스트 파일(설정 파일)을 텍스트 편집기로 연다.
    /// xdg-open 은 .json 을 JSON 기본 앱에 넘기는데 Ubuntu 에서는 보통 Firefox(snap)이고, snap 앱은 ~/.config 같은
    /// 숨김 폴더를 읽지 못해 아무것도 열리지 않는다. text/plain 기본 앱 → 흔한 편집기 → xdg-open 순으로 연다.
    static func openInTextEditor(_ url: URL) {
        if let gio = Executables.find("gio"), let desktopFile = defaultDesktopFile(for: "text/plain") {
            spawn(gio, ["launch", desktopFile, url.path])
            return
        }
        for editor in textEditors {
            if let executable = Executables.find(editor) {
                spawn(executable, [url.path])
                return
            }
        }
        open(url)
    }

    static let textEditors = ["gnome-text-editor", "gedit", "kate", "mousepad", "xed", "pluma"]

    /// MIME 형식의 기본 앱 .desktop 파일 경로.
    static func defaultDesktopFile(for mimeType: String) -> String? {
        guard let xdgMime = Executables.find("xdg-mime") else { return nil }
        let id = FFmpeg.run(xdgMime, ["query", "default", mimeType], timeout: 5)
            .stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return desktopFilePath(id: id, dataDirs: applicationDataDirs())
    }

    /// 데스크톱 항목 id(예 org.gnome.TextEditor.desktop)의 파일 경로. dataDirs 는 우선순위 순.
    static func desktopFilePath(id: String, dataDirs: [String]) -> String? {
        guard id.hasSuffix(".desktop"), !id.contains("/") else { return nil }
        for dir in dataDirs {
            let path = "\(dir)/applications/\(id)"
            if FileManager.default.fileExists(atPath: path) { return path }
        }
        return nil
    }

    /// XDG_DATA_HOME 다음 XDG_DATA_DIRS — .desktop 파일을 찾는 순서.
    static func applicationDataDirs() -> [String] {
        let env = ProcessInfo.processInfo.environment
        let dataHome = env["XDG_DATA_HOME"].flatMap { $0.hasPrefix("/") ? $0 : nil }
            ?? Paths.home.appendingPathComponent(".local/share").path
        let dataDirs = env["XDG_DATA_DIRS"].flatMap { $0.isEmpty ? nil : $0 } ?? "/usr/local/share:/usr/share"
        return [dataHome] + dataDirs.split(separator: ":").map(String.init)
    }

    /// 파일 관리자에서 항목을 선택해 보여 준다(org.freedesktop.FileManager1 — Nautilus 등). 안 되면 상위 폴더를 연다.
    static func reveal(_ url: URL) {
        if let gdbus = Executables.find("gdbus"),
           FFmpeg.run(gdbus, revealArguments(url), timeout: 5).succeeded {
            return
        }
        open(url.deletingLastPathComponent())
    }

    static func revealArguments(_ url: URL) -> [String] {
        let uri = url.standardizedFileURL.absoluteString
        return [
            "call", "--session",
            "--dest", "org.freedesktop.FileManager1",
            "--object-path", "/org/freedesktop/FileManager1",
            "--method", "org.freedesktop.FileManager1.ShowItems",
            "['\(gvariantEscaped(uri))']", "''",
        ]
    }

    /// GVariant 텍스트 형식의 작은따옴표 문자열 안에 넣을 수 있게 이스케이프.
    static func gvariantEscaped(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
    }

    /// 실행만 하고 기다리지 않는다(출력은 버림).
    static func spawn(_ executable: URL, _ args: [String]) {
        let process = Process()
        process.executableURL = executable
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            AppLogger.warn("실행 실패: \(executable.lastPathComponent) — \(error)")
        }
    }
}
