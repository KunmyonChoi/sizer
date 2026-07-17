import Foundation

/// processed 폴더에서 지정 기간보다 오래된 파일을 삭제한다.
/// 기준 시각은 파일의 수정일(=processed로 이동된 시점, ConversionEngine이 이동 시 갱신).
enum ProcessedCleaner {

    /// olderThanDays 보다 오래된 정규 파일을 삭제하고 삭제 개수를 반환.
    @discardableResult
    static func clean(folder: URL, olderThanDays days: Int, now: Date = Date()) -> Int {
        guard days > 0 else { return 0 }
        let fm = FileManager.default
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)

        guard let items = try? fm.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var deleted = 0
        for url in items {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            guard let modified = values?.contentModificationDate, modified < cutoff else { continue }

            do {
                try fm.removeItem(at: url)
                deleted += 1
                AppLogger.info("오래된 원본 자동 삭제(processed): \(url.lastPathComponent)")
            } catch {
                AppLogger.warn("자동 삭제 실패: \(url.lastPathComponent) — \(error.localizedDescription)")
            }
        }
        return deleted
    }
}
