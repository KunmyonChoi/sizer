# Sizer for Linux (베타)

Ubuntu 등 Linux 데스크톱용 Sizer입니다. macOS 앱과 **같은 변환 엔진**(ffmpeg 기반 영상 변환, 저모션 구간
잘라내기·빨리감기)을 쓰며, **백그라운드 서비스 + 상단 바 아이콘 + 파일 관리자 우클릭 메뉴 + 알림**으로 동작합니다.

- **드롭 폴더 감시** — `~/Videos/Sizer/drop`(한국어 데스크톱이면 `~/비디오/Sizer/drop`)에 넣으면 자동 변환
- **Files 우클릭 → "Sizer로 변환"** — 선택한 영상·이미지를 바로 변환(원본은 그대로)
- **알림** — 끝나면 `열기` / `폴더에서 보기` 버튼이 달린 알림
- **상단 바 아이콘** — 상태, 최근 변환, 폴더 열기, 일시정지, 모니터 꺼짐 방지
- **로그인 시 자동 시작** — systemd 사용자 서비스 + 트레이
- **터미널 명령** — `sizer convert 영상.mp4`

> Ubuntu 24.04 LTS(GNOME)에서 개발·테스트했습니다. 다른 배포판은 tar.gz 설치본을 쓰세요(최신 glibc 필요).

## macOS 판과의 차이

| 기능 | macOS | Linux |
|---|---|---|
| 드롭 폴더 자동 변환 · 저모션 잘라내기/빨리감기 | ✅ | ✅ 같은 엔진 |
| 이미지 변환(AVIF/JPEG/PNG/HEIC) | ✅ ImageIO | ✅ ffmpeg(+ HEIC 는 libheif) |
| 드롭·셸프 패널 | ✅ | ➖ Files 우클릭 메뉴로 대체 |
| 메뉴바 아이콘 · 최근 변환 목록 | ✅ 팝오버 | ✅ 상단 바 트레이(메뉴 형태) |
| 설정 화면 | ✅ | ✅ 설정 창(일반·인코딩·트리밍·이미지) — 바꾸면 즉시 적용 |
| 하드웨어 인코딩 | VideoToolbox | ➖ 소프트웨어(libx264/libx265). VAAPI/NVENC 는 후속 과제 |
| 창 스냅 | ✅ | ❌ Wayland 는 다른 앱의 창을 옮길 수 없습니다. Ubuntu 기본 **확장 타일링**(설정 → Ubuntu 데스크톱)을 쓰세요 |
| 모니터 꺼짐 방지 | ✅ | ✅ 트레이 메뉴(GNOME 유휴 억제) |

## 설치

### 방법 A — .deb (Ubuntu · Debian 계열, 권장)

