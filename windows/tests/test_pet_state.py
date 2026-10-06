import unittest

from pet_state import Event, Sessions


class ProtocolTests(unittest.TestCase):
    def test_windows_and_unc_workspaces(self):
        for path in (r"C:\work\pet", r"\\server\share\pet", "/work/pet"):
            with self.subTest(path=path):
                event = Event.parse("tool\ts1\tRead\tpet\tfile\tterminal\t\t" + path)
                self.assertEqual(event.workspace, path)

    def test_reject_relative_workspace(self):
        for path in (r"C:pet", r"\pet", "pet"):
            self.assertEqual(Event.parse("thinking\ts\t\t\t\t\t\t" + path).workspace, "")

    def test_reject_invalid_events(self):
        for line in ("", "wat\ts", "tool", "tool\t!!!", "tool\ts\t" + "a" * 2048):
            self.assertIsNone(Event.parse(line))

    def test_sanitize_and_preserve_empty_fields(self):
        event = Event.parse("tool\ts!\tRead\t\t hi\x00 there \tterminal\tp:task")
        self.assertEqual(event.session, "s")
        self.assertEqual(event.project, "")
        self.assertEqual(event.detail, "hi there")
        self.assertEqual(event.task, "p:task")

    def test_priority_end_and_expiration(self):
        now = [0]
        sessions = Sessions(clock=lambda: now[0], ttl=10)
        sessions.apply(Event("waiting", "a"))
        now[0] = 1
        sessions.apply(Event("thinking", "b"))
        self.assertEqual(sessions.current().session, "a")
        sessions.apply(Event("end", "a"))
        self.assertEqual(sessions.current().session, "b")
        now[0] = 11
        self.assertEqual(sessions.current().state, "idle")

    def test_newest_session_breaks_tie(self):
        now = [0]
        sessions = Sessions(clock=lambda: now[0])
        sessions.apply(Event("tool", "a"))
        now[0] = 1
        sessions.apply(Event("tool", "b"))
        self.assertEqual(sessions.current().session, "b")

    def test_terminal_states_expire_without_hiding_other_work(self):
        for state, lifetime in (("done", 5), ("error", 8)):
            with self.subTest(state=state):
                now = [0]
                sessions = Sessions(clock=lambda: now[0])
                sessions.apply(Event("starting", "active"))
                sessions.apply(Event(state, "finished"))
                now[0] = lifetime
                self.assertEqual(sessions.current().session, "active")
                now[0] = 900
                self.assertEqual(sessions.current().state, "idle")


if __name__ == "__main__":
    unittest.main()
