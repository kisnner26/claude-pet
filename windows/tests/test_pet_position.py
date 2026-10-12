import unittest

from pet_position import Bounds, geometry


class PositionTests(unittest.TestCase):
    def test_negative_monitor_coordinates_are_preserved(self):
        desktop = Bounds(-1920, -1080, 3840, 2160)
        self.assertEqual(desktop.clamp(-1200, -500), (-1200, -500))
        self.assertEqual(geometry(-1200, -500), "260x190+-1200+-500")

    def test_offscreen_positions_return_to_available_desktop(self):
        self.assertEqual(Bounds(0, 0, 1920, 1080).clamp(-1200, -500), (0, 0))
        self.assertEqual(Bounds(0, 0, 1920, 1080).clamp(8000, 8000), (1660, 890))
        self.assertEqual(Bounds(-100, -100, 50, 50).clamp(0, 0), (-100, -100))
