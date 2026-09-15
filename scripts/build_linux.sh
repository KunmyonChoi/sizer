#!/usr/bin/env bash
#
# Sizer Linux 빌드 → 테스트 → 패키지(.deb + .tar.gz).
#
#   ./scripts/build_linux.sh               이 머신의 Swift 툴체인으로(Ubuntu 24.04 + Swift 6.1 권장)
#   ./scripts/build_linux.sh --docker      Swift 가 없으면 linux/Dockerfile 이미지 안에서(Docker 필요)
#   ./scripts/build_linux.sh --skip-tests  테스트 생략
#
# 산출물: dist/sizer_<버전>_<arch>.deb, dist/sizer-<버전>-linux-<arch>.tar.gz
# 실행 파일은 Swift 표준 라이브러리를 정적 링크해 Swift 런타임 없이 돈다(glibc·libstdc++ 만 필요).
#
set -euo pipefail

BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$BASE"

USE_DOCKER=0
PASS_ARGS=()
for arg in "$@"; do
  case "$arg" in
    --docker) USE_DOCKER=1 ;;
    --skip-tests) PASS_ARGS+=("$arg") ;;
    *) echo "알 수 없는 인자: $arg" >&2; exit 2 ;;
  esac
done

if [ "$USE_DOCKER" = 1 ]; then
  # 컨테이너 안에서는 git 워크트리의 원본 저장소가 보이지 않을 수 있어 여기서 정해 넘긴다.
  MAINTAINER="${MAINTAINER:-$(git log -1 --format='%an <%ae>' 2>/dev/null || true)}"
  echo "▶︎ 빌드 이미지 준비(linux/Dockerfile)…"
  docker build -q -t sizer-linux-build -f linux/Dockerfile linux >/dev/null
  mkdir -p .build/docker-home
  exec docker run --rm -u "$(id -u):$(id -g)" -e HOME=/src/.build/docker-home \
    -e MAINTAINER="${MAINTAINER:-}" \
    -v "$BASE":/src -w /src sizer-linux-build ./scripts/build_linux.sh "${PASS_ARGS[@]}"
fi

if ! command -v swift >/dev/null 2>&1; then
  echo "Swift 툴체인이 없습니다 — --docker 로 실행하거나 https://www.swift.org/install/linux/ 를 참고하세요." >&2
  exit 1
fi

VERSION="$(sed -n 's/.*static let version = "\(.*\)".*/\1/p' linux/Sources/Sizer/BuildInfo.swift)"
[ -n "$VERSION" ] || { echo "BuildInfo.swift 에서 버전을 읽지 못했습니다." >&2; exit 1; }

if [[ " ${PASS_ARGS[*]-} " != *" --skip-tests "* ]]; then
  echo "▶︎ 테스트…"
  swift test
  python3 -B -m unittest discover -s linux/packaging/tray -p 'test_*.py'
  python3 -B -m unittest discover -s linux/packaging/settings -p 'test_*.py'
fi

echo "▶︎ Release 빌드(정적 Swift 표준 라이브러리)…"
swift build -c release --static-swift-stdlib --product sizer
BIN="$(swift build -c release --static-swift-stdlib --show-bin-path)/sizer"

case "$(uname -m)" in
  x86_64) DEB_ARCH=amd64 ;;
  aarch64) DEB_ARCH=arm64 ;;
  *) DEB_ARCH="$(uname -m)" ;;
esac
TAR_ARCH="$(uname -m)"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p dist

install -Dm755 "$BIN" "$STAGE/sizer"
strip --strip-unneeded "$STAGE/sizer" 2>/dev/null || true

# ── tar.gz (사용자 설치: ~/.local) ────────────────────────────────────────────
NAME="sizer-$VERSION-linux-$TAR_ARCH"
T="$STAGE/$NAME"
install -Dm755 "$STAGE/sizer" "$T/bin/sizer"
install -Dm755 linux/packaging/tray/sizer-tray "$T/bin/sizer-tray"
install -Dm755 linux/packaging/settings/sizer-settings "$T/bin/sizer-settings"
install -Dm644 linux/packaging/com.dilly.sizer.Settings.desktop "$T/share/sizer/com.dilly.sizer.Settings.desktop"
install -Dm644 linux/packaging/com.dilly.sizer.tray.desktop "$T/share/sizer/com.dilly.sizer.tray.desktop"
install -Dm644 linux/packaging/sizer.service "$T/share/sizer/sizer.service"
install -Dm644 linux/packaging/com.dilly.sizer.desktop "$T/share/sizer/com.dilly.sizer.desktop"
install -Dm644 assets/logo.svg "$T/share/sizer/com.dilly.sizer.svg"
install -Dm644 linux/packaging/nautilus/sizer-nautilus.py "$T/share/sizer/sizer-nautilus.py"
install -m755 linux/packaging/tarball/install.sh linux/packaging/tarball/uninstall.sh "$T/"
install -m644 LICENSE "$T/LICENSE"
install -m644 docs/linux.md "$T/README.md"
tar -C "$STAGE" -czf "dist/$NAME.tar.gz" "$NAME"

