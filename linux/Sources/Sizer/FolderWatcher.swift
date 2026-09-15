import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// inotify 로 폴더를 감시한다(macOS 판은 FSEvents). 변경 시 onChange 를 감시 큐에서 호출.
/// 폴더 한 단계만 본다 — 코디네이터가 주기적 재스캔으로 놓친 이벤트를 보완한다.
final class FolderWatcher {
    private let path: String
    private let onChange: () -> Void
    private let queue = DispatchQueue(label: "com.dilly.sizer.fswatch")
    private var source: DispatchSourceRead?

    init(path: String, onChange: @escaping () -> Void) {
        self.path = path
        self.onChange = onChange
    }

    func start() {
        stop()
        let fd = inotify_init1(Int32(IN_NONBLOCK) | Int32(IN_CLOEXEC))
        guard fd >= 0 else {
            AppLogger.warn("폴더 감시 시작 실패(inotify_init1 errno \(errno)): \(path)")
            return
        }
        // 복사 완료(CLOSE_WRITE), 다른 곳에서 옮겨 옴(MOVED_TO), 새 항목(CREATE), 감시 폴더 자체의 삭제·이동.
        let mask = UInt32(IN_CLOSE_WRITE) | UInt32(IN_MOVED_TO) | UInt32(IN_CREATE)
            | UInt32(IN_DELETE_SELF) | UInt32(IN_MOVE_SELF)
        guard inotify_add_watch(fd, path, mask) >= 0 else {
            AppLogger.warn("폴더 감시 시작 실패(inotify_add_watch errno \(errno)): \(path)")
            close(fd)
            return
        }
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            // 쌓인 이벤트를 모두 비운다. 무엇이 바뀌었는지는 스캔이 판단하므로 내용은 보지 않는다.
            var buffer = [UInt8](repeating: 0, count: 8192)
            var changed = false
            while read(fd, &buffer, buffer.count) > 0 { changed = true }
            if changed { self?.onChange() }
        }
        source.setCancelHandler { close(fd) }
        self.source = source
        source.resume()
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    deinit { stop() }
}
