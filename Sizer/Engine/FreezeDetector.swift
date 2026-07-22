import Foundation

/// ffmpeg freezedetect로 정지 구간을, scdet/select로 장면 전환을 감지.
/// 정확도 개선(리서치 검증):
///  - 감지를 저해상도 프록시(다운스케일+약한 블러)에서 수행 → 속도↑, 노이즈 강건성↑(깨끗한 콘텐츠 무회귀).
///  - 장면 전환 정보를 SegmentPlanner의 병합 가드로 사용한다.
///  - 적응형 임계값: 프록시 노이즈 floor로 '노이즈 있는 콘텐츠'를 판별해 검증된 안전 임계값(-50dB)까지만 느슨하게.
enum FreezeDetector {

    /// 감지용 저해상도 프록시. 블러는 노이즈 플로어를 낮춰 freeze 감지를 돕는다(과블러 금지 — 검증).
    static let freezeProxy = "scale=iw/4:ih/4,boxblur=2,"
    /// 장면 전환용 프록시(블러 없음 — 컷 민감도 유지).
    static let sceneProxy = "scale=iw/4:ih/4,"
    /// 프록시 mafd가 이 값을 넘으면 '노이즈 있는' 콘텐츠로 보고 적응형 임계값을 적용.
    static let noiseFloorTrigger = 0.03
    /// 노이즈 콘텐츠에 허용하는 가장 느슨한 임계값(dB). 실측상 과검출 없이 안전한 상한.
    static let adaptiveLooseDb = -50.0

    /// 정지(움직임 없는) 구간 [(start,end)] 을 찾는다.
    static func detectFreezes(url: URL, duration: Double, options: TrimOptions) -> [Segment] {
        guard let ffmpeg = FFmpeg.ffmpegURL else { return [] }
        let vf = freezeProxy + "freezedetect=n=\(options.noiseArgument):d=\(fmt(options.minStillDuration))"
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
        let vf = sceneProxy + "select='gt(scene\\,\(threshold))',metadata=print:file=-"
        let r = FFmpeg.run(ffmpeg, [
            "-hide_banner", "-i", url.path,
            "-vf", vf, "-an", "-f", "null", "-",
        ])
        let text = r.stdout + r.stderr
        return doubles(in: text, pattern: #"pts_time:([0-9.]+)"#)
    }

    // MARK: 적응형 임계값

    /// 앞부분 표본에서 프록시 mafd의 노이즈 플로어(중앙값)를 추정. 실패 시 nil.
    static func noiseFloor(url: URL, sampleSeconds: Double = 45) -> Double? {
        guard let ffmpeg = FFmpeg.ffmpegURL else { return nil }
        let r = FFmpeg.run(ffmpeg, [
            "-hide_banner", "-t", fmt(sampleSeconds), "-i", url.path,
            "-vf", freezeProxy + "scdet=threshold=0,metadata=print:file=-",
            "-an", "-f", "null", "-",
        ])
        let text = r.stdout + r.stderr
        let mafds = doubles(in: text, pattern: #"lavfi\.scd\.mafd=([0-9.]+)"#)
        return median(mafds)
    }

    /// 노이즈 floor로 freezedetect 임계값(dB)을 조정. 깨끗하면 그대로, 노이즈면 -50dB까지만 느슨하게(순수·테스트용).
    static func adaptiveNoiseDb(base: Double, floorMafd: Double) -> Double {
        guard floorMafd > noiseFloorTrigger else { return base }   // 깨끗한 콘텐츠 → 변경 없음
        return max(base, adaptiveLooseDb)                          // 노이즈 → 안전 상한까지 느슨하게(이미 더 느슨하면 유지)
    }

    static func median(_ xs: [Double]) -> Double? {
        guard !xs.isEmpty else { return nil }
        let s = xs.sorted()
        let n = s.count
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
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
