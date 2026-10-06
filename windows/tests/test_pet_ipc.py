from pathlib import Path
from queue import Queue
import tempfile
import unittest
import json

from pet_ipc import send, start_server


class TransportTests(unittest.TestCase):
    def test_roundtrip_and_invalid_input_recovery(self):
        with tempfile.TemporaryDirectory() as directory:
            events = Queue()
            root = Path(directory) / "pet"
            listener = start_server(root, events.put)
            try:
                send(root, "unknown\ts")
                send(root, "tool\ts\tRead")
                event = events.get(timeout=3)
                self.assertEqual((event.state, event.tool), ("tool", "Read"))
                self.assertTrue(events.empty())
                send(root, json.dumps(dict(v=1, id="codex", state="thinking", ts=1)))
                self.assertEqual(events.get(timeout=3).id, "codex")
                with self.assertRaises(ValueError):
                    send(root, "a" * 2049)
            finally:
                listener.close()
