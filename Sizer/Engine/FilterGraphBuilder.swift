import Foundation

/// ffmpeg 인자 배열을 조립한다(실행파일 경로 제외, "-y" 부터 출력경로까지).
/// 유지구간이 있으면 trim/atrim + concat + scale, 없으면 단순 scale.
enum FilterGraphBuilder {

    /// 장변을 maxLongEdge 이하로 축소(방향 무관, 홀수는 -2로 짝수 보정), 원본이 작으면 유지.
    static func scaleFilter(maxLongEdge: Int) -> String {
        let m = maxLongEdge
        return "scale='if(gt(iw,ih),min(\(m),iw),-2)':'if(gt(iw,ih),-2,min(\(m),ih))'"
    }

    static func build(src: URL, dst: URL, config: ConversionConfig,
                      keepSegments: [Segment]?, hasAudio: Bool) -> [String] {
        let scale = scaleFilter(maxLongEdge: config.maxLongEdge)
        var args: [String] = ["-y", "-i", src.path]

        if let segments = keepSegments, !segments.isEmpty {
            // 경계 declick용 오디오 미세 페이드(부드러움). smoothTransitions면 더 길게.
            let fade = config.trimOptions.smoothTransitions ? 0.04 : 0.010

            var parts: [String] = []
            var vLabels: [String] = []
            var aLabels: [String] = []

            for (i, seg) in segments.enumerated() {
                parts.append("[0:v]trim=\(f(seg.start)):\(f(seg.end)),setpts=PTS-STARTPTS[v\(i)]")
                vLabels.append("[v\(i)]")
                if hasAudio {
                    let dur = seg.duration
                    let outStart = max(0, dur - fade)
                    parts.append(
                        "[0:a]atrim=\(f(seg.start)):\(f(seg.end)),asetpts=PTS-STARTPTS," +
                        "afade=t=in:st=0:d=\(f(fade)),afade=t=out:st=\(f(outStart)):d=\(f(fade))[a\(i)]"
                    )
                    aLabels.append("[a\(i)]")
                }
            }

            let n = segments.count
            if hasAudio {
                let inputs = zip(vLabels, aLabels).map { $0 + $1 }.joined()
                parts.append("\(inputs)concat=n=\(n):v=1:a=1[vc][aout]")
            } else {
                parts.append("\(vLabels.joined())concat=n=\(n):v=1:a=0[vc]")
            }
            parts.append("[vc]\(scale)[vout]")

            args += ["-filter_complex", parts.joined(separator: ";"), "-map", "[vout]"]
            if hasAudio { args += ["-map", "[aout]"] }
        } else {
            args += ["-vf", scale]
        }

        // 코덱
        switch config.codec {
        case .h264, .h265:
            args += ["-c:v", config.codec.rawValue, "-crf", String(config.crf),
                     "-preset", config.preset, "-pix_fmt", "yuv420p"]
        case .h264vt, .h265vt:
            // 하드웨어 인코더는 CRF 미지원 → CRF를 품질(q:v, 0~100 높을수록 고품질)로 근사.
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

    private static func f(_ v: Double) -> String { String(format: "%.3f", v) }
}
