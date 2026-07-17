import SwiftUI

struct ImageSettingsView: View {
    @EnvironmentObject var settings: AppSettings

    private let sizeOptions: [Int] = [0, 1280, 1920, 2560, 3840]

    var body: some View {
        Form {
            Section {
                Toggle("이미지 캡처도 변환", isOn: $settings.imageConversionEnabled)
                Text("드롭 폴더에 들어온 스크린샷·이미지를 고화질 저용량으로 변환합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("포맷") {
                Picker("출력 포맷", selection: $settings.imageFormat) {
                    ForEach(ImageFormat.allCases) { fmt in
                        Text(fmt.label).tag(fmt)
                    }
                }

                VStack(alignment: .leading) {
                    HStack {
                        Text("품질")
                        Slider(value: $settings.imageQuality, in: 0.3...1.0, step: 0.05)
                        Text("\(Int(settings.imageQuality * 100))%")
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                    Text("높을수록 고화질·큰 용량. PNG는 무손실이라 품질이 적용되지 않습니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .disabled(!settings.imageFormat.usesQuality)

                Picker("최대 크기(장변, px)", selection: $settings.imageMaxLongEdge) {
                    ForEach(sizeOptions, id: \.self) { size in
                        Text(size == 0 ? "원본 유지" : "\(size)").tag(size)
                    }
                }
            }
            .disabled(!settings.imageConversionEnabled)
        }
        .formStyle(.grouped)
    }
}
