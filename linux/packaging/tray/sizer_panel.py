"""Sizer 드롭·셸프 패널 — 화면 가장자리의 얇은 탭이 파일을 끌어오거나 마우스를 대면 펼쳐진다.

macOS ShelfController/ShelfView 에 해당한다. 위쪽은 변환 드롭존(놓으면 `sizer add`), 아래쪽은 보관 트레이
(원본을 참조로 담았다가 Files 로 끌어내면 이동/복사). sizer-tray 프로세스 안에서 GTK3 로 돈다.

창 위치 지정·항상 위는 X11 에서만 되므로 트레이는 GDK 를 X11 백엔드로 연다(Wayland 세션에서는 XWayland).
좌표·드롭 존·보관 목록·표시 문구 같은 순수 로직은 GTK 없이 테스트한다(test_sizer_panel.py).

창은 늘 펼친 크기이고, 접힘은 트레이를 숨겨(투명) 입력 영역(X SHAPE ShapeInput)을 핸들로 좁혀 표현한다.
끌어오는 동안 창 크기를 바꾸면 GTK4 앱(Files)의 끌기 소스가 드래그 시작 때 기억한 창 모양을 그대로 써서, 펼쳐진
부분에 놓은 파일이 패널 뒤 창으로 떨어진다. 입력 모양을 바꾸면 ShapeNotify 로 다시 읽으므로 펼친 영역이 제대로
드롭 대상이 되고, 접힌 동안 투명한 부분의 클릭·드롭은 뒤 창으로 간다.
표시 모양(ShapeBounding)은 건드리지 않는다 — mutter 는 표시 모양이 있는 투명(ARGB) 창을 그리지 않는다.
"""

import ctypes
import ctypes.util
import datetime
import hashlib
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import threading

# Sizer/Model/ConversionConfig.swift 와 같게 유지한다(LinuxPlatformTests 가 검사).
VIDEO_EXTENSIONS = {"mp4", "mov", "mkv", "avi", "m4v", "webm", "flv", "wmv", "mpg", "mpeg", "3gp", "ts", "mts"}
IMAGE_EXTENSIONS = {"png", "jpg", "jpeg", "heic", "heif", "tiff", "tif", "bmp", "gif"}

# macOS ShelfView 와 같은 크기(px).
HANDLE_WIDTH = 22
TRAY_WIDTH = 450
CONVERT_HEIGHT = 104
HOLD_HEIGHT = 220
EXPANDED_WIDTH = HANDLE_WIDTH + TRAY_WIDTH
PANEL_HEIGHT = CONVERT_HEIGHT + HOLD_HEIGHT
CARD_WIDTH, CARD_HEIGHT, THUMB_SIZE = 100, 80, 44
BORDER = 1   # .sizer-panel 테두리·구분선 두께 — 위젯 요청 크기에서 빼야 창이 위 크기와 정확히 맞는다

# macOS ShelfController 와 같은 시간(ms)·여유(px).
POLL_MS = 80
EXPAND_DWELL_MS = 180
COLLAPSE_DELAY_MS = 400
FLASH_MS = 1600
NEW_BADGE_MS = 4000
BAND_SLACK = 4
STAY_MARGIN = 10

PANEL_DEFAULTS = {"enabled": True, "side": "right", "addResults": True}


# ── 순수 로직 ───────────────────────────────────────────────────────────────────

def is_supported(path, image_enabled):
    ext = os.path.splitext(path)[1][1:].lower()
    return ext in VIDEO_EXTENSIONS or (image_enabled and ext in IMAGE_EXTENSIONS)


def supported_paths(paths, image_enabled):
    """변환존이 받는 파일(DropIngest.supportedURLs 와 같은 규칙)."""
    return [p for p in paths if is_supported(p, image_enabled)]


def panel_frame(workarea, side, expanded):
    """(x, y, 폭, 높이). 작업 영역의 도킹 가장자리에 붙이고 세로 가운데."""
    x, y, width, height = workarea
    panel_width = EXPANDED_WIDTH if expanded else HANDLE_WIDTH
    top = y + max(0, height - PANEL_HEIGHT) // 2
    left = x if side == "left" else x + width - panel_width
    return (left, top, panel_width, PANEL_HEIGHT)


def handle_rect(side):
    """접힌 상태에서 보이고 입력을 받는 창 안 영역(창은 늘 펼친 크기) — (x, y, 폭, 높이)."""
    x = 0 if side == "left" else EXPANDED_WIDTH - HANDLE_WIDTH
    return (x, 0, HANDLE_WIDTH, PANEL_HEIGHT)


def contains(frame, point, margin=0):
    fx, fy, fw, fh = frame
    px, py = point
    return fx - margin <= px < fx + fw + margin and fy - margin <= py < fy + fh + margin


def in_handle_band(point, workarea, side):
    """접힌 탭 위(가장자리 쪽 여유 포함)에 포인터가 있는지 — 머물면 펼친다."""
    x, _, width, _ = workarea
    _, top, _, height = panel_frame(workarea, side, False)
    px, py = point
    if not top <= py < top + height:
        return False
    if side == "left":
        return x - 1 <= px <= x + HANDLE_WIDTH + BAND_SLACK
    return x + width - HANDLE_WIDTH - BAND_SLACK <= px <= x + width


def zone_at(x, y, side, expanded, show_convert=True):
    """패널 안 좌표(왼쪽 위 원점)의 드롭 존. 접힘·핸들 열은 모두 보관(macOS ShelfDropZone.at 과 같다)."""
    if not (expanded and show_convert):
        return "hold"
    in_handle = x < HANDLE_WIDTH if side == "left" else x >= EXPANDED_WIDTH - HANDLE_WIDTH
    if in_handle:
        return "hold"
    return "convert" if y <= CONVERT_HEIGHT else "hold"


def convert_zone_view(active_zone, rejected, flash):
    """변환존 표시(상태, 제목, 부제, 아이콘). flash 는 None · ("success", n) · ("reject",)."""
    if (active_zone == "convert" and rejected) or flash == ("reject",):
        return ("reject", "변환할 수 없는 형식", "영상·이미지 파일만 가능합니다", "action-unavailable-symbolic")
    if flash and flash[0] == "success":
        return ("success", f"{flash[1]}개 변환 시작", "변환을 시작합니다", "object-select-symbolic")
    if active_zone == "convert":
        return ("active", "여기에 놓기", "놓으면 변환을 시작합니다", "document-save-symbolic")
    return ("idle", "드롭하여 변환", "영상·이미지 · Files에서 끌어오기", "document-save-symbolic")


