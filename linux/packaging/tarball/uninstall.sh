#!/bin/sh
#
# Sizer 사용자 설치 제거. 설정(~/.config/sizer)과 변환 폴더는 남긴다.
#
set -eu

BIN_DIR="${PREFIX:-$HOME/.local}/bin"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}"

if command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1; then
    systemctl --user disable --now sizer.service >/dev/null 2>&1 || true
fi

pkill -x sizer-tray 2>/dev/null || true
rm -f "$BIN_DIR/sizer" "$BIN_DIR/sizer-tray" "$BIN_DIR/sizer-settings" \
      "$DATA_DIR/sizer/sizer_panel.py" \
      "$DATA_DIR/applications/com.dilly.sizer.Settings.desktop" \
      "${XDG_CONFIG_HOME:-$HOME/.config}/autostart/com.dilly.sizer.tray.desktop" \
      "$DATA_DIR/systemd/user/sizer.service" \
      "$DATA_DIR/applications/com.dilly.sizer.desktop" \
      "$DATA_DIR/icons/hicolor/scalable/apps/com.dilly.sizer.svg" \
      "$DATA_DIR/nautilus-python/extensions/sizer-nautilus.py"

if command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1; then
    systemctl --user daemon-reload
fi
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q "$DATA_DIR/applications" || true

echo "Sizer를 제거했습니다. 설정(~/.config/sizer)과 변환 폴더는 그대로 남아 있습니다."
