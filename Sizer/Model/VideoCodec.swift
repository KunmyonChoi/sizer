import Foundation

/// 지원 비디오 코덱. libx264/x265는 CRF 기반, videotoolbox는 하드웨어 품질(q) 기반.
enum VideoCodec: String, CaseIterable, Identifiable {
    case h264 = "libx264"
    case h265 = "libx265"
    case h264vt = "h264_videotoolbox"
    case h265vt = "hevc_videotoolbox"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .h264:   return "H.264 (libx264, SNS 최대 호환)"
        case .h265:   return "H.265 (libx265, 더 작은 용량)"
        case .h264vt: return "H.264 (VideoToolbox, 하드웨어·빠름)"
        case .h265vt: return "H.265 (VideoToolbox, 하드웨어·빠름)"
        }
    }

    /// CRF(품질) 인자를 쓰는 소프트웨어 인코더인지.
    var usesCRF: Bool {
        self == .h264 || self == .h265
    }
}
