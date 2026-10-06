from pathlib import Path
import tempfile
import unittest

import claude_pet
from pet_state import PRIORITY


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
            finally:
                pet.close()
                claude_pet.ROOT = previous
