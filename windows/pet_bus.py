"""pet-bus v1 messages over the windows frontend's authenticated transport."""

from dataclasses import dataclass
import json
import math
import re
import time

from pet_state import PRIORITY


@dataclass(frozen=True)
class PeerMessage:
    id: str
    state: str
    timestamp: float
    left: bool = False

    @classmethod
    def parse(cls, message):
        if len(message.encode("utf-8")) > 512:
            return None
        try:
            data = json.loads(message)
            if not isinstance(data, dict) or type(data.get("v")) is not int or data["v"] != 1:
                return None
            name, timestamp = data.get("id"), data.get("ts")
            if not isinstance(name, str) or not re.fullmatch(r"[a-z0-9-]{1,16}", name):
                return None
            if type(timestamp) not in (int, float) or not math.isfinite(timestamp):
                return None
            state = data.get("state")
            if not isinstance(state, str) or state not in PRIORITY:
                state = "idle"
            return cls(name, state, timestamp, data.get("event") == "left")
        except (ValueError, TypeError, OverflowError):
            return None


class Peers:
    def __init__(self, clock=time.monotonic):
        self.clock = clock
        self.timestamps = {}
        self.entries = {}

    def apply(self, message):
        if message.id == "claude" or message.timestamp < self.timestamps.get(message.id, -math.inf):
            return False
        self.timestamps[message.id] = message.timestamp
        if message.left:
            self.entries.pop(message.id, None)
        else:
            self.entries[message.id] = (message, self.clock())
        return True

    def current(self, name):
        entry = self.entries.get(name)
        if entry and self.clock() - entry[1] < 25:
            return entry[0]
        self.entries.pop(name, None)
        return None
