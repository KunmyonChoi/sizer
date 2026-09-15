# Sizer — Files(Nautilus) 우클릭 메뉴 "Sizer로 변환".
#
# 선택한 영상·이미지를 `sizer add` 로 넘긴다. 데몬이 드롭 폴더에서 변환하고 결과를 알림으로 알린다
# (데몬이 꺼져 있으면 sizer 가 서비스를 켜거나 바로 변환한다).
#
# 설치 위치: /usr/share/nautilus-python/extensions (deb) 또는 ~/.local/share/nautilus-python/extensions (tar.gz)
# 필요 패키지: python3-nautilus. 설치 후 `nautilus -q` 로 Files 를 다시 시작하면 메뉴가 나타난다.

import os
import shutil
import subprocess

from gi.repository import GObject, Nautilus

# Sizer/Model/ConversionConfig.swift 의 확장자 목록과 같게 유지한다(NautilusExtensionTests 가 검사).
VIDEO_EXTENSIONS = {"mp4", "mov", "mkv", "avi", "m4v", "webm", "flv", "wmv", "mpg", "mpeg", "3gp", "ts", "mts"}
IMAGE_EXTENSIONS = {"png", "jpg", "jpeg", "heic", "heif", "tiff", "tif", "bmp", "gif"}


def _sizer_command():
    found = shutil.which("sizer")
    if found:
        return found
    # 사용자 설치(tar.gz)는 ~/.local/bin 에 둔다 — Files 의 PATH 에는 없을 수 있다.
    local = os.path.expanduser("~/.local/bin/sizer")
    return local if os.access(local, os.X_OK) else None


def _supported_paths(files):
    paths = []
    for item in files:
        if item.get_uri_scheme() != "file" or item.is_directory():
            continue
        location = item.get_location()
        path = location.get_path() if location else None
        if not path:
            continue
        ext = os.path.splitext(path)[1][1:].lower()
        if ext in VIDEO_EXTENSIONS or ext in IMAGE_EXTENSIONS:
            paths.append(path)
    return paths


def _run_detached(args):
    subprocess.Popen(args, start_new_session=True, stdin=subprocess.DEVNULL,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


class SizerMenuProvider(GObject.GObject, Nautilus.MenuProvider):

    def get_file_items(self, *args):
        # Nautilus 43+ 는 (files), 그 이전은 (window, files) 로 부른다.
        paths = _supported_paths(args[-1])
        if not paths:
            return []
        label = "Sizer로 변환" if len(paths) == 1 else f"Sizer로 변환 ({len(paths)}개)"
        item = Nautilus.MenuItem(
            name="SizerMenuProvider::Convert",
            label=label,
            tip="고화질 저용량으로 변환해 Sizer 출력 폴더에 저장합니다",
        )
        item.connect("activate", self._convert, paths)
        return [item]

    def _convert(self, _item, paths):
        command = _sizer_command()
        try:
            if command is None:
                _run_detached(["notify-send", "--app-name=Sizer", "Sizer", "sizer 명령을 찾을 수 없습니다"])
            else:
                _run_detached([command, "add", "--", *paths])
        except OSError:
            pass
