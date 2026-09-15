import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// `sizer` 명령. 실행 파일(SizerCLI/main.swift)은 이것만 호출한다.
public enum SizerCLI {

    public static func main(_ argv: [String]) -> Int32 {
        var args = Array(argv.dropFirst())
        let command = args.isEmpty ? "help" : args.removeFirst()
        if command != "daemon" && command != "watch" {
            AppLogger.echoToStderr = false   // 자기 출력과 섞이지 않게(기록은 로그 파일에만)
        }
        switch command {
        case "daemon", "watch": return daemon()
        case "add": return add(args)
        case "convert": return convert(args)
        case "open": return openLocation(args)
        case "pause": return signalDaemon(SIGUSR1, done: "감시를 일시정지했습니다(변환 중인 파일은 마저 끝냅니다).")
        case "resume": return signalDaemon(SIGUSR2, done: "감시를 재개했습니다.")
        case "rescan": return signalDaemon(SIGHUP, done: "설정을 다시 읽고 드롭 폴더를 다시 살펴봅니다.")
        case "status": return status()
        case "config": return config(args)
        case "version", "--version", "-V":
            print("sizer \(BuildInfo.version)")
            return 0
        case "help", "--help", "-h":
            print(usage)
            return 0
        default:
            printError("알 수 없는 명령: \(command)\n\n\(usage)")
            return 2
        }
    }

    static let usage = """
    사용법: sizer <명령> [인자]

      daemon                    드롭 폴더를 감시하며 변환 (systemd 사용자 서비스가 실행)
      add <파일>...              드롭 폴더에 넣어 데몬이 변환 — 파일 관리자 우클릭 메뉴가 쓰는 명령
                                (데몬이 꺼져 있으면 켜고, 켤 수 없으면 바로 변환)
      convert [-o 폴더] <파일>... 지금 이 터미널에서 변환 (원본은 그대로 둠)
      open [drop|output|processed|failed|logs|config]
                                폴더·로그·설정 파일 열기 (기본: drop)
      pause | resume            감시 일시정지 / 재개
      rescan                    설정을 다시 읽고 드롭 폴더 다시 살펴보기
      status                    데몬·ffmpeg·폴더 상태
      config [path|init]        설정 파일 보기 / 경로 / 기본값으로 다시 만들기
      version                   버전

    설정 파일: ~/.config/sizer/config.json — 저장하면 데몬이 바로 다시 읽습니다.
    로그:      ~/.local/state/sizer/convert.log  (서비스 로그: journalctl --user -u sizer)
    """

    // MARK: daemon

    static func daemon() -> Int32 {
        let lock = InstanceLock()
        guard lock.tryAcquire() else {
            printError("Sizer 데몬이 이미 실행 중입니다.")
            return 1
        }
        guard let settings = loadSettings(logWarnings: true) else { return 1 }
        let daemon = Daemon(settings: settings)
        daemon.start()
        withExtendedLifetime((lock, daemon)) {
            dispatchMain()
        }
    }

    // MARK: add

    static func add(_ args: [String]) -> Int32 {
        let paths = args.filter { $0 != "--" }
        guard !paths.isEmpty else {
            printError("넣을 파일을 지정하세요: sizer add <파일>...")
            return 2
        }
        guard let settings = loadSettings() else { return 1 }
        let urls = paths.map(fileURL)
        let supported = DropIngest.supportedURLs(urls, imageEnabled: settings.imageEnabled)
        guard !supported.isEmpty else {
            let message = settings.imageEnabled
                ? "변환할 수 있는 영상·이미지가 없습니다"
                : "변환할 수 있는 영상이 없습니다(이미지 변환은 설정에서 꺼져 있음)"
            printError(message)
            if settings.notifications && !isTerminal { Notifier.notify(title: "Sizer", body: message) }
            return 1
        }
        if urls.count > supported.count {
            printError("지원하지 않는 형식 \(urls.count - supported.count)개는 건너뜁니다.")
        }

        guard Daemon.isRunning() || startService() else {
            // 서비스가 없거나(수동 설치) 켤 수 없으면 이 프로세스에서 바로 변환한다.
            return convertNow(supported, settings: settings, outputFolder: nil,
                              notify: settings.notifications && !isTerminal)
        }

        settings.ensureFolders()
        var added = 0
        for url in supported {
            // 한 파일씩 복사 직후 표식을 남긴다 — 데몬이 이 파일을 마치기 전에 표식이 있어야 한다.
            for dest in DropIngest.copy([url], to: settings.dropFolder) {
                AddedMarks.mark(dest.lastPathComponent)
                added += 1
            }
        }
        print("드롭 폴더에 \(added)개를 넣었습니다 — 변환이 끝나면 알림이 뜹니다.")
        return added == supported.count ? 0 : 1
    }

