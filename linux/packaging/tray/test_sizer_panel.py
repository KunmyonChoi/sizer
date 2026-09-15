"""sizer_panel 의 순수 로직 테스트(GTK 없이 실행). python3 -m unittest discover -s linux/packaging/tray"""

import json
import os
import sys
import tempfile
import time
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sizer_panel as panel   # noqa: E402

WORKAREA = (66, 32, 2494, 1408)   # 이 개발 머신: 왼쪽 Dock 66px, 위 상단 바 32px, 2560x1440


class GeometryTests(unittest.TestCase):

    def test_right_side_frames_hug_the_edge(self):
        collapsed = panel.panel_frame(WORKAREA, "right", False)
        expanded = panel.panel_frame(WORKAREA, "right", True)
        self.assertEqual(collapsed, (2560 - panel.HANDLE_WIDTH, 32 + (1408 - panel.PANEL_HEIGHT) // 2,
                                     panel.HANDLE_WIDTH, panel.PANEL_HEIGHT))
        self.assertEqual(expanded[0] + expanded[2], 2560, "펼쳐도 오른쪽 끝은 그대로")
        self.assertEqual(expanded[2], panel.EXPANDED_WIDTH)
        self.assertEqual(collapsed[1], expanded[1])

    def test_left_side_starts_after_dock(self):
        self.assertEqual(panel.panel_frame(WORKAREA, "left", False)[0], 66)
        self.assertEqual(panel.panel_frame(WORKAREA, "left", True)[0], 66)

    def test_short_workarea_does_not_go_negative(self):
        self.assertEqual(panel.panel_frame((0, 0, 800, 200), "right", False)[1], 0)

    def test_handle_band(self):
        _, top, _, height = panel.panel_frame(WORKAREA, "right", False)
        middle = top + height // 2
        self.assertTrue(panel.in_handle_band((2559, middle), WORKAREA, "right"), "화면 끝에 댄 포인터")
        self.assertTrue(panel.in_handle_band((2560 - panel.HANDLE_WIDTH - panel.BAND_SLACK, middle), WORKAREA, "right"))
        self.assertFalse(panel.in_handle_band((2500, middle), WORKAREA, "right"))
        self.assertFalse(panel.in_handle_band((2559, top - 1), WORKAREA, "right"), "탭 위아래는 아님")
        self.assertTrue(panel.in_handle_band((70, middle), WORKAREA, "left"))
        self.assertFalse(panel.in_handle_band((2559, middle), WORKAREA, "left"))

    def test_handle_rect_is_the_docked_edge_of_the_full_window(self):
        self.assertEqual(panel.handle_rect("right"), (panel.TRAY_WIDTH, 0, panel.HANDLE_WIDTH, panel.PANEL_HEIGHT))
        self.assertEqual(panel.handle_rect("left"), (0, 0, panel.HANDLE_WIDTH, panel.PANEL_HEIGHT))
        x, _, width, _ = panel.handle_rect("right")
        self.assertEqual(x + width, panel.EXPANDED_WIDTH, "오른쪽 도킹이면 창 오른쪽 끝")
        # 접힌 창에서 드롭 좌표가 핸들 안이면 zone_at 은 보관(펼침 전이라)
        self.assertEqual(panel.zone_at(x + 5, 10, "right", False), "hold")

    def test_contains_with_margin(self):
        frame = (100, 100, 50, 50)
        self.assertTrue(panel.contains(frame, (100, 100)))
        self.assertFalse(panel.contains(frame, (150, 120)))
        self.assertTrue(panel.contains(frame, (155, 120), margin=10))


