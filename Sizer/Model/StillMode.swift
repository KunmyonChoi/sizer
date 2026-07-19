import Foundation

/// 정지/저모션 구간 처리 모드.
enum StillMode: String, CaseIterable, Identifiable {
    case off           // 아무것도 안 함
    case trim          // 잘라내기
    case fastForward   // 빨리감기(배속) — Beta

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off: return "끔"
        case .trim: return "잘라내기"
        case .fastForward: return "빨리감기"
        }
    }

    /// Beta 여부(안정화되면 false).
    var isBeta: Bool {
        self == .fastForward && !FeatureFlags.fastForwardStable
    }
}

/// 구간 + 배속. speed=1은 정상, >1은 빨리감기.
struct SpeedSegment: Equatable {
    var start: Double
    var end: Double
    var speed: Double

    init(_ start: Double, _ end: Double, speed: Double = 1) {
        self.start = start
        self.end = end
        self.speed = speed
    }

    var duration: Double { max(0, end - start) }
    var outputDuration: Double { duration / max(0.0001, speed) }
    var isFast: Bool { speed > 1.0001 }
}

extension Array where Element == SpeedSegment {
    var totalOutputDuration: Double { reduce(0) { $0 + $1.outputDuration } }
}

/// 기능 플래그.
enum FeatureFlags {
    /// 빨리감기(FF)가 정식 기능으로 안정화되었는지. false면 UI에 Beta 배지 표시.
    static let fastForwardStable = false
}
