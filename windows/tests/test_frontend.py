from pathlib import Path
import tempfile
import unittest
import os
from unittest.mock import patch

import claude_pet
from pet_state import Event, PRIORITY
from pet_bus import PeerMessage
from pet_position import geometry


# tk on macos aborts when a second root is created after the first is destroyed, so the whole
# module shares one pet and resets it between tests.
SHARED = {}


def setUpModule():
    SHARED["directory"] = tempfile.TemporaryDirectory()
    SHARED["previous"] = claude_pet.ROOT
    claude_pet.ROOT = Path(SHARED["directory"].name) / "pet"
    SHARED["pet"] = claude_pet.Pet()


def tearDownModule():
    SHARED["pet"].close()
    claude_pet.ROOT = SHARED["previous"]
    SHARED["directory"].cleanup()


def reset(pet):
    import shutil
    from pet_state import Sessions
    from pet_bus import Peers
    from mission import Mission
    from workspace import Monitor
    for mascot in (pet, pet.codex):
        mascot.sessions, mascot.alert, mascot.last_key = Sessions(), None, None
        mascot.monitor, mascot.marked, mascot.next_scan = Monitor(), set(), 0.0
        mascot.animations, mascot.stall_watch, mascot.peer_event = True, True, None
    pet.peers, pet.mission = Peers(), Mission()
    pet.codex.window.withdraw()
    while not pet.events.empty():
        pet.events.get_nowait()
    for item in ("block-on-change", "context-changed"):
        target = claude_pet.ROOT / item
        shutil.rmtree(target, ignore_errors=True) if target.is_dir() else target.unlink(missing_ok=True)


class FrontendTests(unittest.TestCase):
    def test_render_all_states(self):
        pet = SHARED["pet"]
        reset(pet)
        pet.window.geometry(geometry(-100, -100))
        pet.window.update_idletasks()
        if os.name == "nt":
            self.assertEqual(pet.window.winfo_x(), -100)
        pet.window.geometry(geometry(60, 60))
        for mascot, body_index in ((pet, 10), (pet.codex, 0)):
            mascot.animations = False
            mascot.draw(Event("idle", "preview"))
            body = mascot.canvas.coords(mascot.canvas.find_all()[body_index])
            for state in ("done", "error"):
                mascot.draw(Event(state, "preview"))
                self.assertEqual(mascot.canvas.coords(mascot.canvas.find_all()[body_index]), body)
            mascot.animations = True
        for state in PRIORITY:
            pet.demo(state)
            pet.update()
            pet.window.update()
            self.assertGreater(len(pet.canvas.find_all()), 10)
        pet.animations = False
        pet.save()
        self.assertTrue(pet.settings.exists())
        pet.demo("tool")
        pet.events.put(PeerMessage("codex", "thinking", 1))
        with patch.object(pet.codex.window, "deiconify", wraps=pet.codex.window.deiconify) as show:
            pet.update()
            pet.update()
            self.assertEqual(show.call_count, 1)
        pet.codex.update()
        pet.window.update()
        self.assertEqual(pet.sessions.current().state, "tool")
        self.assertEqual(pet.codex.peer_event.state, "thinking")
        self.assertEqual(pet.codex.window.state(), "normal")
        pet.events.put(PeerMessage("codex", "idle", 2, left=True))
        pet.update()
        self.assertEqual(pet.codex.window.state(), "withdrawn")


class AlertTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.pet = SHARED["pet"]
        reset(self.pet)

    def tearDown(self):
        self.directory.cleanup()

    def pump(self, until, seconds=3):
        import time
        deadline = time.time() + seconds
        while time.time() < deadline:
            self.pet.next_scan = 0
            self.pet.update()
            self.pet.window.update()
            if until():
                return True
            time.sleep(0.05)
        return False

    def test_project_change_while_thinking_raises_alert_and_marks_session(self):
        from workspace import marker_path, set_blocking
        project = Path(self.directory.name) / "proyecto"
        project.mkdir()
        (project / "a.py").write_text("1")
        set_blocking(claude_pet.ROOT, True)
        self.pet.events.put(Event("thinking", "sesion", project="proyecto", workspace=str(project)))
        self.assertTrue(self.pump(lambda: "sesion" in self.pet.monitor.baselines))
        (project / "nuevo.py").write_text("2")
        self.assertTrue(self.pump(lambda: self.pet.alert is not None))
        self.assertIn("cambió", self.pet.alert[0])
        self.assertTrue(marker_path(claude_pet.ROOT, "sesion").is_file())
        self.pet.events.put(Event("thinking", "sesion", project="proyecto", workspace=str(project)))
        self.assertTrue(self.pump(lambda: self.pet.alert is None))

    def test_stalled_session_raises_alert(self):
        now = [1000.0]
        self.pet.sessions.clock = lambda: now[0]
        self.pet.sessions.apply(Event("thinking", "sesion"))
        now[0] += 301
        self.pet.watch(0)
        self.assertEqual(self.pet.alert[0], "claude parece bloqueado")
        self.pet.stall_watch = False
        self.pet.watch(0)
        self.assertIsNone(self.pet.alert)

    def test_collision_alert_and_diff_menu_do_not_break_drawing(self):
        self.pet.mission.collision = True
        self.pet.mission.local["project"] = "inventario"
        self.pet.watch(0)
        self.assertEqual(self.pet.alert[0], "claude y codex en el mismo proyecto")
        self.pet.draw(Event("idle", "x"))
        self.assertGreater(len(self.pet.canvas.find_all()), 10)


