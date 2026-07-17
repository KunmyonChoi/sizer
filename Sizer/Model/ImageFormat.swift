import Foundation

/// 이미지 출력 포맷. ImageIO(CGImageDestination)로 인코딩.
enum ImageFormat: String, CaseIterable, Identifiable {
    case avif
    case heic
    case jpeg
    case png

    var id: String { rawValue }

    var label: String {
        switch self {
        case .avif: return "AVIF (고효율)"
        case .heic: return "HEIC (Apple 고압축)"
        case .jpeg: return "JPEG (범용)"
        case .png: return "PNG (무손실)"
        }
    }

    var fileExtension: String {
        switch self {
        case .avif: return "avif"
        case .heic: return "heic"
        case .jpeg: return "jpg"
        case .png:  return "png"
        }
    }

    /// CGImageDestination용 UTI.
    var utTypeIdentifier: String {
        switch self {
        case .avif: return "public.avif"
        case .heic: return "public.heic"
        case .jpeg: return "public.jpeg"
        case .png:  return "public.png"
        }
    }

    /// 품질(손실 압축) 파라미터를 쓰는 포맷인지. PNG는 무손실.
    var usesQuality: Bool { self != .png }
}