class ZoneTests(unittest.TestCase):

    def test_top_is_convert_bottom_is_hold(self):
        self.assertEqual(panel.zone_at(200, 10, "right", True), "convert")
        self.assertEqual(panel.zone_at(200, panel.CONVERT_HEIGHT, "right", True), "convert", "경계 포함")
        self.assertEqual(panel.zone_at(200, panel.CONVERT_HEIGHT + 1, "right", True), "hold")

    def test_handle_column_is_never_convert(self):
        self.assertEqual(panel.zone_at(panel.EXPANDED_WIDTH - 5, 10, "right", True), "hold")
        self.assertEqual(panel.zone_at(5, 10, "left", True), "hold")
        self.assertEqual(panel.zone_at(panel.EXPANDED_WIDTH - 5, 10, "left", True), "convert")

    def test_collapsed_or_not_integrated_is_hold(self):
        self.assertEqual(panel.zone_at(10, 10, "right", False), "hold")
        self.assertEqual(panel.zone_at(200, 10, "right", True, show_convert=False), "hold")

    def test_supported_paths_follow_image_setting(self):
        paths = ["/a/clip.MOV", "/a/shot.png", "/a/notes.txt"]
        self.assertEqual(panel.supported_paths(paths, True), ["/a/clip.MOV", "/a/shot.png"])
        self.assertEqual(panel.supported_paths(paths, False), ["/a/clip.MOV"])

    def test_convert_zone_view_priorities(self):
        self.assertEqual(panel.convert_zone_view(None, False, None)[0], "idle")
        self.assertEqual(panel.convert_zone_view("convert", False, None)[1], "여기에 놓기")
        self.assertEqual(panel.convert_zone_view("convert", True, None)[0], "reject")
        self.assertEqual(panel.convert_zone_view(None, False, ("reject",))[0], "reject")
        self.assertEqual(panel.convert_zone_view(None, False, ("success", 3))[1], "3개 변환 시작")
        self.assertEqual(panel.convert_zone_view("hold", False, None)[0], "idle", "보관존 위에서는 변환존이 조용하다")


class StoreTests(unittest.TestCase):

    def test_add_dedupes_and_keeps_order(self):
        store = panel.ShelfStore()
        self.assertEqual(store.add(["/tmp/a.mov", "/tmp/b.png", "/tmp/x/../a.mov"]), 2)
        self.assertEqual(store.paths, ["/tmp/a.mov", "/tmp/b.png"])

    def test_insert_front_marks_new_and_dedupes(self):
        store = panel.ShelfStore()
        store.add(["/tmp/a.mov"])
        self.assertTrue(store.insert_front("/tmp/a_resize.mp4"))
        self.assertFalse(store.insert_front("/tmp/a.mov"))
        self.assertEqual(store.paths, ["/tmp/a_resize.mp4", "/tmp/a.mov"])
        self.assertTrue(store.items[0]["new"])
        store.clear_new("/tmp/a_resize.mp4")
        self.assertFalse(store.items[0]["new"])

    def test_remove_and_clear(self):
        store = panel.ShelfStore()
        store.add(["/tmp/a", "/tmp/b", "/tmp/c"])
        self.assertEqual(store.remove(["/tmp/b", "/tmp/zzz"]), 1)
        self.assertEqual(len(store), 2)
        store.clear()
        self.assertEqual(len(store), 0)

    def test_prune_missing_after_move_out(self):
        with tempfile.TemporaryDirectory() as tmp:
            kept = os.path.join(tmp, "kept.mp4")
            moved = os.path.join(tmp, "moved.mp4")
            for path in (kept, moved):
                open(path, "w").close()
            store = panel.ShelfStore()
            store.add([kept, moved])
            os.remove(moved)
            self.assertEqual(store.prune_missing(), [moved])
            self.assertEqual(store.paths, [kept])


class ResultTests(unittest.TestCase):

    @staticmethod
    def job(source, date, success=True):
        return {"source": source, "date": date, "success": success,
                "output": f"/o/{source}_resize.mp4" if success else None}

    def test_first_call_primes_then_reports_only_new_successes(self):
        seen = set()
        existing = [self.job("b", "2"), self.job("a", "1")]
        panel.new_results(existing, seen)   # 트레이 시작 시 기존 결과는 얹지 않는다
        recent = [self.job("d", "4", success=False), self.job("c", "3")] + existing
        self.assertEqual(panel.new_results(recent, seen), ["/o/c_resize.mp4"])
        self.assertEqual(panel.new_results(recent, seen), [], "같은 결과를 두 번 얹지 않는다")

    def test_multiple_new_results_come_oldest_first(self):
        seen = set()
        panel.new_results([], seen)
        fresh = panel.new_results([self.job("new", "2"), self.job("old", "1")], seen)
        self.assertEqual(fresh, ["/o/old_resize.mp4", "/o/new_resize.mp4"],
                         "차례로 insert_front 하면 최신이 맨 앞에 온다")


