#!/usr/bin/env bash
#
# SNS 비디오 변환 백그라운드 서비스 제거 스크립트.
#
set -euo pipefail

LABEL="com.dilly.snsvideo"
PLIST_DST="${HOME}/Library/LaunchAgents/${LABEL}.plist"

if [[ -f "${PLIST_DST}" ]]; then
  launchctl unload "${PLIST_DST}" 2>/dev/null || true
  rm -f "${PLIST_DST}"
  echo "제거 완료 ✅ (${LABEL})"
else
  echo "설치되어 있지 않습니다."
fi

echo "input/output/processed/failed 폴더와 로그는 그대로 남겨두었습니다."
