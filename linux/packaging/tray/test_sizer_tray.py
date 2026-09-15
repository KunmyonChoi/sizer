"""sizer-tray 의 순수 로직 테스트(GTK 없이 실행). python3 -m unittest discover -s linux/packaging/tray"""

import fcntl
import importlib.machinery
import importlib.util
import os
import tempfile
import unittest
import xml.etree.ElementTree as ET

_HERE = os.path.dirname(os.path.abspath(__file__))
_loader = importlib.machinery.SourceFileLoader("sizer_tray", os.path.join(_HERE, "sizer-tray"))
_spec = importlib.util.spec_from_loader("sizer_tray", _loader)
tray = importlib.util.module_from_spec(_spec)
_loader.exec_module(tray)


def status(**overrides):
    """StatusReportTests.testJSONKeysMatchTrayContract 가 고정한 키."""
    base = {"version": "1.10.0", "pid": 42, "state": "watching", "queued": 0, "ffmpegAvailable": True,
            "dropFolder": "/d", "outputFolder": "/o", "failedFolder": "/f", "recent": []}
    base.update(overrides)
    return base


def job(source, success=True, output="/o/out.mp4"):
    return {"source": source, "output": output if success else None, "kind": "video",
            "success": success, "detail": "1.0MB → 0.5MB (50% 절감)", "date": "1970-01-01T00:00:00Z"}


def labels(model):
    return [entry.get("label") for entry in model if entry["kind"] != "separator"]


def find(model, label):
    return next(entry for entry in model if entry.get("label") == label)


class MenuModelTests(unittest.TestCase):

    def test_service_off_offers_start_and_hides_daemon_actions(self):
        model = tray.menu_model(None, running=False, keep_awake=False)
        self.assertIn("서비스 꺼짐", labels(model))
        self.assertEqual(find(model, "서비스 시작")["action"], "start")
        self.assertNotIn("감시 일시정지", labels(model))
        self.assertNotIn("지금 다시 스캔", labels(model))
        self.assertIn("드롭 폴더 열기", labels(model), "폴더는 서비스가 꺼져 있어도 열 수 있다")

    def test_stale_status_is_ignored_when_daemon_is_off(self):
        model = tray.menu_model(status(state="converting", current="a.mp4"), running=False, keep_awake=False)
        self.assertIn("서비스 꺼짐", labels(model))
        self.assertEqual(tray.icon_name(status(state="converting"), running=False, keep_awake=False), "sizer-off")

    def test_watching(self):
        model = tray.menu_model(status(), running=True, keep_awake=False)
        self.assertEqual(labels(model)[:2], ["Sizer 1.10.0", "감시 중"])
        self.assertEqual(find(model, "감시 일시정지")["action"], "pause")
        self.assertEqual(find(model, "지금 다시 스캔")["action"], "rescan")
        self.assertIn("최근 변환 없음", labels(model))
        self.assertEqual(find(model, "Sizer 종료")["action"], "quit")
        self.assertEqual(find(model, "설정…")["action"], "settings")

    def test_converting_label_and_spinner(self):
        s = status(state="converting", current="clip.mp4", queued=2)
        self.assertIn("변환 중: clip.mp4 · 대기 2", labels(tray.menu_model(s, True, False)))
        self.assertEqual(tray.icon_name(s, True, False, frame=3), "sizer-busy-3")
        self.assertEqual(tray.icon_name(s, True, True, frame=tray.BUSY_FRAMES + 1), "sizer-busy-1",
                         "변환 중에는 꺼짐 방지보다 회전 아이콘이 우선")

    def test_paused_offers_resume(self):
        s = status(state="paused", current="clip.mp4")
        model = tray.menu_model(s, True, False)
        self.assertIn("일시정지 · clip.mp4 마무리 중", labels(model))
        self.assertEqual(find(model, "감시 재개")["action"], "resume")
        self.assertEqual(tray.icon_name(s, True, False), "sizer-paused")

    def test_keep_awake_check_and_icon(self):
        model = tray.menu_model(status(), True, keep_awake=True)
        self.assertTrue(find(model, "모니터 꺼짐 방지")["active"])
        self.assertEqual(tray.icon_name(status(), True, True), "sizer-awake")
        self.assertEqual(tray.icon_name(status(), True, False), "sizer-idle")

    def test_ffmpeg_warning(self):
        model = tray.menu_model(status(ffmpegAvailable=False), True, False)
        self.assertTrue(any("ffmpeg 없음" in label for label in labels(model)))

    def test_recent_items_open_output_or_logs(self):
        recent = [job("ok.mp4", output="/o/ok_resize.mp4"), job("bad.mp4", success=False)]
        model = tray.menu_model(status(recent=recent), True, False)
        ok = next(e for e in model if e.get("label", "").startswith("✅ ok.mp4"))
        bad = next(e for e in model if e.get("label", "").startswith("❌ bad.mp4"))
        self.assertEqual((ok["action"], ok["arg"]), ("open", "/o/ok_resize.mp4"))
        self.assertEqual((bad["action"], bad["arg"]), ("folder", "logs"))

    def test_recent_is_capped(self):
        recent = [job(f"{i}.mp4") for i in range(20)]
        model = tray.menu_model(status(recent=recent), True, False)
        self.assertEqual(sum(1 for label in labels(model) if label.startswith("✅")), tray.MAX_RECENT)

    def test_recent_falls_back_to_saved_history_when_off(self):
        model = tray.menu_model(None, False, False, fallback_recent=[job("saved.mp4")])
        self.assertTrue(any(label.startswith("✅ saved.mp4") for label in labels(model)))

    def test_shorten_keeps_both_ends(self):
        text = "✅ " + "아주긴파일이름" * 20 + "_resize.mp4"
        short = tray.shorten(text)
        self.assertEqual(len(short), tray.LABEL_LIMIT)
        self.assertTrue(short.startswith("✅ 아주"))
        self.assertTrue(short.endswith("_resize.mp4"))
        self.assertEqual(tray.shorten("짧음"), "짧음")


