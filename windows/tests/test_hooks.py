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
            original = b'\xef\xbb\xbf{"theme":"dark"}\r\n'
            settings.write_bytes(original)
            installer = Path(__file__).resolve().parents[1] / "install_hooks.py"
            subprocess.run([sys.executable, str(installer), "--settings", str(settings), "--apply"],
                           check=True, capture_output=True, timeout=5,
                           env={**os.environ, "PYTHONIOENCODING": "cp1252"})
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

    def test_bubble_detail_keeps_only_the_minimum(self):
        def line(hook, **tool):
            return Event.parse(event_line(hook, dict(session_id="s", cwd=r"C:\work\pet", **tool)))
        self.assertEqual(line("PreToolUse", tool_name="Edit",
                              tool_input=dict(file_path=r"C:\work\pet\store.py")).detail, "store.py")
        self.assertEqual(line("PreToolUse", tool_name="Bash",
                              tool_input=dict(command=r"C:\bin\curl.exe -H secret-token")).detail, "$ curl.exe")
        self.assertEqual(line("PreToolUse", tool_name="Bash",
                              tool_input=dict(command="ls", description="lista archivos")).detail, "lista archivos")
        self.assertEqual(line("PreToolUse", tool_name="WebFetch",
                              tool_input=dict(url="https://example.com/a?token=1")).detail, "example.com")
        self.assertEqual(line("PostToolUse", tool_name="Bash",
                              tool_input=dict(description="no se muestra")).detail, "")

    def test_tests_are_classified_without_keeping_the_command(self):
        result = Event.parse(event_line("PreToolUse", dict(
            session_id="s", tool_name="Bash", cwd=r"C:\work\pet",
            tool_input=dict(command="python -m pytest -k secret"))))
        self.assertEqual(result.tool, "test")
        self.assertNotIn("secret", result.detail)

    def test_task_comes_from_prompt_or_todo_and_oversize_lines_survive(self):
        prompt = Event.parse(event_line("UserPromptSubmit", dict(
            session_id="s", cwd=r"C:\work\pet", prompt="arregla\nel   login")))
        self.assertEqual(prompt.task, "p:arregla el login")
        todo = Event.parse(event_line("PreToolUse", dict(
            session_id="s", tool_name="TodoWrite", cwd=r"C:\work\pet", tool_input=dict(todos=[
                dict(status="completed", activeForm="a"),
                dict(status="in_progress", activeForm="escribiendo pruebas")]))))
        self.assertEqual(todo.task, "t:escribiendo pruebas")
        huge = Event.parse(event_line("UserPromptSubmit", dict(
            session_id="s", cwd="C:\\" + "\u00e9" * 1000, prompt="\u00e9" * 400)))
        self.assertIsNotNone(huge)

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


class BlockTests(unittest.TestCase):
    def run_hook(self, directory, name, payload):
        environment = {**os.environ, "HOME": directory, "USERPROFILE": directory}
        script = Path(__file__).resolve().parents[1] / "pet_hook.py"
        return subprocess.run([sys.executable, str(script), name], input=json.dumps(payload),
                              text=True, capture_output=True, env=environment, timeout=5)

    def test_marker_blocks_only_with_flag_and_expires(self):
        import time
        from workspace import mark, set_blocking
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / ".claude-pet"
            payload = dict(session_id="abc", tool_name="Read", cwd=r"C:\work\pet")
            mark(root, "abc")
            self.assertEqual(self.run_hook(directory, "PreToolUse", payload).stdout, "")
            set_blocking(root, True)
            denied = json.loads(self.run_hook(directory, "PreToolUse", payload).stdout)
            self.assertEqual(denied["hookSpecificOutput"]["permissionDecision"], "deny")
            self.assertEqual(self.run_hook(directory, "PostToolUse", payload).stdout, "")
            old = time.time() - 700
            os.utime(root / "context-changed" / "abc", (old, old))
            self.assertEqual(self.run_hook(directory, "PreToolUse", payload).stdout, "")
            mark(root, "abc")
            self.run_hook(directory, "UserPromptSubmit", payload)
            self.assertFalse((root / "context-changed" / "abc").exists())

    def test_paused_marker_needs_no_flag_and_is_per_session(self):
        from workspace import mark
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / ".claude-pet"
            mark(root, "abc", "paused")
            mine = self.run_hook(directory, "PreToolUse", dict(session_id="abc", cwd="C:\\p"))
            other = self.run_hook(directory, "PreToolUse", dict(session_id="xyz", cwd="C:\\p"))
            self.assertIn("deny", mine.stdout)
            self.assertEqual(other.stdout, "")
