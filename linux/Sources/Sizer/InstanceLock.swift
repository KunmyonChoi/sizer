import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// 사용자당 데몬을 하나만 돌리는 flock 잠금. `sizer add` 는 잠금이 잡혀 있는지로 데몬이 도는지 안다.
/// 프로세스가 죽으면 커널이 잠금을 풀어 주므로 낡은 잠금 파일이 남아도 문제없다.
final class InstanceLock {
    static var defaultURL: URL { Paths.runtimeDir.appendingPathComponent("daemon.lock") }

    let url: URL
    private var fd: Int32 = -1

    init(url: URL = InstanceLock.defaultURL) {
        self.url = url
    }

    /// 잠금을 잡는다. 다른 프로세스(또는 같은 프로세스의 다른 InstanceLock)가 잡고 있으면 false.
    func tryAcquire() -> Bool {
        guard fd < 0 else { return true }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fd = open(url.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o644)
        guard fd >= 0 else { return false }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd)
            return false
        }
        ftruncate(fd, 0)
        let pid = "\(getpid())\n"
        _ = pid.withCString { write(fd, $0, strlen($0)) }
        self.fd = fd
        return true
    }

    func release() {
        guard fd >= 0 else { return }
        flock(fd, LOCK_UN)
        close(fd)
        fd = -1
    }

    /// 누군가 잠금을 잡고 있는지(잡아 보고 바로 푼다).
    static func isHeld(at url: URL = InstanceLock.defaultURL) -> Bool {
        let fd = open(url.path, O_RDONLY | O_CLOEXEC)
        guard fd >= 0 else { return false }   // 파일이 없으면 데몬이 돈 적이 없다
        defer { close(fd) }
        if flock(fd, LOCK_EX | LOCK_NB) == 0 {
            flock(fd, LOCK_UN)
            return false
        }
        return true
    }

    /// 잠금을 잡고 있는 데몬의 PID(잠금 파일에 적어 둔 값). 데몬이 없으면 nil.
    static func holderPID(at url: URL = InstanceLock.defaultURL) -> pid_t? {
        guard isHeld(at: url),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    deinit { release() }
}

/// `sizer add` 로 넣은 파일의 표식. 데몬이 변환을 마치면 이것을 보고 출력 폴더를 열지 정한다
/// (macOS 에서 드롭 타겟으로 넣은 파일만 출력 폴더를 여는 것과 같다).
enum AddedMarks {
    static var directory: URL { Paths.runtimeDir.appendingPathComponent("added", isDirectory: true) }

    static func mark(_ fileName: String, in dir: URL = AddedMarks.directory) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        _ = FileManager.default.createFile(atPath: dir.appendingPathComponent(fileName).path, contents: nil)
    }

    /// 표식이 있으면 지우고 true.
    static func take(_ fileName: String, in dir: URL = AddedMarks.directory) -> Bool {
        let url = dir.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        try? FileManager.default.removeItem(at: url)
        return true
    }
}
