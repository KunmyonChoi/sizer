import SwiftUI

struct TrimmingSettingsView: View {
    @EnvironmentObject var settings: AppSettings

    private var sensitivityBinding: Binding<SensitivityPreset> {
        Binding(
            get: { settings.sensitivity },
            set: { settings.applySensitivityPreset($0) }
        )
    }

    var body: some View {
        Form {
            Toggle("움직임 없는 구간 자동 제거", isOn: $settings.trimStill)

            Group {
                Picker("민감도 프리셋", selection: sensitivityBinding) {
                    ForEach(SensitivityPreset.allCases) { preset in
                        Text(preset.label).tag(preset)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("정지 판단 민감도(dB)")
                        Slider(value: $settings.stillNoiseDb, in: -70...(-30), step: 1)
                        Text("\(Int(settings.stillNoiseDb))dB")
                            .monospacedDigit()
                    }
                    Text("0에 가까울수록 공격적")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("최소 정지 길이(초)")
                    Slider(value: $settings.stillMinDuration, in: 0.5...5, step: 0.5)
                    Text(String(format: "%.1f", settings.stillMinDuration))
                        .monospacedDigit()
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("컷 병합 간격(초)")
                        Slider(value: $settings.mergeGapMax, in: 0...2, step: 0.1)
                        Text(String(format: "%.1f", settings.mergeGapMax))
                            .monospacedDigit()
                    }
                    Text("이 이하의 짧은 정지는 잘라내지 않고 이어붙임")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("최소 유지 길이(초)")
                        Slider(value: $settings.minKeep, in: 0...2, step: 0.1)
                        Text(String(format: "%.1f", settings.minKeep))
                            .monospacedDigit()
                    }
                    Text("이보다 짧은 조각은 버림")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("컷 여유(패딩, 초)")
                    Slider(value: $settings.pad, in: 0...1, step: 0.05)
                    Text(String(format: "%.2f", settings.pad))
                        .monospacedDigit()
                }

                Toggle("부드러운 전환(오디오 페이드 증가)", isOn: $settings.smoothTransitions)

                Section("고급") {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("안전장치: 최소 유지 비율")
                            Slider(value: $settings.minKeepRatio, in: 0...0.2, step: 0.01)
                            Text(String(format: "%.2f", settings.minKeepRatio))
                                .monospacedDigit()
                        }
                        Text("잘라낸 뒤 남는 길이가 원본의 이 비율 미만이면 트리밍 취소")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .disabled(!settings.trimStill)
        }
        .formStyle(.grouped)
    }
}
