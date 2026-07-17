import Foundation

/// freeze 구간으로부터 실제로 인코딩할 "유지(움직임) 구간"을 계산하는 순수 로직.
///
/// 개선 포인트(기존 watch_convert.py 대비):
///  - mergeShortGaps: 짧은 정지를 사이에 둔 인접 유지구간을 병합해 마이크로컷 제거(부드러움).
///  - dropShortSegments: 감지 노이즈로 생긴 아주 짧은 유지 조각 제거(정확도).
///  - pad: 유지구간 앞뒤 여유로 시작 프레임 잘림 방지 + 자연스러운 컷(부드러움).
///  - sceneChanges 가드: 실제 장면 전환을 가로질러 병합하지 않음(정확도).
///  - 안전장치: 너무 많이 잘리거나(비율) 사실상 안 잘리면 트리밍 취소.
enum SegmentPlanner {

    /// 정지 구간의 여집합 = 유지할 움직임 구간.
    static func keepSegments(freezes: [Segment], duration: Double) -> [Segment] {
        guard duration > 0 else { return [] }
        var keep: [Segment] = []
        var cursor = 0.0
        for f in freezes.sorted(by: { $0.start < $1.start }) {
            let s = max(0, f.start)
            let e = min(duration, f.end)
            if s > cursor {
                keep.append(Segment(cursor, s))
            }
            cursor = max(cursor, e)
        }
        if duration - cursor > 0.05 {
            keep.append(Segment(cursor, duration))
        }
        return keep
    }

    /// 인접 유지구간 사이의 정지 길이가 mergeGapMax 이하이고, 그 사이에 장면 전환이 없으면 병합.
    static func mergeShortGaps(_ segments: [Segment],
                              mergeGapMax: Double,
                              sceneChanges: [Double] = []) -> [Segment] {
        guard let first = segments.first else { return [] }
        var result: [Segment] = [first]
        for seg in segments.dropFirst() {
            let gap = seg.start - result[result.count - 1].end
            let sceneInGap = sceneChanges.contains { $0 > result[result.count - 1].end && $0 < seg.start }
            if gap <= mergeGapMax && !sceneInGap {
                result[result.count - 1].end = seg.end
            } else {
                result.append(seg)
            }
        }
        return result
    }

    /// minKeep 미만 길이의 유지구간 제거.
    static func dropShortSegments(_ segments: [Segment], minKeep: Double) -> [Segment] {
        segments.filter { $0.duration >= minKeep }
    }

    /// 각 유지구간을 앞뒤로 pad 만큼 확장 후 겹침 병합, [0, duration]로 클램프.
    static func pad(_ segments: [Segment], by pad: Double, duration: Double) -> [Segment] {
        guard pad >= 0 else { return segments }
        let expanded = segments.map {
            Segment(max(0, $0.start - pad), min(duration, $0.end + pad))
        }.sorted { $0.start < $1.start }

        var merged: [Segment] = []
        for seg in expanded {
            if var last = merged.last, seg.start <= last.end {
                last.end = Swift.max(last.end, seg.end)
                merged[merged.count - 1] = last
            } else {
                merged.append(seg)
            }
        }
        return merged
    }

    /// 전체 파이프라인. 트리밍할 유지구간을 반환하거나, 트리밍을 하지 말아야 하면 nil.
    static func plan(freezes: [Segment],
                     duration: Double,
                     options: TrimOptions,
                     sceneChanges: [Double] = []) -> [Segment]? {
        guard duration > 0, !freezes.isEmpty else { return nil }

        let keep0 = keepSegments(freezes: freezes, duration: duration)
        let keep1 = mergeShortGaps(keep0, mergeGapMax: options.mergeGapMax, sceneChanges: sceneChanges)
        let keep2 = dropShortSegments(keep1, minKeep: options.minKeep)
        let keep3 = pad(keep2, by: options.pad, duration: duration)

        guard !keep3.isEmpty else { return nil }

        let kept = keep3.totalDuration
        // 안전장치: 너무 많이 잘렸으면(움직임이 거의 없는 영상) 원본 그대로.
        guard kept >= duration * options.minKeepRatio else { return nil }
        // 사실상 안 잘렸으면(제거량이 미미) 트리밍 생략.
        let removed = duration - kept
        guard removed >= 0.5 else { return nil }

        return keep3
    }
}
