import Foundation

/// 정지 구간 트리밍 파라미터. 감지(freezedetect)와 후처리(병합/제거/패딩) 모두를 제어한다.
struct TrimOptions: Equatable {
    /// freezedetect 노이즈 임계값(dB). 0에 가까울수록 공격적, 낮을수록 엄격. 예: -50.0
    var noiseDb: Double = -50.0
    /// 이 시간(초) 이상 움직임이 없어야 정지로 판단(freezedetect d=).
    var minStillDuration: Double = 2.0
    /// 인접 유지구간 사이 정지 길이가 이 값 이하이면 병합(마이크로컷 제거) — 컷 부드러움.
    var mergeGapMax: Double = 0.5
    /// 이 길이 미만의 유지구간은 버린다(감지 노이즈로 생긴 조각 제거) — 정확도.
    var minKeep: Double = 0.3
    /// 각 유지구간 앞뒤에 주는 여유(초). 시작 프레임 잘림 방지 + 부드러움.
    var pad: Double = 0.15
    /// 잘라낸 뒤 남는 총 길이가 원본의 이 비율 미만이면 트리밍 취소(안전장치).
    var minKeepRatio: Double = 0.02
    /// concat 경계에 짧은 crossfade(xfade/acrossfade) 적용 — 부드러움(옵션).
    var smoothTransitions: Bool = false

    /// freezedetect 필터 인자 문자열의 noise 표현(예: "-50dB").
    var noiseArgument: String {
        // 정수면 정수로, 아니면 소수 한 자리로.
        if noiseDb == noiseDb.rounded() {
            return "\(Int(noiseDb))dB"
        }
        return String(format: "%.1fdB", noiseDb)
    }
}

/// 감지 민감도 프리셋. 각 프리셋이 TrimOptions의 감지/후처리 값을 함께 조정한다.
enum SensitivityPreset: String, CaseIterable, Identifiable {
    case aggressive   // 공격적: 살짝의 정지도 잘라냄
    case balanced     // 균형(기본): 기존 스크립트 근사값
    case conservative // 보수적: 확실한 정지만 잘라냄

    var id: String { rawValue }

    var label: String {
        switch self {
        case .aggressive: return "공격적"
        case .balanced: return "균형"
        case .conservative: return "보수적"
        }
    }

    /// 프리셋이 정의하는 감지 파라미터(noise, minStill, mergeGapMax). 사용자가 개별 조정하면 override됨.
    var detection: (noiseDb: Double, minStill: Double, mergeGapMax: Double) {
        switch self {
        case .aggressive:   return (-45.0, 1.0, 0.35)
        case .balanced:     return (-50.0, 2.0, 0.5)
        case .conservative: return (-58.0, 3.0, 0.7)
        }
    }
}
