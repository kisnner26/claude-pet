from pathlib import Path
import tempfile
import unittest

import claude_pet
from pet_state import PRIORITY
from pet_bus import PeerMessage


class FrontendTests(unittest.TestCase):
    def test_render_all_states(self):
        with tempfile.TemporaryDirectory() as directory:
            previous = claude_pet.ROOT
            claude_pet.ROOT = Path(directory) / "pet"
            pet = claude_pet.Pet()
            try:
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
                pet.update()
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
