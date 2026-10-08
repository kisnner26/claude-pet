import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest

from gitpulse import GitHealth, ScanCoordinator, parse, scan
from mission import Mission
from pet_bus import PeerMessage


def quiet(_workspace):
    return GitHealth(available=True)


class Clock:
    def __init__(self):
        self.now = 1000.0

    def __call__(self):
        return self.now


def git(directory, *arguments):
    subprocess.run(["git", "-C", str(directory), "-c", "user.name=t", "-c", "user.email=t@t", *arguments],
                   check=True, capture_output=True)


class GitPulseTests(unittest.TestCase):
    def test_parse_counts_each_kind_once(self):
        data = b"## main...origin/main\0M  a.py\0 M b.py\0MM c.py\0?? d.py\0UU e.py\0R  new.py\0old.py\0"
        health = parse(data)
        self.assertEqual((health.branch, health.affected, health.staged, health.changed,
                          health.untracked, health.conflicts), ("main", 6, 3, 2, 1, 1))
        self.assertEqual(health.label, "1 conflictos")
        self.assertEqual(parse(b"## No commits yet on dev\0").branch, "dev")
        self.assertEqual(parse(b"## main\0").label, "árbol limpio")
        self.assertEqual(GitHealth().label, "sin repositorio git")

    def test_scan_a_real_repository(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.assertFalse(scan(str(root)).available)
            git(root, "init", "-q", "-b", "main")
            (root / "a.txt").write_text("1")
            git(root, "add", "a.txt")
            (root / "b.txt").write_text("2")
            health = scan(str(root))
            self.assertEqual((health.available, health.staged, health.untracked, health.branch),
                             (True, 1, 1, "main"))
            self.assertFalse(scan(str(root / "missing")).available)
            self.assertFalse(scan("relative/path").available)

    def test_coordinator_keeps_one_running_and_the_newest_pending(self):
        release, seen = [], []

        def slow(workspace):
            seen.append(workspace)
            while not release:
                time.sleep(0.01)
            return GitHealth(available=True)

        coordinator = ScanCoordinator(slow)
        done = []
        for name in ("a", "b", "c"):
            coordinator.request(name, lambda workspace, _health: done.append(workspace))
        time.sleep(0.1)
        self.assertEqual(coordinator.starts, 1)
        release.append(1)
        deadline = time.time() + 3
        while len(done) < 2 and time.time() < deadline:
            time.sleep(0.01)
        self.assertEqual(done, ["a", "c"])
        self.assertEqual(coordinator.starts, 2)


class MissionTests(unittest.TestCase):
    def setUp(self):
        self.clock = Clock()
        self.mission = Mission(self.clock, quiet)

    def test_timeline_keeps_sixteen_newest_changes(self):
        for index in range(20):
            self.mission.record_local("thinking" if index % 2 == 0 else "done", "pet")
            self.clock.now += 1
        self.assertEqual(len(self.mission.timeline), 16)
        self.assertEqual(self.mission.timeline[0].state, "done")

    def test_collision_needs_ten_seconds_and_clears_after_five(self):
        self.mission.record_local("thinking", "pet")
        self.mission.record_peer("tool", "pet")
        self.clock.now += 9
        self.mission.tick()
        self.assertFalse(self.mission.collision)
        self.clock.now += 1
        self.mission.tick()
        self.assertTrue(self.mission.collision)
        self.mission.record_peer("done", "pet")
        self.clock.now += 4
        self.mission.tick()
        self.assertTrue(self.mission.collision)
        self.clock.now += 1
        self.mission.tick()
        self.assertFalse(self.mission.collision)

    def test_collision_ignores_generic_and_different_projects(self):
        for project, other in (("src", "src"), ("pet", "other"), ("", "")):
            mission = Mission(self.clock, quiet)
            mission.record_local("thinking", project)
            mission.record_peer("thinking", other)
            self.clock.now += 30
            mission.tick()
            self.assertFalse(mission.collision)

    def test_budget_counts_tools_and_keeps_the_last_summary(self):
        self.mission.record_local("thinking", "pet")
        for tool in ("Read", "Edit", "Read", "", "Read"):
            self.mission.record_tool(tool)
        self.clock.now += 130
        self.assertEqual(self.mission.focus_label, "2 min · 5 herramientas · Read ×3, Edit ×1, herramienta ×1")
        self.mission.record_local("done", "pet")
        self.assertEqual(self.mission.focus_label, "2 min · 5 herramientas · Read ×3, Edit ×1, herramienta ×1")
        self.mission.record_local("thinking", "pet")
        self.assertEqual(self.mission.tool_calls, 0)

    def test_recovery_after_three_seconds_of_error_and_dismissal(self):
        self.mission.record_local("error", "pet", session="s")
        self.clock.now += 2
        self.mission.tick()
        self.assertIsNone(self.mission.recovery)
        self.clock.now += 1
        self.mission.tick()
        self.assertEqual(self.mission.recovery.project, "pet")
        self.mission.clear_recovery()
        self.clock.now += 5
        self.mission.tick()
        self.assertIsNone(self.mission.recovery)
        self.mission.record_local("thinking", "pet", session="s")
        self.assertIsNone(self.mission.pending_error)

    def test_active_scan_runs_every_fifteen_seconds(self):
        with tempfile.TemporaryDirectory() as directory:
            seen = []
            mission = Mission(self.clock, lambda workspace: seen.append(workspace) or quiet(workspace))
            mission.record_local("thinking", "pet", directory)
            deadline = time.time() + 3
            while not seen and time.time() < deadline:
                time.sleep(0.01)
            self.assertEqual(len(seen), 1)
            self.clock.now += 14
            mission.tick()
            self.clock.now += 1
            mission.tick()
            deadline = time.time() + 3
            while len(seen) < 2 and time.time() < deadline:
                time.sleep(0.01)
            self.assertEqual(len(seen), 2)
            self.assertTrue(mission.git.available)

    def test_peer_message_carries_only_a_sanitised_project_name(self):
        message = PeerMessage.parse('{"v":1,"id":"codex","state":"tool","ts":1,"project":"../my pet"}')
        self.assertEqual(message.project, "..mypet")
        self.assertEqual(PeerMessage.parse('{"v":1,"id":"codex","state":"tool","ts":1}').project, "")
