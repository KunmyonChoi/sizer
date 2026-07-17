#!/usr/bin/env bash
#
# [후속 과제 — Developer ID 확보 시] 공유 배포용 서명 + 공증 빌드.
# 현재는 Apple Developer ID 계정이 없어 실행할 수 없다(개인용은 install_local.sh 사용).
#
# 준비되면:
#   1) 정적 ffmpeg/ffprobe(arm64)를 Sizer/Resources/Helpers/ 에 넣고 project.yml에
#      Copy Files(→ Contents/Helpers) 및 GPL 라이선스/소스 오퍼 동봉을 추가한다.
#   2) project.yml 에서 ENABLE_HARDENED_RUNTIME: YES, CODE_SIGN_IDENTITY: "Developer ID Application".
#   3) 아래 환경변수를 채우고 실행한다.
#
set -euo pipefail

: "${DEV_ID:?'DEV_ID 예) Developer ID Application: Your Name (TEAMID)'}"
: "${NOTARY_PROFILE:?'notarytool keychain 프로파일명 (xcrun notarytool store-credentials 로 생성)'}"

BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$BASE"

xcodegen generate
xcodebuild -project Sizer.xcodeproj -scheme Sizer -configuration Release \
  -derivedDataPath build/dd -destination 'platform=macOS' clean build

APP="build/dd/Build/Products/Release/Sizer.app"

# 번들 ffmpeg/ffprobe 포함 deep sign(Hardened Runtime)
codesign --force --deep --options runtime --timestamp -s "$DEV_ID" "$APP"

# zip 후 공증
DIST="build/Sizer.zip"
ditto -c -k --keepParent "$APP" "$DIST"
xcrun notarytool submit "$DIST" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"

# 검증
codesign --verify --deep --strict --verbose=2 "$APP"
spctl -a -vvv -t exec "$APP"

echo "공증 완료 ✅  $APP"