class PlatformTests(unittest.TestCase):

    def setUp(self):
        self.saved = {k: os.environ.get(k) for k in ("XDG_RUNTIME_DIR", "XDG_STATE_HOME")}

    def tearDown(self):
        for key, value in self.saved.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value

    def test_paths_follow_xdg_like_swift(self):
        os.environ["XDG_RUNTIME_DIR"] = "/run/user/7"
        os.environ["XDG_STATE_HOME"] = "/s"
        self.assertEqual(tray.status_path(), "/run/user/7/sizer/status.json")
        self.assertEqual(tray.daemon_lock_path(), "/run/user/7/sizer/daemon.lock")
        self.assertEqual(tray.recent_path(), "/s/sizer/recent.json")
        del os.environ["XDG_RUNTIME_DIR"]
        self.assertEqual(tray.runtime_dir(), "/s/sizer/run")

    def test_lock_detection(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "daemon.lock")
            self.assertFalse(tray.lock_is_held(path), "파일이 없으면 데몬 없음")
            holder = open(path, "w")
            fcntl.flock(holder, fcntl.LOCK_EX)
            try:
                self.assertTrue(tray.lock_is_held(path))
            finally:
                holder.close()
            self.assertFalse(tray.lock_is_held(path))

    def test_icons_cover_every_name_and_are_valid_svg(self):
        icons = tray.icon_svgs()
        names = {"sizer-idle", "sizer-off", "sizer-paused", "sizer-awake"} | {f"sizer-busy-{i}" for i in range(tray.BUSY_FRAMES)}
        self.assertEqual(set(icons), names)
        for name, svg in icons.items():
            self.assertEqual(ET.fromstring(svg).tag, "{http://www.w3.org/2000/svg}svg", name)
        with tempfile.TemporaryDirectory() as tmp:
            tray.write_icons(tmp)
            self.assertEqual(len(os.listdir(tmp)), len(names))


if __name__ == "__main__":
    unittest.main()
