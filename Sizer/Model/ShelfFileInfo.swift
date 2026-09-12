import Foundation

/// 셸프 항목의 파일 정보(호버·정보 보기 팝오버용). 읽기/포맷팅은 순수 로직 — 단위 테스트 대상.
struct ShelfFileInfo: Equatable {
    let path: String      // 파일명을 포함한 절대경로
    let size: Int64?      // 바이트(폴더면 nil)
    let created: Date?
    let modified: Date?

    var name: String { (path as NSString).lastPathComponent }

    /// 파일 시스템에서 읽는다. 파일이 없으면(이동·삭제됨) nil.
    static func read(_ url: URL) -> ShelfFileInfo? {
        let path = url.standardizedFileURL.path
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
        let isDir = (attrs[.type] as? FileAttributeType) == .typeDirectory
        return ShelfFileInfo(
            path: path,
            size: isDir ? nil : (attrs[.size] as? NSNumber)?.int64Value,
            created: attrs[.creationDate] as? Date,
            modified: attrs[.modificationDate] as? Date
        )
    }

    /// 팝오버에 표시할 (라벨, 값) 행. 파일이 없으면 경로와 안내만.
    static func rows(for url: URL, timeZone: TimeZone = .current) -> [(label: String, value: String)] {
        guard let info = read(url) else {
            return [("경로", url.standardizedFileURL.path), ("상태", "파일을 찾을 수 없음(이동 또는 삭제됨)")]
        }
        var rows: [(label: String, value: String)] = [("경로", info.path)]
        if let size = info.size { rows.append(("크기", formatSize(size))) }
        if let created = info.created { rows.append(("생성일", formatDate(created, timeZone: timeZone))) }
        if let modified = info.modified { rows.append(("수정일", formatDate(modified, timeZone: timeZone))) }
        return rows
    }

    /// "12.3 MB (12,345,678바이트)" — Finder 정보 가져오기와 같은 표기.
    static func formatSize(_ bytes: Int64) -> String {
        let human = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        let grouped = NumberFormatter()
        grouped.numberStyle = .decimal
        grouped.locale = Locale(identifier: "en_US_POSIX")
        grouped.usesGroupingSeparator = true
        grouped.groupingSeparator = ","
        let exact = grouped.string(from: NSNumber(value: bytes)) ?? "\(bytes)"
        return "\(human) (\(exact)바이트)"
    }

    /// "2026-09-11 14:03:22"(초 단위, 지정 시간대).
    static func formatDate(_ date: Date, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: date)
    }

    /// 경로 이름 복사용 텍스트: 파일명을 포함한 절대경로, 여러 개면 줄바꿈으로 구분.
    static func pathsText(_ urls: [URL]) -> String {
        urls.map { $0.standardizedFileURL.path }.joined(separator: "\n")
    }
}
