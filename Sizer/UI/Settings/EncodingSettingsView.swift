import SwiftUI

struct EncodingSettingsView: View {
    @EnvironmentObject var settings: AppSettings

    private let presets = [
        "ultrafast", "superfast", "veryfast", "faster", "fast",
        "medium", "slow", "slower", "veryslow"
    ]
    private let longEdgeOptions = [1280, 1920, 2560, 3840]

    var body: some View {
        Form {
            Section {
                Picker("코덱", selection: $settings.videoCodec) {
                    ForEach(VideoCodec.allCases) { codec in
                        Text(codec.label).tag(codec)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("CRF")
                        Slider(
                            value: Binding(
                                get: { Double(settings.crf) },
                                set: { settings.crf = Int($0) }
                            ),
                            in: 18...32,
                            step: 1
                        )
                        Text("\(settings.crf)")
                            .monospacedDigit()
                    }
                    Text("낮을수록 고화질·큰 용량")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .disabled(!settings.videoCodec.usesCRF)

                Picker("Preset", selection: $settings.preset) {
                    ForEach(presets, id: \.self) { preset in
                        Text(preset).tag(preset)
                    }
                }
                .disabled(!settings.videoCodec.usesCRF)

                Picker("장변 최대(px)", selection: $settings.maxLongEdge) {
                    ForEach(longEdgeOptions, id: \.self) { value in
                        Text("\(value)").tag(value)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    TextField("오디오 비트레이트", text: $settings.audioBitrate)
                    Text("예: 128k")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    TextField("출력 파일 접미사", text: $settings.outputSuffix)
                    Text("예: _resize → 원본이름_resize.mp4")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}