[Releases](https://github.com/KunmyonChoi/sizer/releases)에서 `sizer_<버전>_amd64.deb`(ARM 이면 `arm64`)를 받아:

```bash
sudo apt install ./sizer_*_amd64.deb   # ffmpeg·트레이·Files 확장 의존성도 함께 설치
```

설치 후 앱 목록에서 **Sizer** 를 실행하면 서비스와 상단 바 아이콘이 켜집니다(다음 로그인부터는 자동).
Files 우클릭 메뉴는 Files 를 다시 시작하면 나타납니다(`nautilus -q`).

- 제거: `sudo apt remove sizer` — 설정과 변환 폴더는 남습니다.
- 모든 사용자 계정에서 로그인 시 서비스가 켜집니다(전역 활성화라 `systemctl --user disable` 로는 꺼지지 않습니다).
  내 계정에서만 끄려면 `systemctl --user mask --now sizer`, 되돌리려면 `systemctl --user unmask sizer`.

### 방법 B — tar.gz (sudo 없이 내 계정에만)

```bash
tar xzf sizer-*-linux-x86_64.tar.gz
cd sizer-*-linux-x86_64
./install.sh          # ~/.local 에 설치 + 서비스 켜기. 다시 실행하면 업데이트
```

ffmpeg 등은 따로 설치해야 합니다:
`sudo apt install ffmpeg libnotify-bin python3-nautilus python3-gi gir1.2-ayatanaappindicator3-0.1`.
제거는 같은 폴더의 `./uninstall.sh`.

## 사용법

1. **드롭 폴더에 넣기** — 앱 목록에서 **Sizer** 를 누르면 드롭 폴더가 열립니다. 여기에 파일을 복사/이동하면
   변환이 시작되고, 결과는 `output` 폴더에 `원본이름_resize.mp4` 로 저장됩니다. 원본은 `processed` 로 옮겨지고
   (기본 30일 뒤 자동 삭제), 실패하면 `failed` 로 옮겨집니다.
2. **Files 에서 우클릭 → "Sizer로 변환"** — 선택한 파일을 드롭 폴더로 **복사**해 변환합니다. 끝나면 출력 폴더가
   열립니다(`openOutputAfterAdd`). 서비스가 꺼져 있으면 켜고, 켤 수 없으면 바로 변환합니다.
3. **터미널** — `sizer convert 영상.mp4 스크린샷.png` 는 지금 그 자리에서 변환하고 원본을 옮기지 않습니다.
   `-o 폴더` 로 출력 위치를 바꿀 수 있습니다.

앱 아이콘을 우클릭하면 **출력 폴더 열기 · 설정…** 도 있습니다.

### 상단 바 아이콘

macOS 메뉴바 앱에 해당합니다. 아이콘을 누르면 메뉴가 열립니다(GNOME 은 팝오버가 아니라 메뉴만 지원).

- **아이콘**: 기본은 압축 화살표, 변환 중에는 회전, 일시정지면 ⏸, 모니터 꺼짐 방지 중이면 ☀, 서비스가 꺼져 있으면 흐리게
- **메뉴**: 상태(감시 중 / 변환 중: 파일명 · 대기 N / 일시정지), 최근 변환 8개(누르면 결과 열기, 실패는 로그),
  드롭·출력 폴더 열기, 지금 다시 스캔, 감시 일시정지/재개, 모니터 꺼짐 방지, 설정…, 로그 열기, Sizer 종료
- **모니터 꺼짐 방지**는 트레이가 떠 있는 동안만 유지되며 권한이 필요 없습니다.
- **Sizer 종료**는 서비스와 트레이를 함께 끕니다. 다시 켜려면 앱 목록에서 Sizer 를 실행하세요.
- 아이콘은 GNOME 의 AppIndicator 확장이 그립니다. Ubuntu 는 기본으로 켜져 있고, 다른 배포판의 순정 GNOME 은
  `gnome-shell-extension-appindicator` 를 설치해 켜야 합니다.

### 명령

| 명령 | 설명 |
|---|---|
| `sizer open [drop\|output\|processed\|failed\|logs\|config]` | 폴더·로그·설정 파일 열기(기본 drop) |
| `sizer add <파일>...` | 드롭 폴더에 넣어 서비스가 변환(우클릭 메뉴가 쓰는 명령) |
| `sizer convert [-o 폴더] <파일>...` | 지금 이 터미널에서 변환, 원본 유지 |
| `sizer pause` / `sizer resume` | 감시 일시정지 / 재개(변환 중인 파일은 마저 끝냄) |
| `sizer rescan` | 설정을 다시 읽고 드롭 폴더 다시 살펴보기 |
| `sizer status` | 서비스 · 현재 상태 · ffmpeg · 알림 · 폴더 |
| `sizer-tray` | 상단 바 아이콘(로그인 시 자동 시작 — 직접 쓸 일은 거의 없음) |
| `sizer-settings` | 설정 창(트레이 메뉴 "설정…"과 같음) |
| `sizer config [path\|init]` | 설정 파일 보기 / 경로 / 기본값으로 다시 만들기(기존 파일은 `.bak`) |
| `sizer daemon` | 감시 데몬(서비스가 실행 — 직접 쓸 일은 거의 없음) |

## 설정

트레이 메뉴 **설정…** 으로 여는 설정 창(일반 · 인코딩 · 트리밍 · 이미지)에서 바꾸면 바로 저장·적용됩니다.
설정 창은 `~/.config/sizer/config.json` 을 고치며, 이 파일을 직접 편집해도 됩니다(`sizer open config`).
**저장하면 서비스가 바로 다시 읽습니다.** 모든 키는 생략할 수 있고, 틀린 값은 그 항목만 기본값으로 두고
로그에 경고를 남깁니다(`journalctl --user -u sizer`). 경로에는 `~` 를 쓸 수 있습니다.

| 키 | 기본값 | 설명 |
|---|---|---|
| `folders.drop` / `output` / `processed` / `failed` | `~/Videos/Sizer/…` | 드롭 · 결과 · 변환된 원본 · 실패한 원본 폴더 |
| `notifications` | `true` | 변환 완료/실패 알림 |
| `openOutputAfterAdd` | `true` | 우클릭 메뉴(`sizer add`)로 넣은 파일이 끝나면 출력 폴더 열기 |
| `processedRetentionDays` | `30` | processed 원본 보관 일수(`0` = 자동 삭제 끔) |
| `video.codec` | `"libx264"` | `libx264`(호환성) 또는 `libx265`(더 작음) |
| `video.crf` | `26` | 품질(0~51, 낮을수록 고화질·큰 용량) |
| `video.preset` | `"slow"` | `ultrafast` … `veryslow` (느릴수록 같은 화질에 작은 파일) |
| `video.maxLongEdge` | `1920` | 긴 변 최대 픽셀(작은 영상은 키우지 않음) |
| `video.audioBitrate` | `"128k"` | AAC 비트레이트 |
| `video.outputSuffix` | `"_resize"` | 결과 파일 이름 접미사(이미지에도 적용) |
| `still.mode` | `"fastForward"` | 정지·저모션 구간: `off` / `trim`(잘라내기) / `fastForward`(빨리감기, Beta) |
| `still.sensitivity` | `"conservative"` | 감지 민감도 프리셋: `aggressive` / `balanced` / `conservative` |
| `still.noiseDb` · `minStillDuration` · `mergeGapMax` | 프리셋값 | 적으면 프리셋 대신 이 값을 씀 |
| `still.minKeep` · `pad` · `minKeepRatio` · `smoothTransitions` | `0.3` · `0.15` · `0.02` · `false` | 잘라내기 후처리(macOS 설정 → 트리밍과 같음) |
| `still.adaptiveThreshold` | `false` | 노이즈 있는 영상에서 임계값 자동 완화 |
| `still.fastForwardSpeed` | `4` | 빨리감기 배속 `2` / `4` / `8` |
| `still.fastForwardMinDuration` | `2.0` | 이 길이(초) 이상인 저모션 구간만 배속 |
| `still.fastForwardMuteAudio` · `fastForwardBadge` | `true` · `true` | 배속 구간 음소거 · »N× 배지 |
| `image.enabled` | `true` | 드롭 폴더의 이미지도 변환 |
| `image.format` | `"avif"` | `avif` / `jpeg` / `png` / `heic`(HEIC 는 `libheif-examples libheif-plugin-x265` 필요) |
| `image.quality` | `0.8` | 손실 포맷 품질(0~1) |
| `image.maxLongEdge` | `0` | 긴 변 최대 픽셀(`0` = 원본 크기) |

HEIC(아이폰 사진) **입력**을 변환하려면 `sudo apt install libheif-examples libheif-plugin-libde265` 가 필요합니다.

## 문제 해결

- **상태 확인**: `sizer status` — 서비스 실행 여부, ffmpeg·알림 도구 위치, 폴더 경로가 나옵니다.
- **로그**: `journalctl --user -u sizer -f`(서비스) · `sizer open logs`(변환 로그 `~/.local/state/sizer/convert.log`).
- **변환이 안 됨**: ffmpeg 가 있는지(`sudo apt install ffmpeg`), 서비스가 켜져 있는지
  (`systemctl --user enable --now sizer`) 확인하세요. 파일은 복사가 끝나고 크기가 3초간 변하지 않아야 시작합니다.
- **우클릭 메뉴가 없음**: `sudo apt install python3-nautilus` 후 `nautilus -q` 로 Files 를 다시 시작하세요.
  tar.gz 설치라면 확장 파일이 `~/.local/share/nautilus-python/extensions/` 에 있어야 합니다.
- **상단 바 아이콘이 없음**: 터미널에서 `sizer-tray` 를 실행해 오류를 보세요. 보통
  `sudo apt install python3-gi gir1.2-ayatanaappindicator3-0.1` 또는 AppIndicator 확장이 꺼진 경우입니다
  (`gnome-extensions enable ubuntu-appindicators@ubuntu.com`). 로그인 시 자동으로 켜지 않게 하려면
  `~/.config/autostart/com.dilly.sizer.tray.desktop` 에 `Hidden=true` 를 적은 파일을 두세요.
- **설정 창이 안 열림**: 터미널에서 `sizer-settings` 를 실행해 오류를 보세요. 보통
  `sudo apt install gir1.2-gtk-4.0 gir1.2-adw-1` 이 필요합니다(libadwaita 1.4 이상 — Ubuntu 24.04 이상).
- **알림이 안 뜸**: `sudo apt install libnotify-bin`, 그리고 설정의 `notifications` 와 GNOME 방해 금지 모드를 확인하세요.
- **설정이 적용 안 됨**: JSON 문법이 틀리면 이전 설정으로 계속 동작하고 오류 알림을 띄웁니다. `sizer config` 로 확인하세요.

## 소스에서 빌드

Linux 판은 SwiftPM(`Package.swift`)으로 빌드하며, macOS 앱의 `Sizer/Engine` · `Sizer/Model` 소스를 그대로
공유합니다. Linux 전용 구현(inotify 감시, ffmpeg 이미지 변환, 알림, 데몬, CLI)은 `linux/` 에 있습니다.

```bash
./scripts/build_linux.sh            # Swift 6.1 툴체인이 있으면: 테스트 → 빌드 → dist/ 에 .deb, .tar.gz
./scripts/build_linux.sh --docker   # Swift 가 없으면 Docker 안에서(linux/Dockerfile)
swift test                          # 테스트만(ffmpeg 필요)
```