class ShelfStore:
    """보관 트레이 목록 — 원본 경로를 참조로 담는다(macOS ShelfStore). 담은 순서대로, 변환 결과만 맨 앞."""

    def __init__(self):
        self.items = []   # [{"path": 절대경로, "new": bool}]

    @staticmethod
    def _normalized(path):
        return os.path.normpath(os.path.abspath(path))

    @property
    def paths(self):
        return [item["path"] for item in self.items]

    def __len__(self):
        return len(self.items)

    def add(self, paths):
        added = 0
        for path in paths:
            path = self._normalized(path)
            if path not in self.paths:
                self.items.append({"path": path, "new": False})
                added += 1
        return added

    def insert_front(self, path):
        path = self._normalized(path)
        if path in self.paths:
            return False
        self.items.insert(0, {"path": path, "new": True})
        return True

    def clear_new(self, path):
        for item in self.items:
            if item["path"] == path:
                item["new"] = False

    def remove(self, paths):
        targets = {self._normalized(p) for p in paths}
        before = len(self.items)
        self.items = [item for item in self.items if item["path"] not in targets]
        return before - len(self.items)

    def prune_missing(self, exists=os.path.exists):
        """이동으로 끌어냈거나 지워진 항목을 뺀다."""
        missing = [path for path in self.paths if not exists(path)]
        self.remove(missing)
        return missing

    def clear(self):
        self.items = []


def new_results(jobs, seen):
    """최근 변환(status.json recent, 최신이 앞)에서 처음 보는 성공 결과의 경로를 오래된 것부터.
    seen 은 제자리에서 갱신된다 — 트레이는 처음 한 번 호출해 기존 결과를 '본 것'으로 만든다."""
    fresh = []
    for job in reversed(jobs or []):
        key = (job.get("source"), job.get("date"))
        if key in seen:
            continue
        seen.add(key)
        if job.get("success") and job.get("output"):
            fresh.append(job["output"])
    return fresh


def format_size(size):
    """"12.3 MB (12,345,678바이트)" — macOS 정보 보기와 같은 표기."""
    units = ["B", "KB", "MB", "GB", "TB"]
    value, unit = float(size), 0
    while value >= 1000 and unit < len(units) - 1:
        value /= 1000
        unit += 1
    human = f"{int(value)} {units[unit]}" if unit == 0 else f"{value:.1f} {units[unit]}"
    return f"{human} ({size:,}바이트)"


def format_date(timestamp):
    return datetime.datetime.fromtimestamp(timestamp).strftime("%Y-%m-%d %H:%M:%S")


def info_rows(path, created=None):
    """정보 보기·툴팁에 보일 (라벨, 값). 파일이 없으면 경로와 안내만(ShelfFileInfo.rows)."""
    try:
        st = os.stat(path)
    except OSError:
        return [("경로", path), ("상태", "파일을 찾을 수 없음(이동 또는 삭제됨)")]
    rows = [("경로", path)]
    if not stat.S_ISDIR(st.st_mode):
        rows.append(("크기", format_size(st.st_size)))
    if created:
        rows.append(("생성일", format_date(created)))
    rows.append(("수정일", format_date(st.st_mtime)))
    return rows


def tooltip_markup(name, rows):
    """카드 툴팁(Pango 마크업): 굵은 파일명 + 정보 행."""
    def escape(text):
        return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    return "\n".join([f"<b>{escape(name)}</b>"] + [f"{escape(label)}: {escape(value)}" for label, value in rows])


def paths_text(paths):
    """경로 이름 복사: 파일명을 포함한 절대경로, 여러 개면 줄마다 하나."""
    return "\n".join(os.path.normpath(os.path.abspath(p)) for p in paths)


def panel_config(doc):
    section = doc.get("panel") if isinstance(doc, dict) else None
    section = section if isinstance(section, dict) else {}
    config = dict(PANEL_DEFAULTS)
    for key in ("enabled", "addResults"):
        if isinstance(section.get(key), bool):
            config[key] = section[key]
    if section.get("side") in ("left", "right"):
        config["side"] = section["side"]
    return config


def image_enabled(doc):
    image = doc.get("image") if isinstance(doc, dict) else None
    value = image.get("enabled") if isinstance(image, dict) else None
    return value if isinstance(value, bool) else True


def set_config_value(path, section, name, value):
    """설정 파일을 새로 읽어 한 값만 고쳐 원자적으로 쓴다. 실패하면 오류 문자열."""
    try:
        with open(path, encoding="utf-8") as f:
            doc = json.load(f)
    except FileNotFoundError:
        doc = {}
    except ValueError:
        return "설정 파일의 JSON 형식이 잘못됐습니다"
    except OSError as error:
        return f"설정 파일을 읽을 수 없습니다: {error}"
    if not isinstance(doc, dict):
        return "설정 파일의 최상위가 JSON 객체가 아닙니다"
    if not isinstance(doc.get(section), dict):
        doc[section] = {}
    doc[section][name] = value
    directory = os.path.dirname(path)
    try:
        os.makedirs(directory, exist_ok=True)
        fd, tmp = tempfile.mkstemp(prefix=".config-", suffix=".json", dir=directory)
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(doc, f, ensure_ascii=False, indent=2)
            f.write("\n")
        os.replace(tmp, path)
    except OSError as error:
        return f"설정을 저장하지 못했습니다: {error}"
    return None


def thumbnail_kind(path):
    ext = os.path.splitext(path)[1][1:].lower()
    if ext in VIDEO_EXTENSIONS:
        return "video"
    if ext in IMAGE_EXTENSIONS or ext in ("webp", "avif", "svg"):
        return "image"
    return "other"


def thumbnail_cache_path(path, mtime, cache_dir):
    digest = hashlib.sha1(f"{path}:{mtime}".encode("utf-8")).hexdigest()
    return os.path.join(cache_dir, digest + ".png")


# ── 창 모양(X SHAPE) ───────────────────────────────────────────────────────────

