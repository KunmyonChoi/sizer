#!/bin/sh
#
# Sizer 사용자 설치 — ~/.local 에 설치하고 systemd 사용자 서비스를 켠다. sudo 가 필요 없다.
# 다시 실행하면 업데이트(실행 중인 데몬 재시작)가 된다. 제거: ./uninstall.sh
#
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
BIN_DIR="${PREFIX:-$HOME/.local}/bin"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}"

install_file() {   # 모드 원본 대상
    mkdir -p "$(dirname "$3")"
    cp "$2" "$3.tmp.$$"
    chmod "$1" "$3.tmp.$$"
    mv -f "$3.tmp.$$" "$3"   # 실행 중인 바이너리도 안전하게 교체(이름 바꾸기)
}

install_template() {   # 원본 대상 — @BINDIR@ 를 실제 경로로 바꿔 설치
    mkdir -p "$(dirname "$2")"
    sed "s|@BINDIR@|$BIN_DIR|g" "$1" > "$2"
}

echo "▶︎ 설치: $BIN_DIR/sizer"
install_file 755 "$HERE/bin/sizer" "$BIN_DIR/sizer"
install_file 755 "$HERE/bin/sizer-tray" "$BIN_DIR/sizer-tray"
install_file 644 "$HERE/share/sizer/sizer_panel.py" "$DATA_DIR/sizer/sizer_panel.py"
install_file 755 "$HERE/bin/sizer-settings" "$BIN_DIR/sizer-settings"
install_template "$HERE/share/sizer/com.dilly.sizer.Settings.desktop" "$DATA_DIR/applications/com.dilly.sizer.Settings.desktop"
install_template "$HERE/share/sizer/com.dilly.sizer.tray.desktop" "${XDG_CONFIG_HOME:-$HOME/.config}/autostart/com.dilly.sizer.tray.desktop"
install_template "$HERE/share/sizer/sizer.service" "$DATA_DIR/systemd/user/sizer.service"
install_template "$HERE/share/sizer/com.dilly.sizer.desktop" "$DATA_DIR/applications/com.dilly.sizer.desktop"
install_file 644 "$HERE/share/sizer/com.dilly.sizer.svg" "$DATA_DIR/icons/hicolor/scalable/apps/com.dilly.sizer.svg"
install_file 644 "$HERE/share/sizer/sizer-nautilus.py" "$DATA_DIR/nautilus-python/extensions/sizer-nautilus.py"
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q "$DATA_DIR/applications" || true
command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -q -t "$DATA_DIR/icons/hicolor" 2>/dev/null || true

if command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1; then
    echo "▶︎ 서비스 켜기(로그인 시 자동 시작)"
    systemctl --user daemon-reload
    systemctl --user enable sizer.service >/dev/null 2>&1
    systemctl --user restart sizer.service
else
    echo "⚠︎ systemd 사용자 세션이 없어 서비스를 켜지 못했습니다. 직접 실행: $BIN_DIR/sizer daemon"
fi

if [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
    echo "▶︎ 상단 바 아이콘 켜기"
    pkill -x sizer-tray 2>/dev/null || true
    sleep 0.5
    nohup "$BIN_DIR/sizer-tray" >/dev/null 2>&1 &
fi

echo
"$BIN_DIR/sizer" status || true
echo

missing=""
command -v ffmpeg >/dev/null 2>&1 || missing="$missing ffmpeg"
command -v notify-send >/dev/null 2>&1 || missing="$missing libnotify-bin"
ls /usr/lib/*/nautilus/extensions-4/libnautilus-python.so >/dev/null 2>&1 || missing="$missing python3-nautilus"
/usr/bin/python3 -c "import gi; gi.require_version('AyatanaAppIndicator3', '0.1')" 2>/dev/null \
    || missing="$missing python3-gi gir1.2-ayatanaappindicator3-0.1"
/usr/bin/python3 -c "import gi; gi.require_version('Adw', '1')" 2>/dev/null \
    || missing="$missing gir1.2-gtk-4.0 gir1.2-adw-1"
if [ -n "$missing" ]; then
    echo "권장 패키지가 없습니다:  sudo apt install$missing"
fi
case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) echo "터미널에서 sizer 명령을 쓰려면 PATH에 $BIN_DIR를 추가하세요(다시 로그인하면 보통 자동 추가됩니다)." ;;
esac
echo "Files 우클릭 메뉴가 안 보이면 Files를 다시 시작하세요:  nautilus -q"
echo "설치 완료 ✅  드롭 폴더 열기: sizer open"
