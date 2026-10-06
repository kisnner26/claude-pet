from pathlib import Path
import tempfile
import unittest
import os
from unittest.mock import patch

import claude_pet
from pet_state import Event, PRIORITY
from pet_bus import PeerMessage
from pet_position import geometry


class FrontendTests(unittest.TestCase):
    def test_render_all_states(self):
        with tempfile.TemporaryDirectory() as directory:
            previous = claude_pet.ROOT
            claude_pet.ROOT = Path(directory) / "pet"
            pet = claude_pet.Pet()
            try:
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
            finally:
                pet.close()
                claude_pet.ROOT = previous
