import Foundation

/// ffmpeg freezedetect로 정지 구간을, scdet/select로 장면 전환을 감지.
/// 정확도 개선: 장면 전환 정보를 SegmentPlanner의 병합 가드로 사용한다.
enum FreezeDetector {

    /// 정지(움직임 없는) 구간 [(start,end)] 을 찾는다.
    static func detectFreezes(url: URL, duration: Double, options: TrimOptions) -> [Segment] {
        guard let ffmpeg = FFmpeg.ffmpegURL else { return [] }
        let vf = "freezedetect=n=\(options.noiseArgument):d=\(fmt(options.minStillDuration))"
        let r = FFmpeg.run(ffmpeg, [
            "-hide_banner", "-i", url.path,
            "-vf", vf, "-an", "-f", "null", "-",
        ])
        let text = r.stderr + r.stdout
        let starts = doubles(in: text, pattern: #"freeze_start[:=]\s*([0-9.]+)"#)
        let ends = doubles(in: text, pattern: #"freeze_end[:=]\s*([0-9.]+)"#)

        var intervals: [Segment] = []
        for (i, s) in starts.enumerated() {
            let e = i < ends.count ? ends[i] : (duration > 0 ? duration : s)
            if e > s {
                let end = duration > 0 ? min(duration, e) : e
                intervals.append(Segment(max(0, s), end))
            }
        }
        return intervals
    }

    /// 장면 전환 타임스탬프. 실패해도 빈 배열(병합 가드가 비활성일 뿐 해롭지 않음).
    static func detectSceneChanges(url: URL, threshold: Double = 0.4) -> [Double] {
        guard let ffmpeg = FFmpeg.ffmpegURL else { return [] }
        // scene 점수가 threshold를 넘는 프레임을 선택하고 metadata로 pts_time을 출력.
        let vf = "select='gt(scene\\,\(threshold))',metadata=print:file=-"
        let r = FFmpeg.run(ffmpeg, [
            "-hide_banner", "-i", url.path,
            "-vf", vf, "-an", "-f", "null", "-",
        ])
        let text = r.stdout + r.stderr
        return doubles(in: text, pattern: #"pts_time:([0-9.]+)"#)
    }

    // MARK: helpers

    private static func doubles(in text: String, pattern: String) -> [Double] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap {
            guard $0.numberOfRanges > 1 else { return nil }
            return Double(ns.substring(with: $0.range(at: 1)))
        }
    }

    private static func fmt(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.2f", v)
    }
}
