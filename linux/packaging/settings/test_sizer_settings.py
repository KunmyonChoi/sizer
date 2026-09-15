"""sizer-settings 의 순수 로직 테스트(GTK 없이 실행). python3 -m unittest discover -s linux/packaging/settings"""

import importlib.machinery
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest

_HERE = os.path.dirname(os.path.abspath(__file__))
_SCRIPT = os.path.join(_HERE, "sizer-settings")
_loader = importlib.machinery.SourceFileLoader("sizer_settings", _SCRIPT)
_spec = importlib.util.spec_from_loader("sizer_settings", _loader)
s = importlib.util.module_from_spec(_spec)
_loader.exec_module(s)


class DocumentTests(unittest.TestCase):

    def test_missing_values_use_defaults(self):
        self.assertEqual(s.get_value({}, "video.crf"), 26)
        self.assertEqual(s.get_value({}, "still.mode"), "fastForward")
        self.assertIsNone(s.get_value({}, "folders.drop"), "폴더 기본값은 동영상 폴더에 따라 달라 따로 계산")
        self.assertEqual(s.get_value({"video": {"crf": 30}}, "video.crf"), 30)

    def test_detection_values_follow_preset_until_set(self):
        self.assertEqual(s.get_value({}, "still.noiseDb"), -58.0)
        doc = {"still": {"sensitivity": "aggressive"}}
        self.assertEqual(s.get_value(doc, "still.minStillDuration"), 1.0)
        doc["still"]["noiseDb"] = -52
        self.assertEqual(s.get_value(doc, "still.noiseDb"), -52)

    def test_choosing_preset_clears_explicit_detection_values(self):
        doc = {"still": {"sensitivity": "balanced", "noiseDb": -40, "minStillDuration": 4, "mergeGapMax": 1, "pad": 0.2}}
        doc = s.apply_changes(doc, s.changes_for("still.sensitivity", "aggressive"))
        self.assertEqual(doc["still"], {"sensitivity": "aggressive", "pad": 0.2})
        self.assertEqual(s.get_value(doc, "still.noiseDb"), -45.0)

    def test_apply_changes_creates_sections_and_does_not_mutate_input(self):
        original = {"notifications": True}
        doc = s.apply_changes(original, {"image.quality": 0.5, "notifications": False})
        self.assertEqual(doc, {"notifications": False, "image": {"quality": 0.5}})
        self.assertEqual(original, {"notifications": True})

    def test_save_rereads_file_and_keeps_other_keys(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "sizer", "config.json")
            os.makedirs(os.path.dirname(path))
            with open(path, "w", encoding="utf-8") as f:
                json.dump({"video": {"crf": 26, "preset": "slow"}, "futureKey": {"x": 1}}, f)
            # 창이 열려 있는 사이 누군가 파일을 직접 고쳤다.
            with open(path, "w", encoding="utf-8") as f:
                json.dump({"video": {"crf": 26, "preset": "veryfast"}, "futureKey": {"x": 1}}, f)

            self.assertIsNone(s.save_changes(path, {"video.crf": 30}))
            with open(path, encoding="utf-8") as f:
                saved = json.load(f)
            self.assertEqual(saved["video"], {"crf": 30, "preset": "veryfast"}, "바꾼 키만 고친다")
            self.assertEqual(saved["futureKey"], {"x": 1}, "창에 없는 키도 남긴다")
            self.assertEqual(sorted(os.listdir(os.path.dirname(path))), ["config.json"], "임시 파일을 남기지 않는다")

    def test_save_refuses_to_overwrite_broken_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "config.json")
            with open(path, "w", encoding="utf-8") as f:
                f.write("{ broken")
            error = s.save_changes(path, {"video.crf": 30})
            self.assertIn("JSON", error)
            with open(path, encoding="utf-8") as f:
                self.assertEqual(f.read(), "{ broken")

    def test_save_keeps_korean_readable(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "config.json")
            s.save_changes(path, {"folders.drop": "~/비디오/Sizer/drop"})
            with open(path, encoding="utf-8") as f:
                self.assertIn("~/비디오/Sizer/drop", f.read())


