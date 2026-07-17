import Foundation

/// 한 번의 변환 잡이 필요로 하는 설정의 불변 스냅샷.
/// 코디네이터(MainActor)가 AppSettings로부터 만들어 백그라운드 엔진에 넘긴다.
struct ConversionConfig {
    var dropFolder: URL
    var outputFolder: URL
    var processedFolder: URL
    var failedFolder: URL

    var codec: VideoCodec
    var crf: Int
    var preset: String
    var maxLongEdge: Int
    var audioBitrate: String
    var outputSuffix: String
    var outputExt: String = ".mp4"
    var outputContainer: String = "mp4"

    var trimStill: Bool
    var trimOptions: TrimOptions

    // 이미지(캡처) 변환
    var imageEnabled: Bool
    var imageFormat: ImageFormat
    var imageQuality: Double        // 0.0~1.0 (손실 포맷)
    var imageMaxLongEdge: Int       // 0 = 원본 크기 유지

    var notificationsEnabled: Bool

    /// 처리 대상 영상 확장자.
    static let videoExtensions: Set<String> = [
        "mp4", "mov", "mkv", "avi", "m4v", "webm",
        "flv", "wmv", "mpg", "mpeg", "3gp", "ts", "mts",
    ]

    /// 처리 대상 이미지 확장자.
    static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "heic", "heif", "tiff", "tif", "bmp", "gif",
    ]
}