# ── .deb (시스템 설치: /usr) ──────────────────────────────────────────────────
D="$STAGE/deb"
install -Dm755 "$STAGE/sizer" "$D/usr/bin/sizer"
install -Dm755 linux/packaging/tray/sizer-tray "$D/usr/bin/sizer-tray"
install -Dm755 linux/packaging/settings/sizer-settings "$D/usr/bin/sizer-settings"
mkdir -p "$D/usr/lib/systemd/user" "$D/usr/share/applications" "$D/etc/xdg/autostart"
sed 's|@BINDIR@|/usr/bin|g' linux/packaging/com.dilly.sizer.tray.desktop > "$D/etc/xdg/autostart/com.dilly.sizer.tray.desktop"
sed 's|@BINDIR@|/usr/bin|g' linux/packaging/sizer.service > "$D/usr/lib/systemd/user/sizer.service"
sed 's|@BINDIR@|/usr/bin|g' linux/packaging/com.dilly.sizer.desktop > "$D/usr/share/applications/com.dilly.sizer.desktop"
sed 's|@BINDIR@|/usr/bin|g' linux/packaging/com.dilly.sizer.Settings.desktop > "$D/usr/share/applications/com.dilly.sizer.Settings.desktop"
install -Dm644 assets/logo.svg "$D/usr/share/icons/hicolor/scalable/apps/com.dilly.sizer.svg"
install -Dm644 linux/packaging/nautilus/sizer-nautilus.py "$D/usr/share/nautilus-python/extensions/sizer-nautilus.py"
install -Dm644 LICENSE "$D/usr/share/doc/sizer/copyright"
install -Dm644 docs/linux.md "$D/usr/share/doc/sizer/linux.md"
install -Dm755 linux/packaging/deb/postinst "$D/DEBIAN/postinst"
install -Dm755 linux/packaging/deb/prerm "$D/DEBIAN/prerm"
chmod 755 "$D/usr/lib/systemd/user" "$D/usr/share/applications" "$D/etc" "$D/etc/xdg" "$D/etc/xdg/autostart"
chmod 644 "$D/usr/lib/systemd/user/sizer.service" "$D/usr/share/applications/com.dilly.sizer.desktop" \
  "$D/usr/share/applications/com.dilly.sizer.Settings.desktop" \
  "$D/etc/xdg/autostart/com.dilly.sizer.tray.desktop"
echo "/etc/xdg/autostart/com.dilly.sizer.tray.desktop" > "$D/DEBIAN/conffiles"

# 공유 라이브러리 의존성(libc6, libstdc++6 …)은 dpkg-shlibdeps 로 계산한다.
SHLIBS="libc6, libgcc-s1, libstdc++6"
if command -v dpkg-shlibdeps >/dev/null 2>&1; then
  mkdir -p "$STAGE/shlibs/debian"
  printf 'Source: sizer\n\nPackage: sizer\nArchitecture: any\n' > "$STAGE/shlibs/debian/control"
  if out="$(cd "$STAGE/shlibs" && dpkg-shlibdeps -O "$D/usr/bin/sizer" 2>/dev/null)"; then
    SHLIBS="${out#shlibs:Depends=}"
  else
    echo "⚠︎ dpkg-shlibdeps 실패 — 버전 없는 기본 의존성($SHLIBS)을 씁니다." >&2
  fi
fi

if [ -z "${MAINTAINER:-}" ]; then
  MAINTAINER="$(git log -1 --format='%an <%ae>' 2>/dev/null || echo 'Sizer <noreply@github.com>')"
fi

cat > "$D/DEBIAN/control" <<EOF
Package: sizer
Version: $VERSION
Architecture: $DEB_ARCH
Maintainer: $MAINTAINER
Installed-Size: $(du -sk "$D/usr" | cut -f1)
Depends: ffmpeg, python3, $SHLIBS
Recommends: libnotify-bin, python3-nautilus, python3-gi, gir1.2-ayatanaappindicator3-0.1, gir1.2-gtk-4.0, gir1.2-adw-1, gnome-shell-extension-appindicator
Suggests: libheif-examples, libheif-plugin-x265, libheif-plugin-libde265
Section: video
Priority: optional
Homepage: https://github.com/KunmyonChoi/sizer
Description: drop-folder video and image compressor
 Sizer watches a drop folder and re-encodes videos (ffmpeg, H.264/H.265)
 and images (AVIF/JPEG/PNG/HEIC) to small, high-quality files. Low-motion
 stretches of screen recordings can be cut or fast-forwarded.
 .
 Runs as a systemd user service with a top-bar tray menu (status, recent
 conversions, pause, keep-awake) and a GTK settings window, notifies with
 open/reveal buttons, and adds
 a "Sizer로 변환" item to the Files (Nautilus) context menu.
EOF

DEB="dist/sizer_${VERSION}_${DEB_ARCH}.deb"
dpkg-deb --root-owner-group -Zxz --build "$D" "$DEB" >/dev/null

echo
echo "완료 ✅"
ls -lh "$DEB" "dist/$NAME.tar.gz" | awk '{print "  " $5 "  " $NF}'
