import Foundation

/// Finder에서 드롭된 파일을 드롭 폴더로 복사하는 순수 로직(테스트 가능).
enum DropIngest {

    /// 지원(변환 가능) 파일만 추림. 이미지는 imageEnabled일 때만 포함.
    static func supportedURLs(_ urls: [URL], imageEnabled: Bool) -> [URL] {
        urls.filter { url in
            let ext = url.pathExtension.lowercased()
            if ConversionConfig.videoExtensions.contains(ext) { return true }
            if imageEnabled && ConversionConfig.imageExtensions.contains(ext) { return true }
            return false
        }
    }

    /// 대상 폴더로 복사(이름 충돌 시 번호 부여). 복사에 성공한 대상 URL 목록 반환.
    @discardableResult
    static func copy(_ urls: [URL], to dropFolder: URL) -> [URL] {
        let fm = FileManager.default
        try? fm.createDirectory(at: dropFolder, withIntermediateDirectories: true)
        var copied: [URL] = []
        for src in urls {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: src.path, isDirectory: &isDir), !isDir.boolValue else { continue }
            let dest = uniqueDestination(for: src, in: dropFolder)
            do {
                try fm.copyItem(at: src, to: dest)
                copied.append(dest)
                AppLogger.info("드롭 수집: \(src.lastPathComponent) → \(dest.lastPathComponent)")
            } catch {
                AppLogger.warn("드롭 복사 실패: \(src.lastPathComponent) — \(error.localizedDescription)")
            }
        }
        return copied
    }

    static func uniqueDestination(for src: URL, in folder: URL) -> URL {
        let fm = FileManager.default
        var dest = folder.appendingPathComponent(src.lastPathComponent)
        let stem = src.deletingPathExtension().lastPathComponent
        let ext = src.pathExtension
        var counter = 1
        while fm.fileExists(atPath: dest.path) {
            let name = ext.isEmpty ? "\(stem)_\(counter)" : "\(stem)_\(counter).\(ext)"
            dest = folder.appendingPathComponent(name)
            counter += 1
        }
        return dest
    }
}
