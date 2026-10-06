"""window placement, including monitors left of or above the primary screen."""

import ctypes
from dataclasses import dataclass
import os


@dataclass(frozen=True)
class Bounds:
    x: int
    y: int
    width: int
    height: int

    def clamp(self, x, y, width=200, height=160):
        return (max(self.x, min(x, self.x + max(0, self.width - width))),
                max(self.y, min(y, self.y + max(0, self.height - height))))


def desktop_bounds(window):
    if os.name == "nt":
        metrics = ctypes.windll.user32.GetSystemMetrics
        metrics.argtypes = [ctypes.c_int]
        metrics.restype = ctypes.c_int
        x, y, width, height = (metrics(index) for index in (76, 77, 78, 79))
        if width > 0 and height > 0:
            return Bounds(x, y, width, height)
    return Bounds(window.winfo_vrootx(), window.winfo_vrooty(),
                  window.winfo_vrootwidth(), window.winfo_vrootheight())


def geometry(x, y):
    # an explicit '+' preserves negative absolute coordinates in tk.
    return f"200x160+{x}+{y}"
