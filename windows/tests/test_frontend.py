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
