import SwiftUI

struct TrimmingSettingsView: View {
    @EnvironmentObject var settings: AppSettings

    private var sensitivityBinding: Binding<SensitivityPreset> {
        Binding(get: { settings.sensitivity }, set: { settings.applySensitivityPreset($0) })
    }

    var body: some View {
        Form {
            Picker("정지 구간 처리", selection: $settings.stillMode) {
                ForEach(StillMode.allCases) { mode in
                    Text(mode.isBeta ? "\(mode.label) · Beta" : mode.label).tag(mode)
                }
            }
            Text(modeHelp)
                .font(.caption).foregroundStyle(.secondary)

            if settings.stillMode != .off {
                Section("감지") {
                    Picker("민감도 프리셋", selection: sensitivityBinding) {
                        ForEach(SensitivityPreset.allCases) { Text($0.label).tag($0) }
                    }
                    labeledSlider("정지 판단 민감도(dB)", $settings.stillNoiseDb, -70...(-30), 1,
                                  fmt: { "\(Int($0))dB" }, hint: "0에 가까울수록 공격적")
                    labeledSlider("최소 정지 길이(초)", $settings.stillMinDuration, 0.5...5, 0.5,
                                  fmt: { String(format: "%.1f", $0) })
                    Toggle("적응형 임계값(노이즈 콘텐츠)", isOn: $settings.adaptiveThreshold)
                    Text("노이즈가 있는 영상에서 정지 구간을 놓치지 않도록 임계값을 안전 범위 내에서 자동 완화합니다. 깨끗한 화면 녹화에는 영향 없음.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if settings.stillMode == .trim {
                Section("잘라내기") {
                    labeledSlider("컷 병합 간격(초)", $settings.mergeGapMax, 0...2, 0.1,
                                  fmt: { String(format: "%.1f", $0) }, hint: "이 이하의 짧은 정지는 이어붙임")
                    labeledSlider("최소 유지 길이(초)", $settings.minKeep, 0...2, 0.1,
                                  fmt: { String(format: "%.1f", $0) }, hint: "이보다 짧은 조각은 버림")
                    labeledSlider("컷 여유(패딩, 초)", $settings.pad, 0...1, 0.05,
                                  fmt: { String(format: "%.2f", $0) })
                    Toggle("부드러운 전환(오디오 페이드 증가)", isOn: $settings.smoothTransitions)
                    labeledSlider("안전장치: 최소 유지 비율", $settings.minKeepRatio, 0...0.2, 0.01,
                                  fmt: { String(format: "%.2f", $0) },
                                  hint: "남는 길이가 원본의 이 비율 미만이면 취소")
                }
            }

            if settings.stillMode == .fastForward {
                Section("빨리감기 (Beta)") {
                    Text("저모션(대기·진행바 등) 구간을 잘라내지 않고 배속 재생합니다. 감지 정확도를 개선 중인 Beta 기능입니다.")
                        .font(.caption).foregroundStyle(.secondary)
                    Picker("배속", selection: $settings.ffSpeed) {
                        Text("2×").tag(2); Text("4×").tag(4); Text("8×").tag(8)
                    }
                    labeledSlider("최소 배속 구간 길이(초)", $settings.ffMinDuration, 1...8, 0.5,
                                  fmt: { String(format: "%.1f", $0) }, hint: "이 길이 이상 저모션 구간만 배속")
                    Toggle("배속 구간 오디오 음소거", isOn: $settings.ffMuteAudio)
                    Toggle("배속 배지 표시(»N×)", isOn: $settings.ffBadge)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var modeHelp: String {
        switch settings.stillMode {
        case .off: return "정지/저모션 구간을 그대로 둡니다."
        case .trim: return "정지 구간을 잘라내 이어붙입니다."
        case .fastForward: return "저모션 구간을 배속 재생해 지루함을 줄이되 맥락은 유지합니다."
        }
    }

    @ViewBuilder
    private func labeledSlider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>,
                              _ step: Double, fmt: @escaping (Double) -> String, hint: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Slider(value: value, in: range, step: step)
                Text(fmt(value.wrappedValue)).monospacedDigit().frame(width: 52, alignment: .trailing)
            }
            if let hint {
                Text(hint).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
