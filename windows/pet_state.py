"""local event protocol and session selection for the windows frontend."""

from dataclasses import dataclass
from pathlib import PureWindowsPath
import re
import time

PRIORITY = dict(idle=0, done=1, starting=2, thinking=3, tool=4, error=5, waiting=6)


def identifier(value, limit):
    return re.sub(r"[^a-zA-Z0-9_.:-]", "", value)[:limit]


def text(value, limit):
    return "".join(c for c in value if ord(c) >= 32 and ord(c) != 127)[:limit].strip()


@dataclass(frozen=True)
class Event:
    state: str
    session: str
    tool: str = ""
    project: str = ""
    detail: str = ""
    origin: str = ""
    task: str = ""
    workspace: str = ""

    @classmethod
    def parse(cls, line):
        if len(line.encode("utf-8")) > 2048:
            return None
        parts = line.rstrip("\r\n").split("\t", 7)
        if len(parts) < 2 or parts[0] not in (*PRIORITY, "end"):
            return None
        parts += [""] * (8 - len(parts))
        session = identifier(parts[1], 16)
        if not session:
            return None
        workspace = text(parts[7], 1024)
        if not (workspace.startswith("/") or PureWindowsPath(workspace).is_absolute()):
            workspace = ""
        return cls(parts[0], session, identifier(parts[2], 40),
                   identifier(parts[3], 40), text(parts[4], 80),
                   identifier(parts[5], 12), text(parts[6], 140), workspace)


class Sessions:
    """select the highest-priority live session, with newest events breaking ties."""

    def __init__(self, clock=time.monotonic, ttl=7200):
        self.clock = clock
        self.ttl = ttl
        self.entries = {}

    def apply(self, event):
        if event.state == "end":
            self.entries.pop(event.session, None)
        else:
            self.entries[event.session] = (event, self.clock())

    def current(self):
        now = self.clock()
        self.entries = {key: value for key, value in self.entries.items()
                        if now - value[1] < self.ttl}
        return max(self.entries.values(),
                   key=lambda item: (PRIORITY[item[0].state], item[1]),
                   default=(Event("idle", "local"), now))[0]
