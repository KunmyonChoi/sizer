#!/usr/bin/env bash
#
# Sizer 개인용 로컬 설치(미공증 ad-hoc 서명).
# 소스에서 Release 빌드 → ad-hoc 서명 → /Applications 설치 → 실행.
# Developer ID/공증 불필요. 이 머신에서만 사용.
#
set -euo pipefail

BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$BASE"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen 이 필요합니다: brew install xcodegen" >&2
  exit 1
fi
if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "경고: ffmpeg 가 없습니다. 'brew install ffmpeg' 후 사용하세요." >&2
fi

echo "▶︎ 프로젝트 생성 + Release 빌드…"
xcodegen generate >/dev/null
xcodebuild -project Sizer.xcodeproj -scheme Sizer -configuration Release \
  -derivedDataPath build/dd -destination 'platform=macOS' clean build >/dev/null

APP="build/dd/Build/Products/Release/Sizer.app"
echo "▶︎ ad-hoc 서명…"
codesign --force --deep -s - "$APP"

echo "▶︎ 기존 Sizer 종료 후 /Applications 설치…"
pkill -x Sizer 2>/dev/null || true
sleep 1
rm -rf "/Applications/Sizer.app"
cp -R "$APP" "/Applications/Sizer.app"
xattr -dr com.apple.quarantine "/Applications/Sizer.app" 2>/dev/null || true

echo "▶︎ 실행…"
open "/Applications/Sizer.app"

echo
echo "설치 완료 ✅  /Applications/Sizer.app"
echo "  메뉴바에 Sizer 아이콘이 나타납니다."
echo "  기본 폴더: ~/Movies/Sizer/{drop,output,processed,failed}"
echo "  설정에서 폴더·코덱·트리밍을 변경할 수 있습니다."
echo "  첫 알림 시 macOS가 권한을 물으면 허용하세요."
