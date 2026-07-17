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

## 프로젝트 구조

- `Sizer/Model/` — 설정·값 타입(`AppSettings`, `ConversionConfig`, `TrimOptions`, `ImageFormat` …)
- `Sizer/Engine/` — 변환 엔진(`ConversionEngine`, `FreezeDetector`, `SegmentPlanner`, `ImageConverter`, `FolderWatcher`, `WatchCoordinator`, `ProcessedCleaner`)
- `Sizer/Services/` — `Notifier`, `LoginItem`, `AppLogger`
- `Sizer/UI/` — 메뉴바/설정 SwiftUI 뷰
- `SizerTests/` — 순수 로직 단위 테스트 + 실제 ffmpeg/ImageIO 통합 테스트

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