class ControlTests(unittest.TestCase):

    def test_coerce_numbers(self):
        self.assertEqual(s.coerce(s.CONTROLS["video.crf"], 27.0), 27)
        self.assertIsInstance(s.coerce(s.CONTROLS["video.crf"], 27.0), int)
        self.assertEqual(s.coerce(s.CONTROLS["still.pad"], 0.15000001), 0.15)

    def test_bounds_widen_for_hand_edited_values(self):
        crf = s.CONTROLS["video.crf"]
        self.assertEqual(s.number_bounds(crf, 26), (18, 32))
        self.assertEqual(s.number_bounds(crf, 40), (18, 40), "직접 고친 값을 조용히 잘라내지 않는다")

    def test_choices_include_hand_edited_value(self):
        edge = s.CONTROLS["video.maxLongEdge"]
        self.assertEqual(len(s.choices_with(edge, 1920)), 4)
        extra = s.choices_with(edge, 1000)
        self.assertEqual(extra[-1][0], 1000)

    def test_text_pattern(self):
        bitrate = s.CONTROLS["video.audioBitrate"]
        self.assertTrue(s.text_is_valid(bitrate, "96k"))
        self.assertFalse(s.text_is_valid(bitrate, "96"))
        self.assertTrue(s.text_is_valid(s.CONTROLS["video.outputSuffix"], ""))

    def test_groups_follow_mode(self):
        self.assertFalse(s.group_visible("detect", {"still": {"mode": "off"}}))
        self.assertTrue(s.group_visible("trim", {"still": {"mode": "trim"}}))
        self.assertFalse(s.group_visible("fastForward", {"still": {"mode": "trim"}}))
        self.assertTrue(s.group_visible("fastForward", {}), "기본 모드는 빨리감기")

    def test_every_page_key_has_a_control_and_every_control_is_shown(self):
        keys = [key for _, _, groups in s.PAGES for _, _, group_keys in groups for key in group_keys]
        self.assertEqual(sorted(keys), sorted(s.CONTROLS))
        self.assertEqual(len(keys), len(set(keys)))

    def test_defaults_lie_within_bounds_and_choices(self):
        for key, control in s.CONTROLS.items():
            if control["type"] == "number":
                self.assertTrue(control["min"] <= control["default"] <= control["max"], key)
            if control["type"] == "choice":
                self.assertIn(control["default"], [c[0] for c in control["choices"]], key)

    def test_dump_spec_runs_without_gtk(self):
        out = subprocess.run([sys.executable, "-B", _SCRIPT, "--dump-spec"], capture_output=True, text=True, check=True)
        spec = json.loads(out.stdout)
        self.assertEqual(set(spec["controls"]), set(s.CONTROLS))
        self.assertEqual(spec["presets"]["balanced"]["noiseDb"], -50.0)


class FolderTests(unittest.TestCase):

    def test_expand_and_abbreviate(self):
        self.assertEqual(s.expand("~/Videos", "/home/u"), "/home/u/Videos")
        self.assertEqual(s.expand("$HOME/x", "/home/u"), "/home/u/x")
        self.assertEqual(s.abbreviate("/home/u/Videos/Sizer", "/home/u"), "~/Videos/Sizer")
        self.assertEqual(s.abbreviate("/home/user2", "/home/u"), "/home/user2")

    def test_default_folder_uses_xdg_videos_dir(self):
        with tempfile.TemporaryDirectory() as cfg:
            self.assertEqual(s.default_folder("drop", "/home/u", cfg), "/home/u/Videos/Sizer/drop")
            with open(os.path.join(cfg, "user-dirs.dirs"), "w", encoding="utf-8") as f:
                f.write('XDG_VIDEOS_DIR="$HOME/비디오"\n')
            self.assertEqual(s.default_folder("drop", "/home/u", cfg), "/home/u/비디오/Sizer/drop")

    def test_output_cannot_equal_drop(self):
        doc = {"folders": {"drop": "~/in", "output": "~/out"}}
        self.assertIsNotNone(s.folder_conflict(doc, "folders.output", "/home/u/in/", "/home/u", "/nonexistent"))
        self.assertIsNotNone(s.folder_conflict(doc, "folders.drop", "/home/u/out", "/home/u", "/nonexistent"))
        self.assertIsNone(s.folder_conflict(doc, "folders.output", "/home/u/elsewhere", "/home/u", "/nonexistent"))
        self.assertIsNone(s.folder_conflict(doc, "folders.failed", "/home/u/in", "/home/u", "/nonexistent"))


if __name__ == "__main__":
    unittest.main()