class XShape:
    """창의 입력 영역을 사각형 하나로 좁히거나(접힘) 되돌린다(펼침). Xlib SHAPE 를 ctypes 로 부른다
    (GTK 의 input_shape_combine_region 은 python3-gi-cairo 가 필요해 쓰지 않는다)."""

    SHAPE_INPUT, SHAPE_SET = 2, 0

    class _Rect(ctypes.Structure):
        _fields_ = [("x", ctypes.c_short), ("y", ctypes.c_short),
                    ("width", ctypes.c_ushort), ("height", ctypes.c_ushort)]

    def __init__(self, gdk_window, display_name):
        import gi
        gi.require_version("GdkX11", "3.0")
        from gi.repository import GdkX11  # noqa: F401 — GdkWindow 에 get_xid() 를 붙인다
        self.xlib = ctypes.CDLL(ctypes.util.find_library("X11") or "libX11.so.6")
        self.xext = ctypes.CDLL(ctypes.util.find_library("Xext") or "libXext.so.6")
        self.xlib.XOpenDisplay.restype = ctypes.c_void_p
        self.xlib.XOpenDisplay.argtypes = [ctypes.c_char_p]
        self.xlib.XFlush.argtypes = [ctypes.c_void_p]
        self.xext.XShapeCombineRectangles.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_int, ctypes.c_int,
                                                      ctypes.c_int, ctypes.c_void_p, ctypes.c_int, ctypes.c_int,
                                                      ctypes.c_int]
        self.xext.XShapeCombineMask.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_int, ctypes.c_int,
                                                ctypes.c_int, ctypes.c_ulong, ctypes.c_int]
        self.display = self.xlib.XOpenDisplay(display_name.encode() if display_name else None)
        if not self.display:
            raise OSError(f"X 디스플레이를 열 수 없습니다: {display_name}")
        self.xid = gdk_window.get_xid()
        self.current = "unset"

    def set(self, rect):
        """rect=(x, y, 폭, 높이) 로 입력 영역을 좁히거나 None 이면 창 전체로."""
        if rect == self.current:
            return
        if rect is None:
            self.xext.XShapeCombineMask(self.display, self.xid, self.SHAPE_INPUT, 0, 0, 0, self.SHAPE_SET)
        else:
            region = self._Rect(*rect)
            self.xext.XShapeCombineRectangles(self.display, self.xid, self.SHAPE_INPUT, 0, 0, ctypes.byref(region), 1,
                                              self.SHAPE_SET, 0)
        self.xlib.XFlush(self.display)
        self.current = rect


# ── GTK 패널 ────────────────────────────────────────────────────────────────────

CSS = b"""
window.sizer-window { background-color: transparent; }
.sizer-panel { background-color: rgba(30, 30, 38, 0.93); border: 1px solid rgba(255, 255, 255, 0.12); color: #ffffff; }
.sizer-panel.right { border-radius: 24px 0 0 24px; border-right-width: 0; }
.sizer-panel.left { border-radius: 0 24px 24px 0; border-left-width: 0; }
.sizer-panel label { color: #ffffff; }
.sizer-panel image { color: #ffffff; }
.sizer-panel scrolledwindow, .sizer-panel viewport, .sizer-panel flowbox, .sizer-panel stack { background-color: transparent; }
.edge-divider { background-color: rgba(255, 255, 255, 0.12); min-width: 1px; min-height: 1px; }
.handle-logo { background-image: linear-gradient(135deg, #0EA5E9, #6366F1, #8B5CF6); border-radius: 5px; min-width: 15px; min-height: 15px; }
.handle-chevron { color: rgba(255, 255, 255, 0.45); }
.handle-count { background-color: #6366F1; border-radius: 9px; min-width: 18px; min-height: 18px; font-size: 10px; font-weight: 800; }
.convert-zone { border-radius: 18px; border: 2px dashed rgba(255, 255, 255, 0.20); background-color: rgba(255, 255, 255, 0.05); padding: 0 18px; }
.convert-zone.active { border: 2px solid #6366F1; background-color: rgba(99, 102, 241, 0.26); }
.convert-zone.success { border: 2px solid #22C55E; background-color: rgba(34, 197, 94, 0.14); }
.convert-zone.reject { border: 2px solid #F59E0B; background-color: rgba(245, 158, 11, 0.16); }
.cz-badge { border-radius: 13px; background-image: linear-gradient(135deg, #0EA5E9, #6366F1, #8B5CF6); min-width: 44px; min-height: 44px; }
.convert-zone.success .cz-badge { background-image: none; background-color: #22C55E; }
.convert-zone.reject .cz-badge { background-image: none; background-color: #F59E0B; }
.cz-title { font-size: 15px; font-weight: bold; }
.cz-subtitle { font-size: 12px; color: rgba(255, 255, 255, 0.62); }
.hold-title { font-size: 14px; font-weight: bold; }
.count-pill { background-color: rgba(255, 255, 255, 0.16); border-radius: 9px; padding: 0 7px; font-size: 11px; font-weight: bold; }
.sizer-panel button.clear-button { background-color: transparent; background-image: none; border: none; box-shadow: none; text-shadow: none; padding: 2px 6px; min-height: 0; }
.sizer-panel button.clear-button:hover { background-color: rgba(255, 255, 255, 0.10); }
.sizer-panel button.clear-button label { font-size: 11px; color: rgba(255, 255, 255, 0.8); }
.hold-body { border: 2px solid transparent; border-radius: 12px; margin: 0 6px 6px 6px; }
.hold-body.active { border-color: rgba(99, 102, 241, 0.85); background-color: rgba(255, 255, 255, 0.06); }
.empty-title { font-size: 13px; font-weight: 600; color: rgba(255, 255, 255, 0.8); }
.empty-subtitle { font-size: 10px; color: rgba(255, 255, 255, 0.45); }
.sizer-panel flowboxchild { padding: 0; background-color: transparent; border-radius: 12px; }
.shelf-card { border-radius: 12px; background-color: rgba(255, 255, 255, 0.06); padding: 6px 4px 4px 4px; }
.sizer-panel flowboxchild:selected .shelf-card { background-color: rgba(99, 102, 241, 0.55); }
.card-name { font-size: 10px; }
.new-badge { background-color: #22C55E; border-radius: 5px; padding: 0 4px; margin: 3px; font-size: 9px; font-weight: 800; }
.sizer-panel button.remove-button { min-width: 20px; min-height: 20px; padding: 0; margin: 3px; border-radius: 10px; border: none; box-shadow: none; background-image: none; background-color: rgba(0, 0, 0, 0.65); color: #ffffff; text-shadow: none; -gtk-icon-shadow: none; }
.sizer-panel button.remove-button:hover { background-color: rgba(0, 0, 0, 0.85); }
.sizer-panel button.remove-button image { color: #ffffff; }
"""


