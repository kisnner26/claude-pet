from pathlib import Path
import unittest
import json
import os
from queue import Queue
import subprocess
import sys
import tempfile

from install_hooks import merge
from pet_hook import HOOKS, event_line
from pet_state import Event
from pet_ipc import start_server


class HookTests(unittest.TestCase):
    def test_install_reads_bom_and_keeps_original_backup(self):
        with tempfile.TemporaryDirectory() as directory:
            settings = Path(directory) / "settings.json"
            original = b'\xef\xbb\xbf{"theme":"dark"}\n'
            settings.write_bytes(original)
            installer = Path(__file__).resolve().parents[1] / "install_hooks.py"
            subprocess.run([sys.executable, str(installer), "--settings", str(settings), "--apply"],
                           check=True, capture_output=True, timeout=5)
            self.assertEqual(json.loads(settings.read_text(encoding="utf-8"))["theme"], "dark")
            self.assertEqual(next(Path(directory).glob("*.bak")).read_bytes(), original)

    def test_uninstall_after_hook_executable_is_deleted(self):
        with tempfile.TemporaryDirectory() as directory:
            executable = (Path(directory) / "missing-hook.exe").resolve()
            settings = Path(directory) / "settings.json"
            settings.write_text(json.dumps(merge({}, Path("pet_hook.py"), "python.exe",
                                                  hook_executable=executable)), encoding="utf-8")
            installer = Path(__file__).resolve().parents[1] / "install_hooks.py"
            subprocess.run([sys.executable, str(installer), "--settings", str(settings),
                            "--hook-executable", str(executable), "--uninstall", "--apply"],
                           check=True, capture_output=True, timeout=5)
            self.assertEqual(json.loads(settings.read_text(encoding="utf-8")), {"hooks": {}})

    def test_all_states_and_windows_project(self):
        for hook, state in HOOKS.items():
            event = Event.parse(event_line(hook, dict(session_id="s", tool_name="Read",
                                                     cwd=r"C:\work\pet", prompt="private")))
            self.assertEqual(event.state, state)
            self.assertEqual(event.project, "pet")
            self.assertEqual(event.task, "")

    def test_idempotent_install_preserves_other_hooks(self):
        original = {"theme": "dark", "hooks": {"Stop": [{"hooks": [
            {"type": "command", "command": "other-hook"}]}]}}
        script = Path("C:/pet folder/pet_hook.py")
        installed = merge(original, script, "C:/Python/python.exe")
        self.assertEqual(merge(installed, script, "C:/Python/python.exe"), installed)
        self.assertEqual(installed["theme"], "dark")
        self.assertEqual(len(original["hooks"]["Stop"]), 1)
        uninstalled = merge(installed, script, "C:/Python/python.exe", uninstall=True)
        self.assertEqual(uninstalled, original)

    def test_exec_form_keeps_paths_as_arguments(self):
        script = Path("C:/pet's $folder/pet_hook.py")
        executable = "C:/Program Files/Python/python.exe"
        installed = merge({}, script, executable)
        hook = installed["hooks"]["Stop"][0]["hooks"][0]
        self.assertEqual(hook["command"], executable)
        self.assertEqual(hook["args"], [str(script), "Stop"])

    def test_standalone_hook_install_and_removal(self):
        executable = Path("C:/pet/claude-pet-hook.exe")
        script = Path("C:/pet/pet_hook.py")
        installed = merge({}, script, "python.exe", hook_executable=executable)
        hook = installed["hooks"]["Stop"][0]["hooks"][0]
        self.assertEqual(hook["command"], str(executable))
        self.assertEqual(hook["args"], ["Stop"])
        self.assertEqual(merge(installed, script, "python.exe", hook_executable=executable), installed)
        self.assertEqual(merge(installed, script, "python.exe", uninstall=True,
                               hook_executable=executable), {"hooks": {}})

    def test_hook_process_delivers_event_and_fails_open_when_pet_closed(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / ".claude-pet"
            events = Queue()
            listener = start_server(root, events.put)
            script = Path(__file__).resolve().parents[1] / "pet_hook.py"
            environment = {**os.environ, "HOME": directory, "USERPROFILE": directory}
            executable = os.environ.get("PET_HOOK_EXECUTABLE")
            command = ([executable, "PreToolUse"] if executable else
                       [sys.executable, str(script), "PreToolUse"])
            payload = json.dumps(dict(session_id="s", tool_name="Read", cwd=r"C:\work\pet"))
            try:
                result = subprocess.run(command, input=payload, text=True, capture_output=True,
                                        env=environment, timeout=5)
                self.assertEqual((result.returncode, result.stdout, result.stderr), (0, "", ""))
                self.assertEqual(events.get(timeout=3).tool, "Read")
            finally:
                listener.close()
            # a separate directory has no running pet and no authentication key.
            environment.update(HOME=directory + "/absent", USERPROFILE=directory + "/absent")
            result = subprocess.run(command, input=payload, text=True, capture_output=True,
                                    env=environment, timeout=5)
            self.assertEqual((result.returncode, result.stdout, result.stderr), (0, "", ""))
