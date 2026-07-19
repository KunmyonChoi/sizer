import Foundation

/// ffmpeg 인자 배열을 조립한다(실행파일 경로 제외, "-y" 부터 출력경로까지).
/// 세그먼트가 있으면 구간별 (배속) trim/atrim + concat + scale, 없으면 단순 scale.
enum FilterGraphBuilder {

    /// 장변을 maxLongEdge 이하로 축소(방향 무관, 홀수는 -2로 짝수 보정), 원본이 작으면 유지.
    static func scaleFilter(maxLongEdge: Int) -> String {
        let m = maxLongEdge
        return "scale='if(gt(iw,ih),min(\(m),iw),-2)':'if(gt(iw,ih),-2,min(\(m),ih))'"
    }

    static func build(src: URL, dst: URL, config: ConversionConfig,
                      segments: [SpeedSegment]?, hasAudio: Bool, badgeURL: URL? = nil) -> [String] {
        let scale = scaleFilter(maxLongEdge: config.maxLongEdge)
        let useBadge = badgeURL != nil && (segments?.contains { $0.isFast } ?? false)
        var args: [String] = ["-y", "-i", src.path]
        if useBadge, let badgeURL { args += ["-i", badgeURL.path] }

        if let segments, !segments.isEmpty {
            let fade = config.trimOptions.smoothTransitions ? 0.04 : 0.010
            var parts: [String] = []
            var vLabels: [String] = []
            var aLabels: [String] = []
            var outCursor = 0.0
            var ffRanges: [(Double, Double)] = []   // 출력 타임라인 기준 FF 구간(배지용)

            for (i, seg) in segments.enumerated() {
                let fast = seg.isFast
                parts.append("[0:v]trim=\(f(seg.start)):\(f(seg.end)),setpts=(PTS-STARTPTS)/\(f(seg.speed))[v\(i)]")
                vLabels.append("[v\(i)]")

                if hasAudio {
                    var a = "[0:a]atrim=\(f(seg.start)):\(f(seg.end)),asetpts=PTS-STARTPTS"
                    if fast {
                        a += ",\(atempoChain(seg.speed))"
                        if config.ffMuteAudio { a += ",volume=0" }
                    } else {
                        let outEnd = max(0, seg.duration - fade)   // 경계 declick
                        a += ",afade=t=in:st=0:d=\(f(fade)),afade=t=out:st=\(f(outEnd)):d=\(f(fade))"
                    }
                    a += "[a\(i)]"
                    parts.append(a)
                    aLabels.append("[a\(i)]")
                }

                if fast { ffRanges.append((outCursor, outCursor + seg.outputDuration)) }
                outCursor += seg.outputDuration
            }

            let n = segments.count
            if hasAudio {
                let inputs = zip(vLabels, aLabels).map { $0 + $1 }.joined()
                parts.append("\(inputs)concat=n=\(n):v=1:a=1[vc][aout]")
            } else {
                parts.append("\(vLabels.joined())concat=n=\(n):v=1:a=0[vc]")
            }

            if useBadge, !ffRanges.isEmpty {
                parts.append("[vc]\(scale)[vs]")
                let enable = ffRanges.map { "between(t,\(f($0.0)),\(f($0.1)))" }.joined(separator: "+")
                parts.append("[vs][1:v]overlay=x=W-w-46:y=46:enable='\(enable)'[vout]")
            } else {
                parts.append("[vc]\(scale)[vout]")
            }

            args += ["-filter_complex", parts.joined(separator: ";"), "-map", "[vout]"]
            if hasAudio { args += ["-map", "[aout]"] }
        } else {
            args += ["-vf", scale]
        }

        switch config.codec {
        case .h264, .h265:
            args += ["-c:v", config.codec.rawValue, "-crf", String(config.crf),
                     "-preset", config.preset, "-pix_fmt", "yuv420p"]
        case .h264vt, .h265vt:
            let q = max(1, min(100, 100 - (config.crf - 18) * 4))
            args += ["-c:v", config.codec.rawValue, "-q:v", String(q), "-pix_fmt", "yuv420p"]
        }

        if hasAudio {
            args += ["-c:a", "aac", "-b:a", config.audioBitrate]
        } else {
            args += ["-an"]
        }
        args += ["-movflags", "+faststart", "-f", config.outputContainer, dst.path]
        return args
    }

    /// atempo는 인스턴스당 최대 2.0 → 2의 거듭제곱으로 분해(4×=2,2 / 8×=2,2,2).
    static func atempoChain(_ speed: Double) -> String {
        var remaining = speed
        var parts: [String] = []
        while remaining > 2.0 + 0.001 {
            parts.append("atempo=2.0")
            remaining /= 2.0
        }
        parts.append("atempo=\(f(remaining))")
        return parts.joined(separator: ",")
    }

    private static func f(_ v: Double) -> String { String(format: "%.3f", v) }
}
