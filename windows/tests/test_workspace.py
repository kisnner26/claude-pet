from pathlib import Path
import tempfile
import time
import unittest

from workspace import Monitor, clear_mark, fingerprint, mark, marker_path, stalled


class WorkspaceTests(unittest.TestCase):
    def test_fingerprint_ignores_generated_folders_and_reacts_to_real_changes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "a.py").write_text("1")
            base = fingerprint(str(root))
            (root / "node_modules").mkdir()
            (root / "node_modules" / "x.js").write_text("x")
            (root / "run.log").write_text("x")
            (root / ".hidden").write_text("x")
            self.assertEqual(fingerprint(str(root)), base)
            (root / "b.py").write_text("2")
            self.assertNotEqual(fingerprint(str(root)), base)
            self.assertIsNone(fingerprint("relative"))
            self.assertIsNone(fingerprint(str(root / "missing")))

    def test_monitor_fires_once_after_a_change_and_rearm_clears_it(self):
        values = iter(["a", "b", "b", "c"])
        current = []

        def scanner(_root):
            current.append(next(values))
            return current[-1]

        monitor = Monitor(scanner)
        monitor.arm("s", "C:\\p")
        deadline = time.time() + 2
        while "s" not in monitor.baselines and time.time() < deadline:
            time.sleep(0.01)
        monitor.check("s", "C:\\p")
        deadline = time.time() + 2
        while "s" not in monitor.changed_sessions() and time.time() < deadline:
            time.sleep(0.01)
        self.assertEqual(monitor.changed_sessions(), {"s"})
        monitor.arm("s", "C:\\p")
        self.assertEqual(monitor.changed_sessions(), set())
        monitor.forget("s")

    def test_stall_thresholds(self):
        self.assertFalse(stalled("thinking", 0, 299))
        self.assertTrue(stalled("thinking", 0, 300))
        self.assertFalse(stalled("tool", 0, 899))
        self.assertTrue(stalled("tool", 0, 900))
        self.assertFalse(stalled("waiting", 0, 10_000))

    def test_marker_names_are_validated(self):
        with tempfile.TemporaryDirectory() as directory:
            mark(directory, "../evil")
            self.assertFalse((Path(directory).parent / "evil").exists())
            mark(directory, "ok")
            self.assertTrue(marker_path(directory, "ok").is_file())
            clear_mark(directory, "ok")
            self.assertFalse(marker_path(directory, "ok").exists())
