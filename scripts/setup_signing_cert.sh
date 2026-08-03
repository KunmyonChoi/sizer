#!/usr/bin/env bash
#
# Sizer 로컬 빌드용 자체 서명 코드사인 인증서 설정(머신당 1회).
#
# 왜: ad-hoc 서명(codesign -s -)은 빌드마다 CDHash가 바뀐다. macOS 손쉬운 사용(TCC)
#     권한은 그 해시에 묶이므로, 재빌드/업그레이드할 때마다 권한이 초기화돼 매번 다시
#     허용해야 한다. 고정된 자체 서명 인증서로 서명하면 코드 신원이 일정해 권한이 유지된다.
#     (Apple 개발자 등록·공증 불필요. 로컬 전용.)
#
# 실행 후: ./scripts/install_local.sh 가 이 인증서로 서명하며,
#          손쉬운 사용 권한은 최초 1회만 허용하면 이후 재빌드에도 유지된다.
#
set -euo pipefail

NAME="Sizer Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning 2>/dev/null | grep -q "$NAME"; then
  echo "이미 '$NAME' 인증서가 있습니다. (재설정하려면 '키체인 접근'에서 삭제 후 다시 실행)"
  exit 0
fi

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cnf" <<'CNF'
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = Sizer Local Signing
[v3]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:false
CNF

echo "▶︎ 자체 서명 코드사인 인증서 생성(10년)…"
openssl req -x509 -newkey rsa:2048 -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
  -days 3650 -nodes -config "$TMP/cert.cnf" >/dev/null 2>&1

# macOS 'security import' 호환을 위해 레거시 PBE(3DES/SHA1) 사용
# (OpenSSL 3 기본 PKCS#12 암호화는 macOS가 MAC 검증에 실패한다.)
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -out "$TMP/cert.p12" \
  -passout pass:sizer -name "$NAME" \
  -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1 >/dev/null 2>&1

echo "▶︎ 로그인 키체인에 가져오기…"
security import "$TMP/cert.p12" -k "$KEYCHAIN" -P sizer -A -T /usr/bin/codesign >/dev/null

echo "▶︎ codesign 이 이 키로 서명하도록 파티션 리스트 설정 — Mac 로그인 암호가 필요합니다."
read -rsp "   Mac 로그인 암호: " PW; echo
# 이 명령은 처리에 성공해도 종료코드 1을 반환할 수 있어 실패로 보지 않는다(실제 확인은 아래 codesign).
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -t private \
  -k "$PW" "$KEYCHAIN" >/dev/null 2>&1 || true
unset PW

echo "▶︎ 서명 검증…"
# 재서명 가능한(SIP 아님) 바이너리로 테스트. 시스템 바이너리(/bin/*)는 SIP라 재서명 불가.
TESTSRC="$(command -v xcodegen || command -v ffmpeg || command -v brew || true)"
if [ -n "$TESTSRC" ] && cp "$TESTSRC" "$TMP/signtest" 2>/dev/null \
   && codesign --force --sign "$NAME" "$TMP/signtest" >/dev/null 2>&1 \
   && codesign -dvvv "$TMP/signtest" 2>&1 | grep -q "Authority=$NAME"; then
  echo "✅ 완료 — 이제 ./scripts/install_local.sh 가 '$NAME' 로 서명합니다."
  echo "   빌드 후 손쉬운 사용 권한을 최초 1회만 허용하면 재빌드에도 유지됩니다."
else
  echo "⚠️  자동 검증을 건너뜁니다(테스트용 바이너리 없음/파티션 미설정). install_local 빌드 후"
  echo "   'codesign -dvvv /Applications/Sizer.app | grep Authority' 로 확인하세요."
  echo "   여전히 ad-hoc이면: security set-key-partition-list -S apple-tool:,apple:,codesign: -s -t private -k <로그인암호> \"$KEYCHAIN\""
fi