class Panel:
    """가장자리 드롭·셸프 패널. 트레이가 apply()·add_results()·toggle_from_shortcut() 을 부른다."""

    def __init__(self, gi, convert, image_enabled_fn):
        self.Gtk, self.Gdk, self.GLib, self.Gio = gi["Gtk"], gi["Gdk"], gi["GLib"], gi["Gio"]
        self.GdkPixbuf, self.Pango = gi["GdkPixbuf"], gi["Pango"]
        self.convert = convert              # (경로 목록) → 변환을 맡긴 개수
        self.image_enabled = image_enabled_fn
        self.store = ShelfStore()
        self.enabled = False
        self.side = "right"
        self.window = None
        self.shape = None                   # XShape · False(쓸 수 없음 → 크기 조절로 펼침)
        self.placed_frame = None
        self.expanded = False
        self.workarea = None
        self.holds = set()                  # 끌어내기·메뉴·정보 창·단축키로 연 동안 접지 않는다
        self.pointer_entered = False
        self.sources = {"poll": 0, "expand": 0, "collapse": 0, "flash": 0}
        self.active_zone = None
        self.rejected = False
        self.flash = None
        self.drag_paths = None
        self.drag_zone = "hold"
        self.data_requested = False
        self.dropping = False
        self.drop_point = (0, 0)
        self.thumbs = {}                    # 경로 → pixbuf (카드를 다시 만들어도 재사용)
        cache_home = os.environ.get("XDG_CACHE_HOME", "")
        cache_home = cache_home if cache_home.startswith("/") else os.path.expanduser("~/.cache")
        self.thumb_dir = os.path.join(cache_home, "sizer", "thumbs")

        provider = self.Gtk.CssProvider()
        provider.load_from_data(CSS)
        self.Gtk.StyleContext.add_provider_for_screen(
            self.Gdk.Screen.get_default(), provider, self.Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        self.uri_target = self.Gtk.TargetEntry.new("text/uri-list", 0, 0)
        self.uri_atom = self.Gdk.Atom.intern("text/uri-list", False)

    # 트레이가 부르는 API

    def apply(self, enabled, side):
        if side != self.side:
            self.side = side
            if self.window:
                self._destroy_window()
        self.enabled = enabled
        if enabled:
            self.show()
        else:
            self.hide()

    def show(self):
        if self.window is None:
            self._build_window()
        self.workarea = self._workarea_at(self._pointer())
        self.expanded = False
        self.window.show_all()
        self._refresh_items()
        self._place()
        if not self.sources["poll"]:
            self.sources["poll"] = self.GLib.timeout_add(POLL_MS, self._poll)

    def hide(self):
        self._cancel("poll")
        self._cancel("expand")
        self._cancel("collapse")
        if self.window:
            self.window.hide()

    def add_results(self, paths):
        """변환 결과를 보관 트레이 맨 앞에 NEW 로 얹는다(macOS S5)."""
        added = [p for p in paths if os.path.exists(p) and self.store.insert_front(p)]
        if not added:
            return
        self._refresh_items()
        for path in added:
            self.GLib.timeout_add(NEW_BADGE_MS, self._clear_new, path)

    def toggle_from_shortcut(self):
        """사용자 지정 단축키(sizer-tray --toggle-panel): 펼쳐서 포인터가 들어왔다 나갈 때까지 유지, 다시 누르면 접기."""
        if not self.window or not self.window.get_visible():
            return
        if self.expanded:
            self.holds.discard("keyboard")
            self._collapse()
            return
        self.pointer_entered = False
        self.holds.add("keyboard")
        self.expand()
        self.window.present()

    # 창

    def _build_window(self):
        Gtk, Gdk = self.Gtk, self.Gdk
        window = Gtk.Window()
        window.set_title("Sizer 패널")
        window.set_decorated(False)
        window.set_type_hint(Gdk.WindowTypeHint.UTILITY)
        window.set_keep_above(True)
        window.set_skip_taskbar_hint(True)
        window.set_skip_pager_hint(True)
        window.stick()
        window.set_gravity(Gdk.Gravity.NORTH_WEST if self.side == "left" else Gdk.Gravity.NORTH_EAST)
        visual = window.get_screen().get_rgba_visual()
        if visual:
            window.set_visual(visual)
        window.set_app_paintable(True)
        window.get_style_context().add_class("sizer-window")
        window.connect("key-press-event", self._on_key)
        window.connect("delete-event", lambda *_: True)   # Alt+F4 로 닫지 않는다(메뉴에서 끈다)

        root = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        # 창은 늘 펼친 크기 — 접혀 트레이가 숨으면 핸들만 도킹 가장자리에 붙어 그려진다.
        root.set_halign(Gtk.Align.START if self.side == "left" else Gtk.Align.END)
        root.get_style_context().add_class("sizer-panel")
        root.get_style_context().add_class(self.side)
        self.handle = self._build_handle()
        self.divider = Gtk.Box()
        self.divider.get_style_context().add_class("edge-divider")
        self.tray = self._build_tray()
        widgets = [self.handle, self.divider, self.tray] if self.side == "left" else [self.tray, self.divider, self.handle]
        for widget in widgets:
            root.pack_start(widget, widget is self.tray, True, 0)
        window.add(root)

        window.drag_dest_set(Gtk.DestDefaults(0), [self.uri_target], Gdk.DragAction.COPY | Gdk.DragAction.MOVE)
        window.connect("drag-motion", self._on_drag_motion)
        window.connect("drag-leave", self._on_drag_leave)
        window.connect("drag-drop", self._on_drag_drop)
        window.connect("drag-data-received", self._on_drag_data_received)
        self.window = window

    def _destroy_window(self):
        self.hide()
        self.window.destroy()
        self.window = None
        self.shape = None
        self.placed_frame = None
        self.holds.clear()

    def _build_handle(self):
        Gtk = self.Gtk
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        box.set_size_request(HANDLE_WIDTH - BORDER, -1)   # + 바깥 테두리 1px = 22
        box.set_margin_top(12)
        box.set_margin_bottom(12)
        logo = Gtk.Box()
        logo.get_style_context().add_class("handle-logo")
        logo.set_halign(Gtk.Align.CENTER)
        chevron = Gtk.Image.new_from_icon_name("pan-end-symbolic" if self.side == "left" else "pan-start-symbolic",
                                               Gtk.IconSize.MENU)
        chevron.get_style_context().add_class("handle-chevron")
        self.handle_count = Gtk.Label()
        self.handle_count.get_style_context().add_class("handle-count")
        self.handle_count.set_halign(Gtk.Align.CENTER)
        self.handle_count.set_no_show_all(True)
        box.pack_start(logo, False, False, 0)
        box.pack_start(chevron, False, False, 0)
        box.pack_end(self.handle_count, False, False, 0)
        return box

    def _build_tray(self):
        Gtk = self.Gtk
        tray = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        tray.set_size_request(TRAY_WIDTH - BORDER, PANEL_HEIGHT - 2 * BORDER)   # + 구분선 1px, 위아래 테두리
        tray.set_no_show_all(True)

        # 위 — 변환 드롭존
        self.convert_zone = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=14)
        self.convert_zone.get_style_context().add_class("convert-zone")
        self.convert_zone.set_margin_start(14)
        self.convert_zone.set_margin_end(14)
        self.convert_zone.set_margin_top(14)
        self.convert_zone.set_margin_bottom(8)
        self.convert_zone.set_size_request(-1, CONVERT_HEIGHT - 22)
        badge = Gtk.Box()
        badge.get_style_context().add_class("cz-badge")
        badge.set_valign(Gtk.Align.CENTER)
        self.cz_icon = Gtk.Image()
        self.cz_icon.set_pixel_size(20)
        badge.set_center_widget(self.cz_icon)
        texts = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=3)
        texts.set_valign(Gtk.Align.CENTER)
        self.cz_title = Gtk.Label(xalign=0)
        self.cz_title.get_style_context().add_class("cz-title")
        self.cz_subtitle = Gtk.Label(xalign=0)
        self.cz_subtitle.get_style_context().add_class("cz-subtitle")
        texts.pack_start(self.cz_title, False, False, 0)
        texts.pack_start(self.cz_subtitle, False, False, 0)
        self.convert_zone.pack_start(badge, False, False, 0)
        self.convert_zone.pack_start(texts, True, True, 0)
        tray.pack_start(self.convert_zone, False, False, 0)
        divider = Gtk.Box()
        divider.get_style_context().add_class("edge-divider")
        tray.pack_start(divider, False, False, 0)

        # 아래 — 보관 트레이
        header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        header.set_size_request(-1, 40)
        header.set_margin_start(14)
        header.set_margin_end(10)
        title = Gtk.Label(label="파일 보관")
        title.get_style_context().add_class("hold-title")
        title.set_valign(Gtk.Align.CENTER)
        self.count_pill = Gtk.Label()
        self.count_pill.get_style_context().add_class("count-pill")
        self.count_pill.set_valign(Gtk.Align.CENTER)   # 머리줄 높이로 늘어나 세로 캡슐이 되지 않게
        self.count_pill.set_no_show_all(True)
        self.clear_button = Gtk.Button(label="전체 지우기")
        self.clear_button.get_style_context().add_class("clear-button")
        self.clear_button.set_no_show_all(True)
        self.clear_button.set_valign(Gtk.Align.CENTER)
        self.clear_button.connect("clicked", lambda _b: self._clear_all())
        header.pack_start(title, False, False, 0)
        header.pack_start(self.count_pill, False, False, 0)
        header.pack_end(self.clear_button, False, False, 0)
        tray.pack_start(header, False, False, 0)

        self.hold_body = Gtk.Stack()
        self.hold_body.get_style_context().add_class("hold-body")
        empty = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        empty.set_valign(Gtk.Align.CENTER)
        empty_icon = Gtk.Image.new_from_icon_name("folder-download-symbolic", Gtk.IconSize.DND)
        empty_icon.set_opacity(0.5)
        empty_title = Gtk.Label(label="여기에 파일을 모아 두세요")
        empty_title.get_style_context().add_class("empty-title")
        empty_subtitle = Gtk.Label(label="Files에서 끌어와 담고, 필요한 곳으로 다시 끌어다 놓으세요")
        empty_subtitle.get_style_context().add_class("empty-subtitle")
        for widget in (empty_icon, empty_title, empty_subtitle):
            empty.pack_start(widget, False, False, 0)
        self.hold_body.add_named(empty, "empty")

        scroller = Gtk.ScrolledWindow()
        scroller.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        self.flow = Gtk.FlowBox()
        self.flow.set_selection_mode(Gtk.SelectionMode.MULTIPLE)
        self.flow.set_activate_on_single_click(False)
        self.flow.set_homogeneous(True)
        self.flow.set_min_children_per_line(4)
        self.flow.set_max_children_per_line(4)
        self.flow.set_column_spacing(6)
        self.flow.set_row_spacing(6)
        self.flow.set_valign(Gtk.Align.START)
        for side in ("start", "end", "top", "bottom"):
            getattr(self.flow, f"set_margin_{side}")(6)
        self.flow.connect("child-activated", lambda _f, child: self._open([child.path]))
        scroller.add(self.flow)
        self.hold_body.add_named(scroller, "items")
        tray.pack_start(self.hold_body, True, True, 0)

        for child in tray.get_children():
            child.show_all()
        self._update_convert_zone()
        return tray

    # 배치 · 펼침

    def _pointer(self):
        seat = self.Gdk.Display.get_default().get_default_seat()
        _screen, x, y = seat.get_pointer().get_position()
        return (x, y)

    def _workarea_at(self, point):
        display = self.Gdk.Display.get_default()
        monitor = display.get_monitor_at_point(*point) or display.get_primary_monitor() or display.get_monitor(0)
        rect = monitor.get_workarea()
        return (rect.x, rect.y, rect.width, rect.height)

    def _place(self):
        if not self.window or not self.workarea:
            return
        self.tray.set_visible(self.expanded)
        self.divider.set_visible(self.expanded)
        shape = self._shape()
        # 입력 모양을 쓸 수 있으면 창은 늘 펼친 크기로 두고 입력 영역만 바꾼다(모듈 설명 참고).
        frame = panel_frame(self.workarea, self.side, True if shape else self.expanded)
        if frame != self.placed_frame:
            x, y, width, height = frame
            self.window.set_size_request(width, height)
            gdk_window = self.window.get_window()
            if gdk_window:
                gdk_window.move_resize(x, y, width, height)   # 이동과 크기를 한 번에 — 따로 하면 제자리로 안 간다
            else:
                self.window.move(x, y)
                self.window.resize(width, height)
            self.placed_frame = frame
        if shape:
            shape.set(None if self.expanded else handle_rect(self.side))

    def _shape(self):
        if self.shape is False:
            return None
        if self.shape is None:
            gdk_window = self.window.get_window() if self.window else None
            if gdk_window is None:
                return None
            try:
                self.shape = XShape(gdk_window, self.Gdk.Display.get_default().get_name())
            except Exception as error:
                print(f"sizer-tray: 창 모양을 바꿀 수 없어 크기 조절로 접고 펼칩니다: {error}", file=sys.stderr)
                self.shape = False
                return None
        return self.shape

    def expand(self):
        self._cancel("collapse")
        self._cancel("expand")
        if self.expanded:
            return
        self.expanded = True
        self._place()

    def schedule_collapse(self, delay=COLLAPSE_DELAY_MS):
        self._cancel("collapse")
        self.sources["collapse"] = self.GLib.timeout_add(delay, self._collapse_if_idle)

    def _collapse_if_idle(self):
        self.sources["collapse"] = 0
        if not self.expanded or self.holds:
            return False
        if contains(panel_frame(self.workarea, self.side, True), self._pointer(), 8):
            self.schedule_collapse()
            return False
        self._collapse()
        return False

    def _collapse(self):
        self.expanded = False
        self._set_zone(None, False)
        self._place()

    def hold(self, reason):
        self.holds.add(reason)
        self._cancel("collapse")

    def release(self, reason):
        if reason in self.holds:
            self.holds.discard(reason)
            if not self.holds:
                self.schedule_collapse()

    def _poll(self):
        if not self.window or not self.window.get_visible():
            self.sources["poll"] = 0
            return False
        point = self._pointer()
        if not self.expanded:
            if not self.holds:
                workarea = self._workarea_at(point)
                if workarea != self.workarea:      # 다른 모니터로 가면 그 가장자리로
                    self.workarea = workarea
                    self._place()
                    return True
            if in_handle_band(point, self.workarea, self.side):
                if not self.sources["expand"]:
                    self.sources["expand"] = self.GLib.timeout_add(EXPAND_DWELL_MS, self._dwell_expand)
            else:
                self._cancel("expand")
            return True

        inside = contains(panel_frame(self.workarea, self.side, True), point, STAY_MARGIN)
        if "keyboard" in self.holds:
            if inside:
                self.pointer_entered = True
            elif self.pointer_entered:
                self.release("keyboard")
        if not self.holds:
            if inside:
                self._cancel("collapse")
            elif not self.sources["collapse"]:
                self.schedule_collapse()
        return True

    def _dwell_expand(self):
        self.sources["expand"] = 0
        self.expand()
        return False

    def _cancel(self, name):
        if self.sources[name]:
            self.GLib.source_remove(self.sources[name])
            self.sources[name] = 0

    # 드롭(파일을 패널로)

    def _on_drag_motion(self, widget, context, x, y, time):
        self.expand()
        self.drag_zone = zone_at(x, y, self.side, self.expanded)
        if self.drag_paths is None:
            if not self.data_requested:
                self.data_requested = True
                widget.drag_get_data(context, self.uri_atom, time)
            return True
        self._evaluate_drag(context, time)
        return True

    def _evaluate_drag(self, context, time):
        Gdk = self.Gdk
        if self.drag_zone == "convert":
            ok = bool(supported_paths(self.drag_paths, self.image_enabled()))
            self._set_zone("convert", not ok)
            Gdk.drag_status(context, Gdk.DragAction.COPY if ok else Gdk.DragAction(0), time)
        else:
            self._set_zone("hold", False)
            Gdk.drag_status(context, Gdk.DragAction.COPY, time)

    def _on_drag_data_received(self, widget, context, x, y, data, info, time):
        paths = [p for p in (self.Gio.File.new_for_uri(u).get_path() for u in (data.get_uris() or [])) if p]
        if self.dropping:
            self.dropping = False
            self.data_requested = False
            self.drag_paths = None
            self.Gtk.drag_finish(context, bool(paths), False, time)
            self._handle_drop(paths)
        else:
            self.drag_paths = paths
            self._evaluate_drag(context, time)

    def _on_drag_drop(self, widget, context, x, y, time):
        self.dropping = True
        self.drop_point = (x, y)
        widget.drag_get_data(context, self.uri_atom, time)
        return True

    def _on_drag_leave(self, widget, context, time):
        self.drag_paths = None
        self.data_requested = False
        self._set_zone(None, False)
        if not self.dropping:
            self.schedule_collapse()

    def _handle_drop(self, paths):
        zone = zone_at(self.drop_point[0], self.drop_point[1], self.side, self.expanded)
        self._set_zone(None, False)
        if zone == "convert":
            count = self.convert(paths)
            self._flash(("success", count) if count else ("reject",))
            self.schedule_collapse(1400)
        else:
            if self.store.add(paths):
                self._refresh_items()
            self.schedule_collapse(800)

    def _set_zone(self, zone, rejected):
        if (zone, rejected) == (self.active_zone, self.rejected):
            return
        self.active_zone, self.rejected = zone, rejected
        self._update_convert_zone()

    def _flash(self, flash):
        self.flash = flash
        self._update_convert_zone()
        self._cancel("flash")
        self.sources["flash"] = self.GLib.timeout_add(FLASH_MS, self._end_flash)

    def _end_flash(self):
        self.sources["flash"] = 0
        self.flash = None
        self._update_convert_zone()
        return False

    def _update_convert_zone(self):
        state, title, subtitle, icon = convert_zone_view(self.active_zone, self.rejected, self.flash)
        context = self.convert_zone.get_style_context()
        for name in ("idle", "active", "success", "reject"):
            context.remove_class(name)
        context.add_class(state)
        self.cz_title.set_text(title)
        self.cz_subtitle.set_text(subtitle)
        self.cz_icon.set_from_icon_name(icon, self.Gtk.IconSize.DND)
        self.cz_icon.set_pixel_size(20)
        body = self.hold_body.get_style_context()
        (body.add_class if self.active_zone == "hold" else body.remove_class)("active")

    # 보관 트레이

    def _refresh_items(self):
        if not self.window:
            return
        selected = set(self._selected_paths())
        for child in self.flow.get_children():
            self.flow.remove(child)
            child.destroy()
        for item in self.store.items:
            child = self._build_card(item)
            self.flow.add(child)
            child.show_all()
            if item["path"] in selected:
                self.flow.select_child(child)
        count = len(self.store)
        self.hold_body.set_visible_child_name("items" if count else "empty")
        for label in (self.count_pill, self.handle_count):
            label.set_text(str(min(count, 99)))
            label.set_visible(count > 0)
        self.clear_button.set_visible(count > 0)

    def _build_card(self, item):
        Gtk, Gdk, Gio = self.Gtk, self.Gdk, self.Gio
        path = item["path"]
        child = Gtk.FlowBoxChild()
        child.path = path

        thumb = Gtk.Image()
        thumb.set_pixel_size(THUMB_SIZE)
        self._load_thumbnail(thumb, child, path)
        name = Gtk.Label(label=os.path.basename(path))
        name.set_ellipsize(self.Pango.EllipsizeMode.MIDDLE)
        name.set_max_width_chars(12)
        name.get_style_context().add_class("card-name")
        card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        card.get_style_context().add_class("shelf-card")
        card.set_size_request(CARD_WIDTH, CARD_HEIGHT)
        card.pack_start(thumb, True, True, 0)
        card.pack_start(name, False, False, 0)

        overlay = Gtk.Overlay()
        overlay.add(card)
        badge = Gtk.Label(label="NEW")
        badge.get_style_context().add_class("new-badge")
        badge.set_halign(Gtk.Align.START)
        badge.set_valign(Gtk.Align.START)
        badge.set_no_show_all(True)
        badge.set_visible(item["new"])
        remove = Gtk.Button.new_from_icon_name("window-close-symbolic", Gtk.IconSize.MENU)
        remove.get_style_context().add_class("remove-button")
        remove.set_halign(Gtk.Align.END)
        remove.set_valign(Gtk.Align.START)
        remove.set_no_show_all(True)
        remove.set_tooltip_text("목록에서 제거")
        remove.connect("clicked", lambda _b: self._remove([path]))
        overlay.add_overlay(badge)
        overlay.add_overlay(remove)

        events = Gtk.EventBox()
        events.add(overlay)
        events.add_events(Gdk.EventMask.ENTER_NOTIFY_MASK | Gdk.EventMask.LEAVE_NOTIFY_MASK)
        events.connect("enter-notify-event", lambda _w, _e: remove.set_visible(True) or False)
        events.connect("leave-notify-event", lambda _w, e: e.detail == Gdk.NotifyType.INFERIOR or remove.set_visible(False) or False)
        events.connect("button-press-event", self._on_card_button, child)
        events.drag_source_set(Gdk.ModifierType.BUTTON1_MASK, [self.uri_target],
                               Gdk.DragAction.COPY | Gdk.DragAction.MOVE)
        events.connect("drag-begin", self._on_card_drag_begin, child)
        events.connect("drag-data-get", self._on_card_drag_data_get)
        events.connect("drag-end", self._on_card_drag_end)
        child.add(events)
        child.set_tooltip_markup(tooltip_markup(os.path.basename(path), info_rows(path, self._created_time(path))))
        return child

    def _load_thumbnail(self, image, child, path):
        Gtk, Gio = self.Gtk, self.Gio
        child.thumb_pixbuf = self.thumbs.get(path)
        if child.thumb_pixbuf:
            image.set_from_pixbuf(child.thumb_pixbuf)
            return
        content_type, _ = Gio.content_type_guess(path, None)
        icon = Gio.ThemedIcon.new("folder") if os.path.isdir(path) else Gio.content_type_get_icon(content_type)
        image.set_from_gicon(icon, Gtk.IconSize.DIALOG)
        image.set_pixel_size(THUMB_SIZE)
        kind = thumbnail_kind(path)
        if kind == "other" or not os.path.isfile(path):
            return

        def work():
            source = path
            if kind == "video":
                source = self._video_frame(path)
            if not source:
                return
            try:
                pixbuf = self.GdkPixbuf.Pixbuf.new_from_file_at_scale(source, THUMB_SIZE * 2, THUMB_SIZE * 2, True)
            except Exception:   # 디코더 없는 형식(AVIF 등)은 아이콘으로 둔다
                return
            self.GLib.idle_add(self._set_thumbnail, image, child, path, pixbuf)

        threading.Thread(target=work, daemon=True).start()

    def _video_frame(self, path):
        try:
            cache = thumbnail_cache_path(path, os.path.getmtime(path), self.thumb_dir)
        except OSError:
            return None
        if os.path.exists(cache):
            return cache
        ffmpeg = shutil.which("ffmpeg") or "/usr/bin/ffmpeg"
        os.makedirs(self.thumb_dir, exist_ok=True)
        for seek in ("1", "0"):   # 1초보다 짧은 영상은 첫 프레임
            try:
                subprocess.run([ffmpeg, "-loglevel", "error", "-y", "-ss", seek, "-i", path, "-frames:v", "1",
                                "-vf", "scale=176:176:force_original_aspect_ratio=decrease", cache],
                               timeout=30, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            except (OSError, subprocess.TimeoutExpired):
                return None
            if os.path.exists(cache):
                return cache
        return None

    def _set_thumbnail(self, image, child, path, pixbuf):
        scaled = pixbuf.scale_simple(max(1, pixbuf.get_width() // 2), max(1, pixbuf.get_height() // 2),
                                     self.GdkPixbuf.InterpType.BILINEAR)
        self.thumbs[path] = scaled
        if image.get_parent() is not None:
            image.set_from_pixbuf(scaled)
            child.thumb_pixbuf = scaled
        return False

    def _selected_paths(self):
        return [child.path for child in self.flow.get_selected_children()] if self.window else []

    def _select_only_if_needed(self, child):
        if not child.is_selected():
            self.flow.unselect_all()
            self.flow.select_child(child)

    def _remove(self, paths):
        if self.store.remove(paths):
            self._refresh_items()

    def _clear_all(self):
        self.store.clear()
        self._refresh_items()

    def _clear_new(self, path):
        self.store.clear_new(path)
        self._refresh_items()
        return False

    # 끌어내기(보관 → Files)

    def _on_card_drag_begin(self, widget, context, child):
        self._select_only_if_needed(child)
        self.hold("drag")
        if getattr(child, "thumb_pixbuf", None):
            pixbuf = child.thumb_pixbuf
            self.Gtk.drag_set_icon_pixbuf(context, pixbuf, pixbuf.get_width() // 2, pixbuf.get_height() // 2)

    def _on_card_drag_data_get(self, widget, context, data, info, time):
        data.set_uris([self.Gio.File.new_for_path(p).get_uri() for p in self._selected_paths()])

    def _on_card_drag_end(self, widget, context):
        self.GLib.timeout_add(400, self._after_drag_out)

    def _after_drag_out(self):
        if self.store.prune_missing():   # 이동으로 끌어낸 항목은 사라진다
            self._refresh_items()
        self.release("drag")
        return False

    # 카드 조작

    def _on_card_button(self, widget, event, child):
        if event.type == self.Gdk.EventType.BUTTON_PRESS and event.button == 3:
            self._select_only_if_needed(child)
            self._show_menu(event)
            return True
        return False

    def _show_menu(self, event):
        Gtk = self.Gtk
        paths = self._selected_paths()
        if not paths:
            return
        menu = Gtk.Menu()
        entries = [
            ("열기", lambda: self._open(paths)),
            ("훑어보기", lambda: self._preview(paths[0])),
            ("폴더에서 보기", lambda: self._reveal(paths)),
            ("정보 보기", lambda: self._show_info(paths[0])),
            ("경로 이름 복사", lambda: self._copy_paths(paths)),
            None,
            ("목록에서 제거", lambda: self._remove(paths)),
        ]
        for entry in entries:
            if entry is None:
                menu.append(Gtk.SeparatorMenuItem())
                continue
            label, action = entry
            item = Gtk.MenuItem(label=label)
            item.connect("activate", lambda _i, a=action: a())
            menu.append(item)
        self.hold("menu")
        menu.connect("deactivate", lambda _m: self.GLib.idle_add(lambda: self.release("menu") or False))
        menu.show_all()
        menu.popup_at_pointer(event)
        self.menu = menu

    def _on_key(self, _window, event):
        Gdk = self.Gdk
        key = event.keyval
        paths = self._selected_paths()
        if key == Gdk.KEY_Escape:
            self.flow.unselect_all()
            self.holds.discard("keyboard")
            self.schedule_collapse(0)
            return True
        if not paths:
            return False
        if key == Gdk.KEY_space:
            self._preview(paths[0])
        elif key in (Gdk.KEY_Delete, Gdk.KEY_BackSpace):
            self._remove(paths)
        elif key in (Gdk.KEY_Return, Gdk.KEY_KP_Enter):
            self._open(paths)
        elif key in (Gdk.KEY_c, Gdk.KEY_C) and event.state & Gdk.ModifierType.CONTROL_MASK:
            self._copy_paths(paths)
        else:
            return False
        return True

    def _open(self, paths):
        for path in paths:
            try:
                self.Gio.AppInfo.launch_default_for_uri(self.Gio.File.new_for_path(path).get_uri(), None)
            except self.GLib.Error as error:
                print(f"sizer-tray: 열기 실패 {path}: {error.message}")

    def _preview(self, path):
        """GNOME 훑어보기(Sushi). 이미 떠 있으면 닫는다."""
        Gio, GLib = self.Gio, self.GLib
        uri = Gio.File.new_for_path(path).get_uri()
        bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        handle = ""
        try:
            handle = f"x11:{self.window.get_window().get_xid():x}"
        except Exception:
            pass

        def legacy(source, result):
            try:
                source.call_finish(result)
            except GLib.Error:
                bus.call("org.gnome.NautilusPreviewer", "/org/gnome/NautilusPreviewer", "org.gnome.NautilusPreviewer",
                         "ShowFile", GLib.Variant("(sib)", (uri, 0, True)), None, Gio.DBusCallFlags.NONE, -1, None,
                         None, None)

        bus.call("org.gnome.NautilusPreviewer", "/org/gnome/NautilusPreviewer", "org.gnome.NautilusPreviewer2",
                 "ShowFile", GLib.Variant("(ssb)", (uri, handle, True)), None, Gio.DBusCallFlags.NONE, -1, None,
                 legacy, None)

    def _reveal(self, paths):
        Gio, GLib = self.Gio, self.GLib
        uris = [Gio.File.new_for_path(p).get_uri() for p in paths]
        bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        bus.call("org.freedesktop.FileManager1", "/org/freedesktop/FileManager1", "org.freedesktop.FileManager1",
                 "ShowItems", GLib.Variant("(ass)", (uris, "")), None, Gio.DBusCallFlags.NONE, -1, None, None, None)

    def _copy_paths(self, paths):
        clipboard = self.Gtk.Clipboard.get(self.Gdk.SELECTION_CLIPBOARD)
        clipboard.set_text(paths_text(paths), -1)
        clipboard.store()

    def _created_time(self, path):
        """생성 시각(statx). 파일 시스템이 모르면 None."""
        try:
            info = self.Gio.File.new_for_path(path).query_info("time::created", self.Gio.FileQueryInfoFlags.NONE, None)
        except self.GLib.Error:
            return None
        return info.get_attribute_uint64("time::created") if info.has_attribute("time::created") else None

    def _show_info(self, path):
        Gtk = self.Gtk
        created = self._created_time(path)
        window = Gtk.Window(title=f"정보 — {os.path.basename(path)}")
        window.set_keep_above(True)
        window.set_type_hint(self.Gdk.WindowTypeHint.DIALOG)
        window.set_default_size(480, -1)
        grid = Gtk.Grid(column_spacing=12, row_spacing=6)
        grid.set_border_width(16)
        for row, (label, value) in enumerate(info_rows(path, created)):
            key = Gtk.Label(label=label, xalign=1)
            key.get_style_context().add_class("dim-label")
            key.set_valign(Gtk.Align.START)
            text = Gtk.Label(label=value, xalign=0, selectable=True)
            text.set_line_wrap(True)
            text.set_line_wrap_mode(self.Pango.WrapMode.CHAR)
            text.set_max_width_chars(52)
            grid.attach(key, 0, row, 1, 1)
            grid.attach(text, 1, row, 1, 1)
        window.add(grid)
        reason = f"info-{id(window)}"
        self.hold(reason)
        window.connect("destroy", lambda _w: self.release(reason))
        window.show_all()
