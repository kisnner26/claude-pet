from pathlib import Path
import unittest

from install_hooks import merge
from pet_hook import HOOKS, event_line
from pet_state import Event


class HookTests(unittest.TestCase):
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