    /// systemd 사용자 서비스를 켜고 데몬이 잠금을 잡을 때까지 잠깐 기다린다. 서비스가 없거나 실패하면 false.
    static func startService() -> Bool {
        guard let systemctl = Executables.find("systemctl"),
              FFmpeg.run(systemctl, ["--user", "start", "sizer.service"], timeout: 15).succeeded else { return false }
        for _ in 0..<50 {
            if Daemon.isRunning() { return true }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return false
    }

    // MARK: convert

    static func convert(_ args: [String]) -> Int32 {
        var outputFolder: URL?
        var paths: [String] = []
        var i = 0
        var optionsEnded = false
        while i < args.count {
            let arg = args[i]
            if !optionsEnded && arg == "--" {
                optionsEnded = true
            } else if !optionsEnded && (arg == "-o" || arg == "--output") {
                guard i + 1 < args.count else {
                    printError("\(arg) 뒤에 출력 폴더를 지정하세요")
                    return 2
                }
                outputFolder = fileURL(args[i + 1])
                i += 1
            } else if !optionsEnded && arg.hasPrefix("--output=") {
                outputFolder = fileURL(String(arg.dropFirst("--output=".count)))
            } else if !optionsEnded && arg.hasPrefix("-") && arg != "-" {
                printError("알 수 없는 옵션: \(arg)")
                return 2
            } else {
                paths.append(arg)
            }
            i += 1
        }
        guard !paths.isEmpty else {
            printError("변환할 파일을 지정하세요: sizer convert [-o 폴더] <파일>...")
            return 2
        }
        guard let settings = loadSettings() else { return 1 }
        let urls = paths.map(fileURL)
        // 명령으로 직접 고른 파일이므로 이미지 변환 설정과 무관하게 변환한다.
        let supported = DropIngest.supportedURLs(urls, imageEnabled: true)
        for url in urls where !supported.contains(url) {
            printError("건너뜀(지원하지 않는 형식): \(url.path)")
        }
        guard !supported.isEmpty else { return 1 }
        return convertNow(supported, settings: settings, outputFolder: outputFolder, notify: false)
    }

    /// 원본을 건드리지 않도록 캐시의 작업 폴더에 링크(안 되면 복사)해서 변환하고, 작업 폴더는 지운다.
    static func convertNow(_ sources: [URL], settings: LinuxSettings, outputFolder: URL?, notify: Bool) -> Int32 {
        let fm = FileManager.default
        let staging = Paths.cacheDir.appendingPathComponent("staging/\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: staging) }

        var config = settings.config
        config.processedFolder = staging.appendingPathComponent("done", isDirectory: true)
        config.failedFolder = staging.appendingPathComponent("failed", isDirectory: true)
        if let outputFolder { config.outputFolder = outputFolder }
        do {
            try fm.createDirectory(at: config.outputFolder, withIntermediateDirectories: true)
        } catch {
            printError("출력 폴더를 만들 수 없습니다: \(config.outputFolder.path) — \(error.localizedDescription)")
            return 1
        }

        var failures = 0
        for (index, src) in sources.enumerated() {
            print("[\(index + 1)/\(sources.count)] \(src.lastPathComponent) 변환 중…")
            fflush(stdout)
            let slot = staging.appendingPathComponent("\(index)", isDirectory: true)
            guard let staged = stage(src, into: slot) else {
                printError("  ✗ 읽을 수 없음: \(src.path)")
                failures += 1
                continue
            }
            let outcome = ConversionEngine.process(staged, config: config)
            let failureNote: String
            if outcome.success {
                print("  ✓ \(outcome.outputURL?.path ?? "") — \(outcome.detail)")
                failureNote = ""
            } else {
                failures += 1
                failureNote = outcome.detail == "ffmpeg 없음"
                    ? "ffmpeg 가 없습니다 — sudo apt install ffmpeg"
                    : "원본은 그대로 있습니다 · 로그: \(Paths.abbreviate(AppLogger.logFileURL.path))"
                printError("  ✗ 실패 — \(failureNote)")
            }
            if notify {
                Notifier.notifyOutcome(outcome, withActions: false, failureNote: failureNote)
            }
        }
        return failures == 0 ? 0 : 1
    }

    private static func stage(_ src: URL, into dir: URL) -> URL? {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: src.path, isDirectory: &isDir), !isDir.boolValue,
              (try? fm.createDirectory(at: dir, withIntermediateDirectories: true)) != nil else { return nil }
        let dest = dir.appendingPathComponent(src.lastPathComponent)
        if link(src.path, dest.path) == 0 { return dest }
        return (try? fm.copyItem(at: src, to: dest)) != nil ? dest : nil
    }

    // MARK: pause · resume · rescan

    static func signalDaemon(_ sig: Int32, done: String) -> Int32 {
        guard let pid = InstanceLock.holderPID() else {
            printError("Sizer 데몬이 실행 중이 아닙니다 — systemctl --user start sizer")
            return 1
        }
        guard kill(pid, sig) == 0 else {
            printError("데몬(PID \(pid))에 신호를 보내지 못했습니다(errno \(errno))")
            return 1
        }
        print(done)
        return 0
    }

    // MARK: open · status · config

    static func openLocation(_ args: [String]) -> Int32 {
        guard let settings = loadSettings() else { return 1 }
        let target = args.first ?? "drop"
        let folders = ["drop": settings.dropFolder, "output": settings.outputFolder,
                       "processed": settings.processedFolder, "failed": settings.failedFolder]
        if let folder = folders[target] {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            Desktop.open(folder)
        } else if target == "logs" {
            if FileManager.default.fileExists(atPath: AppLogger.logFileURL.path) {
                Desktop.reveal(AppLogger.logFileURL)
            } else {
                try? FileManager.default.createDirectory(at: Paths.stateDir, withIntermediateDirectories: true)
                Desktop.open(Paths.stateDir)
            }
        } else if target == "config" {
            Desktop.openInTextEditor(Paths.configFile)
        } else {
            printError("열 수 있는 곳: drop, output, processed, failed, logs, config")
            return 2
        }
        return 0
    }

    static func status() -> Int32 {
        guard let settings = loadSettings() else { return 1 }
        func row(_ label: String, _ value: String) {
            // 한글은 터미널에서 두 칸을 차지하므로 글자 수가 아니라 표시 폭으로 맞춘다.
            let width = label.unicodeScalars.reduce(0) { total, scalar in
                let wide = (0x1100...0x115F).contains(scalar.value) || (0x2E80...0xA4CF).contains(scalar.value)
                    || (0xAC00...0xD7A3).contains(scalar.value) || (0xFF00...0xFF60).contains(scalar.value)
                return total + (wide ? 2 : 1)
            }
            print(label + String(repeating: " ", count: max(1, 10 - width)) + value)
        }
        func tool(_ url: URL?, missing: String) -> String { url?.path ?? "없음 — \(missing)" }

        var daemon = Daemon.isRunning() ? "실행 중" : "꺼짐"
        if let systemctl = Executables.find("systemctl") {
            let enabled = FFmpeg.run(systemctl, ["--user", "is-enabled", "sizer.service"], timeout: 5)
                .stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !enabled.isEmpty { daemon += " (로그인 시 시작: \(enabled == "enabled" ? "켬" : enabled))" }
        }
        print("Sizer \(BuildInfo.version)")
        row("데몬", daemon)
        if Daemon.isRunning(), let report = StatusReport.read() {
            row("상태", report.summary)
        }
        row("ffmpeg", tool(FFmpeg.ffmpegURL, missing: "sudo apt install ffmpeg"))
        row("ffprobe", tool(FFmpeg.ffprobeURL, missing: "sudo apt install ffmpeg"))
        row("알림", tool(Executables.find("notify-send"), missing: "sudo apt install libnotify-bin"))
        row("설정", Paths.abbreviate(Paths.configFile.path))
        row("드롭", Paths.abbreviate(settings.dropFolder.path))
        row("출력", Paths.abbreviate(settings.outputFolder.path))
        row("완료", Paths.abbreviate(settings.processedFolder.path))
        row("실패", Paths.abbreviate(settings.failedFolder.path))
        row("로그", Paths.abbreviate(AppLogger.logFileURL.path))
        return 0
    }

    static func config(_ args: [String]) -> Int32 {
        let url = Paths.configFile
        switch args.first {
        case "path":
            print(url.path)
            return 0
        case "init":
            let fm = FileManager.default
            if fm.fileExists(atPath: url.path) {
                let backup = url.appendingPathExtension("bak")
                try? fm.removeItem(at: backup)
                try? fm.moveItem(at: url, to: backup)
                print("기존 설정을 \(Paths.abbreviate(backup.path)) 로 옮겼습니다.")
            }
            _ = try? LinuxSettings.loadOrCreate(at: url)
            print("기본 설정 파일을 만들었습니다: \(url.path)")
            return 0
        case nil:
            guard loadSettings() != nil, let text = try? String(contentsOf: url, encoding: .utf8) else { return 1 }
            print("# \(url.path)")
            print(text, terminator: text.hasSuffix("\n") ? "" : "\n")
            return 0
        default:
            printError("사용법: sizer config [path|init]")
            return 2
        }
    }

    // MARK: helpers

    private static func loadSettings(logWarnings: Bool = false) -> LinuxSettings? {
        do {
            let (settings, warnings) = try LinuxSettings.loadOrCreate()
            for warning in warnings {
                if logWarnings { AppLogger.warn("설정: \(warning)") } else { printError("설정 경고: \(warning)") }
            }
            return settings
        } catch {
            let message = "설정 파일 오류(\(Paths.configFile.path)): \(error)"
            if logWarnings { AppLogger.error(message) } else { printError(message) }
            return nil
        }
    }

    private static func fileURL(_ path: String) -> URL {
        let expanded = Paths.expand(path)
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        return URL(fileURLWithPath: expanded, relativeTo: cwd).standardizedFileURL
    }

    private static var isTerminal: Bool { isatty(STDOUT_FILENO) != 0 }

    private static func printError(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
