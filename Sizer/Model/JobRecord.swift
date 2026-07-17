import Foundation

/// 감시/변환 상태.
enum WatchStatus: Equatable {
    case idle
    case watching
    case paused
    case converting(String)   // 현재 변환 중인 파일명

    var label: String {
        switch self {
        case .idle: return "대기"
        case .watching: return "감시 중"
        case .paused: return "일시정지"
        case .converting(let name): return "변환 중: \(name)"
        }
    }
}

/// 변환 대상 종류.
enum MediaKind {
    case video
    case image
}

/// 최근 변환 결과 한 건.
struct JobRecord: Identifiable, Equatable {
    let id = UUID()
    let sourceName: String
    let outputName: String?
    let outputURL: URL?      // 성공 시 결과 파일 경로(클릭 재생/열기용)
    let kind: MediaKind
    let success: Bool
    let detail: String      // 예: "124.5MB → 2.2MB (98% 절감) · 정지 88s 제거"
    let date: Date

    static func == (lhs: JobRecord, rhs: JobRecord) -> Bool { lhs.id == rhs.id }
}
