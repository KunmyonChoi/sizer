// swift-tools-version:5.9
//
// Sizer Linux 빌드(SwiftPM). macOS 앱은 계속 XcodeGen(project.yml) + Xcode 로 빌드한다.
//
// 변환 엔진과 모델은 macOS 앱과 **같은 소스 파일**을 그대로 컴파일한다(Sizer/Engine, Sizer/Model 의 플랫폼
// 독립 파일). AppKit·ImageIO·FSEvents·UserNotifications 에 기대던 타입만 linux/Sources/Sizer 에 같은 이름으로
// 구현하므로, 엔진 로직을 고치면 두 플랫폼에 함께 반영된다.
import Foundation
import PackageDescription

/// 저장소 루트(".")를 경로로 쓰는 타깃이 sources 밖의 파일(README, macOS UI 등)을 "unhandled" 로
/// 경고하지 않도록, keep 에 들지 않는 항목을 모두 exclude 로 돌린다. 숨김 항목(.build, .git)은 SwiftPM 이 원래 무시한다.
func excluding(_ keep: [String]) -> [String] {
    let root = Context.packageDirectory
    func walk(_ relative: String) -> [String] {
        let dir = relative.isEmpty ? root : "\(root)/\(relative)"
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        return names.filter { !$0.hasPrefix(".") }.sorted().flatMap { name -> [String] in
            let path = relative.isEmpty ? name : "\(relative)/\(name)"
            if keep.contains(path) { return [] }
            if keep.contains(where: { $0.hasPrefix(path + "/") }) { return walk(path) }
            return [path]
        }
    }
    return walk("")
}

/// macOS 앱과 공유하는 플랫폼 독립 소스.
let sharedSources = [
    "Sizer/Engine/ConversionEngine.swift",
    "Sizer/Engine/DropIngest.swift",
    "Sizer/Engine/FFmpeg.swift",
    "Sizer/Engine/FilterGraphBuilder.swift",
    "Sizer/Engine/FreezeDetector.swift",
    "Sizer/Engine/Probe.swift",
    "Sizer/Engine/ProcessedCleaner.swift",
    "Sizer/Engine/SegmentPlanner.swift",
    "Sizer/Model/ConversionConfig.swift",
    "Sizer/Model/ImageFormat.swift",
    "Sizer/Model/JobRecord.swift",
    "Sizer/Model/Segment.swift",
    "Sizer/Model/StillMode.swift",
    "Sizer/Model/TrimOptions.swift",
    "Sizer/Model/VideoCodec.swift",
]

/// macOS 테스트 중 플랫폼 독립이라 Linux 에서도 그대로 도는 것.
let sharedTests = [
    "SizerTests/ConversionEngineIntegrationTests.swift",
    "SizerTests/ConversionEngineTests.swift",
    "SizerTests/DropIngestTests.swift",
    "SizerTests/FastForwardTests.swift",
    "SizerTests/FreezeDetectorTests.swift",
    "SizerTests/ProcessedCleanerTests.swift",
    "SizerTests/SegmentPlannerTests.swift",
]

let coreSources = sharedSources + ["linux/Sources/Sizer"]
let testSources = sharedTests + ["linux/Tests/SizerTests"]

let package = Package(
    name: "Sizer",
    products: [
        .executable(name: "sizer", targets: ["SizerCLI"]),
    ],
    targets: [
        // 공유 테스트가 macOS 와 똑같이 `@testable import Sizer` 로 쓰도록 모듈 이름을 Sizer 로 맞춘다.
        .target(
            name: "Sizer",
            path: ".",
            exclude: excluding(coreSources),
            sources: coreSources
        ),
        .executableTarget(
            name: "SizerCLI",
            dependencies: ["Sizer"],
            path: "linux/Sources/SizerCLI"
        ),
        .testTarget(
            name: "SizerTests",
            dependencies: ["Sizer"],
            path: ".",
            exclude: excluding(testSources),
            sources: testSources
        ),
    ]
)