class InfoTests(unittest.TestCase):

    def test_format_size(self):
        self.assertEqual(panel.format_size(12_345_678), "12.3 MB (12,345,678바이트)")
        self.assertEqual(panel.format_size(0), "0 B (0바이트)")
        self.assertEqual(panel.format_size(999), "999 B (999바이트)")

    def test_info_rows(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "clip.mov")
            with open(path, "wb") as f:
                f.write(b"x" * 1234)
            rows = panel.info_rows(path, created=time.time())
            self.assertEqual([label for label, _ in rows], ["경로", "크기", "생성일", "수정일"])
            self.assertEqual(rows[0][1], path)
            self.assertEqual([label for label, _ in panel.info_rows(tmp)], ["경로", "수정일"], "폴더는 크기 없음")
            self.assertEqual([label for label, _ in panel.info_rows(os.path.join(tmp, "gone.mp4"))], ["경로", "상태"])

    def test_tooltip_markup_escapes_and_bolds_name(self):
        markup = panel.tooltip_markup("Tom & <Jerry>.mp4", [("경로", "/a/Tom & <Jerry>.mp4"), ("크기", "1 B (1바이트)")])
        self.assertEqual(markup.split("\n")[0], "<b>Tom &amp; &lt;Jerry&gt;.mp4</b>")
        self.assertIn("경로: /a/Tom &amp; &lt;Jerry&gt;.mp4", markup)

    def test_convert_zone_icon_is_not_a_dropdown_chevron(self):
        for view in (panel.convert_zone_view(None, False, None), panel.convert_zone_view("convert", False, None)):
            self.assertNotEqual(view[3], "go-down-symbolic", "Yaru 에서는 드롭다운 화살표처럼 보인다")

    def test_paths_text(self):
        self.assertEqual(panel.paths_text(["/tmp/x/a.mov", "/tmp/x/../y/b 1.png"]), "/tmp/x/a.mov\n/tmp/y/b 1.png")


class ConfigTests(unittest.TestCase):

    def test_panel_config_defaults_and_validation(self):
        self.assertEqual(panel.panel_config({}), panel.PANEL_DEFAULTS)
        self.assertEqual(panel.panel_config({"panel": {"side": "left", "enabled": False}})["side"], "left")
        self.assertEqual(panel.panel_config({"panel": {"side": "top", "enabled": "yes"}}), panel.PANEL_DEFAULTS,
                         "틀린 값은 기본값(데몬은 경고를 남긴다)")
        self.assertTrue(panel.image_enabled({}))
        self.assertFalse(panel.image_enabled({"image": {"enabled": False}}))

    def test_set_config_value_keeps_other_keys(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "sizer", "config.json")
            os.makedirs(os.path.dirname(path))
            with open(path, "w", encoding="utf-8") as f:
                json.dump({"video": {"crf": 30}, "panel": {"side": "left"}}, f)
            self.assertIsNone(panel.set_config_value(path, "panel", "enabled", False))
            with open(path, encoding="utf-8") as f:
                self.assertEqual(json.load(f), {"video": {"crf": 30}, "panel": {"side": "left", "enabled": False}})
            self.assertEqual(os.listdir(os.path.dirname(path)), ["config.json"])

    def test_set_config_value_refuses_broken_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "config.json")
            with open(path, "w", encoding="utf-8") as f:
                f.write("{ broken")
            self.assertIn("JSON", panel.set_config_value(path, "panel", "enabled", False))

    def test_thumbnail_kind_and_cache_path(self):
        self.assertEqual(panel.thumbnail_kind("/a/b.MKV"), "video")
        self.assertEqual(panel.thumbnail_kind("/a/b.avif"), "image")
        self.assertEqual(panel.thumbnail_kind("/a/b.txt"), "other")
        a = panel.thumbnail_cache_path("/a/b.mp4", 1.0, "/c")
        self.assertNotEqual(a, panel.thumbnail_cache_path("/a/b.mp4", 2.0, "/c"), "파일이 바뀌면 새 썸네일")
        self.assertTrue(a.startswith("/c/") and a.endswith(".png"))


if __name__ == "__main__":
    unittest.main()
