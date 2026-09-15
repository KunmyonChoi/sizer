# 기여 가이드 (Contributing)

Sizer에 관심 가져주셔서 감사합니다. 버그 리포트·기능 제안·PR 모두 환영합니다.

## 개발 환경

| 도구 | 용도 |
|------|------|
| macOS 13+ | 실행/빌드 대상 |
| Xcode 15+ | Swift 5 / SwiftUI 빌드 |
| [XcodeGen](https://github.com/yonyz/XcodeGen) (`brew install xcodegen`) | `project.yml` → `Sizer.xcodeproj` 생성 |
| ffmpeg (`brew install ffmpeg`) | 영상 변환 + 테스트 픽스처 생성 |

> `Sizer.xcodeproj`는 **생성물**이라 저장소에 포함되지 않습니다. 소스 오브 트루스는 `project.yml`입니다.

## 빌드 & 테스트

```bash
xcodegen generate                                                            # 프로젝트 생성
xcodebuild -project Sizer.xcodeproj -scheme Sizer -destination 'platform=macOS' build
xcodebuild -project Sizer.xcodeproj -scheme Sizer -destination 'platform=macOS' test
```

개인용 로컬 설치:

```bash
./scripts/install_local.sh     # Release 빌드 → ad-hoc 서명 → /Applications 설치
```

## Linux 빌드 & 테스트

Linux 판은 `Package.swift`(SwiftPM)로 빌드합니다. Ubuntu 24.04 + Swift 6.1 이 있으면 `swift test`,
없으면 Docker 로 같은 환경(`linux/Dockerfile`)에서 돌립니다.

```bash
swift test                            # 공유 엔진 테스트 + Linux 계층 테스트(ffmpeg 필요)
./scripts/build_linux.sh --docker     # Docker 안에서 테스트 → dist/ 에 .deb, .tar.gz
```

- `Sizer/Engine`·`Sizer/Model` 의 파일 중 `Package.swift` 의 `sharedSources` 에 든 것은 **두 플랫폼이 함께 컴파일**합니다.
  이 파일에는 AppKit·ImageIO 등 Apple 전용 프레임워크를 들이지 마세요(Foundation 만).
  플랫폼마다 달라야 하는 타입(`FolderWatcher`, `ImageConverter`, `Notifier` …)은 macOS 판은 `Sizer/`, Linux 판은
  `linux/Sources/Sizer/` 에 같은 이름·시그니처로 둡니다.
- 버전을 올릴 때는 `project.yml` 의 `MARKETING_VERSION` 과 `linux/Sources/Sizer/BuildInfo.swift` 를 함께 바꿉니다(테스트가 검사).
- 릴리스를 게시하면 `release-linux.yml` 이 amd64·arm64 패키지를 만들어 릴리스에 올립니다.

## 프로젝트 구조

- `Sizer/Model/` — 설정·값 타입(`AppSettings`, `ConversionConfig`, `TrimOptions`, `ImageFormat` …)
- `Sizer/Engine/` — 변환 엔진(`ConversionEngine`, `FreezeDetector`, `SegmentPlanner`, `ImageConverter`, `FolderWatcher`, `WatchCoordinator`, `ProcessedCleaner`)
- `Sizer/Services/` — `Notifier`, `LoginItem`, `AppLogger`
- `Sizer/UI/` — 메뉴바/설정 SwiftUI 뷰
- `SizerTests/` — 순수 로직 단위 테스트 + 실제 ffmpeg/ImageIO 통합 테스트
- `linux/Sources/Sizer/` — Linux 전용 구현(inotify 감시, ffmpeg 이미지 변환·배지, notify-send 알림, 설정 파일, 데몬, CLI)
- `linux/Tests/SizerTests/` — Linux 계층 테스트, `linux/packaging/` — systemd 서비스·.desktop·Files 확장·deb/tar.gz 스크립트

## 코딩 규칙

- Swift 5 언어 모드, 최소 배포 타깃 macOS 13.
- 순수 로직(예: `SegmentPlanner`, `ProcessedCleaner`)은 사이드이펙트 없이 테스트 가능하게 유지.
- 새 동작에는 테스트를 추가해 주세요. PR 전 `xcodebuild ... test`가 통과해야 합니다.
- UI 문자열은 한국어를 기본으로 합니다.

## PR 절차

1. 이슈로 먼저 논의(선택) → 브랜치 생성.
2. 변경 + 테스트 추가, 로컬에서 `test` 통과 확인.
3. PR 설명에 무엇을·왜 바꿨는지 요약.

## 참고: ffmpeg 라이선스

Sizer는 ffmpeg를 **별도 실행 파일로 호출**할 뿐 라이브러리로 링크하지 않습니다. 따라서 Sizer 소스는
ffmpeg의 라이선스(GPL/LGPL, 빌드 구성에 따라 다름)의 영향을 받지 않습니다. 다만 ffmpeg 바이너리를
**함께 번들해 재배포**할 경우 해당 라이선스 준수가 필요합니다(현재 배포는 Homebrew ffmpeg 참조).
