#!/usr/bin/env bash
#
# SNS 비디오 변환 백그라운드 서비스 설치 스크립트.
# launchd LaunchAgent 로 등록하여 로그인 시 자동 실행되게 한다.
#
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LABEL="com.dilly.snsvideo"
PLIST_SRC="${BASE_DIR}/${LABEL}.plist"
PLIST_DST="${HOME}/Library/LaunchAgents/${LABEL}.plist"
PYTHON_BIN="$(command -v python3)"

if [[ -z "${PYTHON_BIN}" ]]; then
  echo "python3 를 찾을 수 없습니다." >&2
  exit 1
fi
if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "경고: ffmpeg 가 없습니다. 'brew install ffmpeg' 를 먼저 실행하세요." >&2
fi

mkdir -p "${HOME}/Library/LaunchAgents" "${BASE_DIR}/logs" \
         "${BASE_DIR}/input" "${BASE_DIR}/output" \
         "${BASE_DIR}/processed" "${BASE_DIR}/failed"

# 플레이스홀더를 실제 경로로 치환하여 설치
sed -e "s|__PYTHON__|${PYTHON_BIN}|g" \
    -e "s|__BASE_DIR__|${BASE_DIR}|g" \
    "${PLIST_SRC}" > "${PLIST_DST}"

# 이미 로드되어 있으면 먼저 내린다
launchctl unload "${PLIST_DST}" 2>/dev/null || true
launchctl load "${PLIST_DST}"

echo "설치 완료 ✅"
echo "  서비스: ${LABEL}"
echo "  input  : ${BASE_DIR}/input   (여기에 영상을 넣으세요)"
echo "  output : ${BASE_DIR}/output"
echo "  로그   : ${BASE_DIR}/logs/convert.log"
echo
echo "상태 확인 : launchctl list | grep ${LABEL}"
echo "제거      : ${BASE_DIR}/uninstall.sh"
