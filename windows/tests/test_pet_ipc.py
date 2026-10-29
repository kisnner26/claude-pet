from pathlib import Path
from queue import Queue
import tempfile
import unittest
import json
import os
from unittest import mock
from multiprocessing.connection import Client
from multiprocessing import AuthenticationError

from pet_ipc import endpoint, send, start_server


class TransportTests(unittest.TestCase):
    def test_roundtrip_and_invalid_input_recovery(self):
        with tempfile.TemporaryDirectory() as directory:
            events = Queue()
            root = Path(directory) / "pet"
            listener = start_server(root, events.put)
            try:
                with self.assertRaises(RuntimeError):
                    start_server(root, events.put)
                address, family = endpoint(root)
                # disconnect before authentication finishes, then send a wrong key.
                with Client(address, family=family, authkey=None):
                    pass
                with self.assertRaises((AuthenticationError, EOFError, OSError)):
                    Client(address, family=family, authkey=b"incorrect-key")
                send(root, "unknown\ts")
                send(root, json.dumps(dict(v=1, id="codex", state="thinking", ts=10 ** 400)))
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

    @unittest.skipIf(os.name == "nt", "POSIX mode bits; Windows uses directory ACLs")
    def test_existing_key_is_made_private_before_listener_starts(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "pet"
            root.mkdir()
            key = root / "windows-pet.key"
            key.write_bytes(b"k" * 32)
            key.chmod(0o644)
            with mock.patch("pet_ipc.Listener", side_effect=OSError("test stops before binding")):
                with self.assertRaises(OSError):
                    start_server(root, lambda event: None)
            self.assertEqual(key.stat().st_mode & 0o777, 0o600)
            self.assertEqual(key.read_bytes(), b"k" * 32)
