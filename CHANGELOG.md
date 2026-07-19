# Changelog

이 프로젝트의 주요 변경 사항을 기록합니다. 형식은 [Keep a Changelog](https://keepachangelog.com/ko/1.1.0/)를
따르며 [Semantic Versioning](https://semver.org/lang/ko/)을 사용합니다.

## [1.1.0] - 2026-07-19

### Added
- **플로팅 드롭 타겟** — 화면에 떠 있는 콤팩트 드롭 필(HUD 글래스, 항상 위·이동·위치 기억). Finder에서
  파일을 드롭하면 드롭 폴더로 복사되어 자동 변환. 드래그 호버 시 확대·글로우, 드롭 성공 시 카운트 플래시.
- **Homebrew tap** 설치 경로(`brew install KunmyonChoi/tap/sizer`) — 소스 빌드라 개발자 등록/공증 없이
  Gatekeeper 경고 없이 설치.
- **30초 튜토리얼 영상**(hyperframes) + README 프리뷰.

## [1.0.0] - 2026-07-17

### Added
- macOS 메뉴바(트레이) 앱으로 재구성 — Dock 아이콘 없는 agent 앱, 팝오버 메뉴.
- 드롭 폴더 감시(FSEvents + 주기적 재스캔) → 자동 변환.
- 영상 변환: H.264/H.265/VideoToolbox, CRF/Preset/장변 축소/오디오 비트레이트/접미사 설정 노출.
- **움직임 없는 구간 자동 제거** 개선: 민감도 프리셋, 짧은 조각 제거(정확도), 컷 패딩·오디오 페이드(부드러움), 안전장치.
- **이미지 캡처 변환**(ImageIO): AVIF/HEIC/JPEG/PNG, 품질·최대 크기 설정. 스크린샷 기준 70~95% 절감.
- 설정에서 드롭/출력/완료/실패 폴더 변경, 로그인 시 자동 시작(SMAppService), 알림(UserNotifications).
- 최근 변환 목록 클릭 → 결과 재생/열기.
- 변환 중 트레이 아이콘 회전 애니메이션.
- **processed 폴더 자동 정리**(기본 켬, 30일) — 보관 기간 지난 원본 자동 삭제.
- 순수 로직 단위 테스트 + 실제 ffmpeg/ImageIO 통합 테스트.

### 참고
- 이전 버전은 Python `watch_convert.py` launchd 워커였으며 `legacy/`에 보존.
