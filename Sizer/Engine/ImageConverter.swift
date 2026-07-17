import Foundation
import ImageIO
import CoreGraphics

/// ImageIO 기반 이미지 변환(고화질 저용량). 선택적 다운스케일 + 포맷/품질 지정.
enum ImageConverter {
    struct Result {
        let success: Bool
        let error: String?
    }

    static func convert(src: URL, dst: URL, format: ImageFormat,
                        quality: Double, maxLongEdge: Int) -> Result {
        guard let source = CGImageSourceCreateWithURL(src as CFURL, nil) else {
            return Result(success: false, error: "이미지 열기 실패")
        }

        // 원본 픽셀 크기 확인(업스케일 방지)
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let pw = (props?[kCGImagePropertyPixelWidth] as? Int) ?? 0
        let ph = (props?[kCGImagePropertyPixelHeight] as? Int) ?? 0
        let longEdge = max(pw, ph)

        let cgImage: CGImage?
        if maxLongEdge > 0, longEdge > maxLongEdge {
            let opts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxLongEdge,
            ]
            cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary)
        } else {
            cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        }

        guard let image = cgImage else {
            return Result(success: false, error: "이미지 디코드 실패")
        }

        guard let dest = CGImageDestinationCreateWithURL(
            dst as CFURL, format.utTypeIdentifier as CFString, 1, nil) else {
            return Result(success: false, error: "\(format.label) 인코더 생성 실패")
        }

        var destProps: [CFString: Any] = [:]
        if format.usesQuality {
            destProps[kCGImageDestinationLossyCompressionQuality] = max(0.0, min(1.0, quality))
        }
        CGImageDestinationAddImage(dest, image, destProps as CFDictionary)

        guard CGImageDestinationFinalize(dest) else {
            return Result(success: false, error: "\(format.label) 인코딩 실패")
        }
        return Result(success: true, error: nil)
    }
}
