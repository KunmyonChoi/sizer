import Foundation

/// 시간 구간 [start, end] (초). freeze 구간과 유지(움직임) 구간 모두에 사용.
struct Segment: Equatable {
    var start: Double
    var end: Double

    var duration: Double { max(0, end - start) }

    init(_ start: Double, _ end: Double) {
        self.start = start
        self.end = end
    }
}

extension Array where Element == Segment {
    var totalDuration: Double { reduce(0) { $0 + $1.duration } }
}