class HandoffUiTests(unittest.TestCase):
    def setUp(self):
        self.pet = SHARED["pet"]
        reset(self.pet)
        self.directory = tempfile.TemporaryDirectory()

    def tearDown(self):
        self.directory.cleanup()

    def test_review_flow_confirms_runs_and_reports(self):
        import subprocess
        import sys
        import time
        import handoff
        root = Path(self.directory.name) / "proyecto"
        root.mkdir()
        for command in (["init", "-q", "-b", "main"], ["add", "-A"]):
            subprocess.run(["git", "-C", str(root), *command], check=True, capture_output=True)
        (root / "a.py").write_text("x = 1\n")
        script = Path(self.directory.name) / "fake.py"
        script.write_text("import sys; sys.stdin.read(); print('todo bien')")
        self.pet.mission.local.update(workspace=str(root), project="proyecto")
        asked, opened = [], []
        with patch.object(claude_pet.messagebox, "askokcancel", lambda *a, **k: asked.append(a[1]) or True), \
                patch.object(handoff, "find_agent", return_value="fake"), \
                patch.object(handoff, "build_command", lambda *a: [sys.executable, str(script)]), \
                patch.object(claude_pet, "open_file", opened.append):
            self.pet.start_review("claude")
            self.assertIn("solo lectura", asked[0])
            self.assertIn("Anthropic", asked[0])
            deadline = time.time() + 10
            while not self.pet.review.done.is_set() and time.time() < deadline:
                time.sleep(0.05)
            self.pet.watch(0)
            self.assertEqual(self.pet.alert[0], "revisión lista")
            self.assertEqual(self.pet.alert_tone, "info")
            self.assertEqual(opened, [self.pet.review.result])
            self.pet.draw(Event("idle", "x"))

    def test_declined_confirmation_sends_nothing(self):
        import handoff
        self.pet.mission.local.update(workspace=self.directory.name, project="p")
        with patch.object(claude_pet.messagebox, "askokcancel", return_value=False), \
                patch.object(claude_pet.messagebox, "showinfo"), \
                patch.object(handoff, "prepare", return_value=("prompt", 10)):
            self.pet.start_review("codex")
        self.assertIsNone(self.pet.review)

    def test_pause_marks_only_sessions_of_the_collision_project(self):
        from workspace import marker_path
        self.pet.mission.local.update(project="inventario")
        self.pet.sessions.apply(Event("tool", "uno", project="inventario"))
        self.pet.sessions.apply(Event("tool", "dos", project="otro"))
        self.pet.pause_claude()
        self.assertEqual(marker_path(claude_pet.ROOT, "uno").read_text(), "paused")
        self.assertFalse(marker_path(claude_pet.ROOT, "dos").exists())


class MenuTests(unittest.TestCase):
    def test_menus_build_in_every_state(self):
        import tkinter as tk
        pet = SHARED["pet"]
        reset(pet)
        pet.mission.collision = True
        pet.mission.local.update(workspace=tempfile.gettempdir(), project="p")
        root = tk.Menu(pet.window, tearoff=False)
        pet.mission_menu(root)
        labels = [root.entrycget(i, "label") for i in range(root.index("end") + 1)]
        self.assertEqual(labels, ["mission control", "traspaso claude y codex"])
        panel = root.nametowidget(root.entrycget(1, "menu"))
        texts = [panel.entrycget(i, "label") for i in range(panel.index("end") + 1)
                 if panel.type(i) != "separator"]
        self.assertTrue(any("worktree aislado para codex" in text for text in texts))
