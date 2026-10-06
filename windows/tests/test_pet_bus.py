import json
import unittest

from pet_bus import PeerMessage, Peers


class BusTests(unittest.TestCase):
    def test_schema_and_unknown_state(self):
        data = dict(v=1, id="codex", ts=1, state="thinking")
        self.assertEqual(PeerMessage.parse(json.dumps(data)).state, "thinking")
        for field, value in (("v", True), ("v", 2), ("id", "../codex"), ("ts", float("nan")),
                             ("ts", True), ("ts", "1")):
            with self.subTest(field=field, value=value):
                self.assertIsNone(PeerMessage.parse(json.dumps({**data, field: value})))
        self.assertEqual(PeerMessage.parse(json.dumps({**data, "state": []})).state, "idle")
        self.assertIsNone(PeerMessage.parse("{"))
        self.assertIsNone(PeerMessage.parse(json.dumps({**data, "extra": "a" * 512})))

    def test_stale_messages_departure_and_heartbeat_timeout(self):
        now = [0]
        peers = Peers(clock=lambda: now[0])
        self.assertTrue(peers.apply(PeerMessage("codex", "thinking", 10)))
        self.assertFalse(peers.apply(PeerMessage("codex", "done", 9)))
        self.assertFalse(peers.apply(PeerMessage("claude", "tool", 10)))
        now[0] = 24
        self.assertIsNotNone(peers.current("codex"))
        now[0] = 25
        self.assertIsNone(peers.current("codex"))
        peers.apply(PeerMessage("codex", "idle", 11))
        peers.apply(PeerMessage("codex", "idle", 12, left=True))
        self.assertIsNone(peers.current("codex"))
