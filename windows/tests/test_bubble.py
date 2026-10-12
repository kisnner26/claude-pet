import unittest

from bubble import describe
from pet_state import Event, Sessions


class BubbleTests(unittest.TestCase):
    def test_wording_matches_macos(self):
        self.assertEqual(describe("tool", "Edit", "store.py"), ("Editando store.py", ""))
        self.assertEqual(describe("tool", "Bash", "$ git"), ("Ejecutando git", ""))
        self.assertEqual(describe("tool", "test", "$ pytest"), ("Ejecutando pruebas (pytest)", ""))
        self.assertEqual(describe("tool", "Grep", "login"), ("Buscando «login»", ""))
        self.assertEqual(describe("tool", "mcp__figma__get_design"), ("Usando get_design", ""))
        self.assertEqual(describe("waiting", "Write", "a.py"), ("Escribiendo a.py", "Esperando tu aprobación"))
        self.assertEqual(describe("thinking", task="arregla el login"), ("arregla el login", "Pensando"))
        self.assertEqual(describe("done"), ("Terminó", "Terminó"))
        self.assertEqual(describe("idle"), ("", ""))

    def test_sessions_keep_prompt_and_prefer_todo(self):
        clock = [0]
        sessions = Sessions(clock=lambda: clock[0])
        sessions.apply(Event("thinking", "s", task="p:arregla el login"))
        sessions.apply(Event("tool", "s", tool="Read", detail="a.py"))
        self.assertEqual(sessions.task(sessions.current()), "arregla el login")
        sessions.apply(Event("tool", "s", tool="TodoWrite", task="t:escribiendo pruebas"))
        self.assertEqual(sessions.task(sessions.current()), "escribiendo pruebas")
        sessions.apply(Event("thinking", "s", task="p:otra cosa"))
        self.assertEqual(sessions.task(sessions.current()), "otra cosa")
        sessions.apply(Event("end", "s"))
        self.assertEqual(sessions.prompts, {})
        self.assertEqual(sessions.todos, {})
