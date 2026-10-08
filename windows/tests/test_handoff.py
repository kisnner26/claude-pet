import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

import handoff


def git(directory, *arguments):
    subprocess.run(["git", "-C", str(directory), "-c", "user.name=t", "-c", "user.email=t@t", *arguments],
                   check=True, capture_output=True)


def repository(directory, dirty=True):
    root = Path(directory) / "proyecto"
    root.mkdir()
    git(root, "init", "-q", "-b", "main")
    (root / "a.py").write_text("x = 1\n")
    git(root, "add", "-A")
    git(root, "commit", "-q", "-m", "base")
    if dirty:
        (root / "a.py").write_text("x = 2\n")
        (root / "nuevo.py").write_text("y = 1\n")
    return root


FAKE = """
import sys
data = sys.stdin.read()
mode = sys.argv[1]
if mode == "echo":
    print("hallazgo: " + str(len(data)))
elif mode == "file":
    open(sys.argv[2], "w", encoding="utf-8").write("revision en archivo")
    print("progreso que no es el resultado")
elif mode == "fail":
    sys.stderr.write("boom\\n"); sys.exit(3)
elif mode == "sleep":
    import time; time.sleep(30)
"""


class CommandTests(unittest.TestCase):
    def test_reviewers_run_read_only(self):
        codex = handoff.build_command("codex", "codex", "/p", "/o")
        self.assertEqual(codex[codex.index("--sandbox") + 1], "read-only")
        self.assertEqual(codex[-1], "-")
        self.assertNotIn("danger-full-access", codex)
        claude = handoff.build_command("claude", "claude", "/p", "/o")
        self.assertEqual(claude[claude.index("--permission-mode") + 1], "plan")
        tools = claude[claude.index("--tools") + 1].split(",")
        self.assertEqual(sorted(tools), ["Glob", "Grep", "Read"])
        with self.assertRaises(ValueError):
            handoff.build_command("otro", "x", "/p", "/o")

    def test_prompt_keeps_the_prompt_out_of_argv(self):
        secret = "SECRETO-DEL-DIFF"
        for reviewer in ("codex", "claude"):
            self.assertNotIn(secret, " ".join(handoff.build_command(reviewer, "x", "/p", "/o")))
        text = handoff.review_prompt("claude", "pet", "arregla login", secret.encode(), True, ["n.py"])
        for expected in (secret, "arregla login", "n.py", "recortado", "Claude", "pet"):
            self.assertIn(expected, text)

    def test_find_agent_searches_beyond_path(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory) / ".local" / "bin"
            folder.mkdir(parents=True)
            tool = folder / "fakeagent"
            tool.write_text("#!/bin/sh\n")
            tool.chmod(0o755)
            with patch("shutil.which", return_value=None):
                found = handoff.find_agent("fakeagent", home=directory)
                self.assertEqual(Path(found), tool)
                self.assertIsNone(handoff.find_agent("noexiste", home=directory))


class PrepareTests(unittest.TestCase):
    def test_prepare_requires_a_repository_with_changes(self):
        with tempfile.TemporaryDirectory() as directory:
            clean = repository(directory, dirty=False)
            self.assertIn("no hay cambios", handoff.prepare(str(clean), "claude")[1])
            (clean / "a.py").write_text("x = 3\n")
            prompt, size = handoff.prepare(str(clean), "claude", "proyecto", "tarea")
            self.assertIn("+x = 3", prompt)
            self.assertEqual(size, len(prompt.encode("utf-8")))
            plain = Path(directory) / "plano"
            plain.mkdir()
            self.assertIsNone(handoff.prepare(str(plain), "claude")[0])
            self.assertIsNone(handoff.prepare("relative", "claude")[0])

    def test_untracked_files_are_listed_and_big_diffs_are_trimmed(self):
        with tempfile.TemporaryDirectory() as directory:
            root = repository(directory)
            prompt, _ = handoff.prepare(str(root), "codex")
            self.assertIn("nuevo.py", prompt)
            (root / "a.py").write_text("linea\n" * 60000)
            prompt, size = handoff.prepare(str(root), "codex")
            self.assertIn("recortado", prompt)
            self.assertLess(size, handoff.PROMPT_DIFF_LIMIT + 4096)


class ReviewTests(unittest.TestCase):
    def run_review(self, reviewer, mode, timeout=30):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        script = Path(directory.name) / "fake.py"
        script.write_text(FAKE)
        root = Path(directory.name) / "pet"
        workspace = Path(directory.name)
        review = handoff.Review(reviewer, workspace, "proyecto", root, "prompt de prueba",
                                executable="fake", timeout=timeout)

        def command(who, _exe, _workspace, output):
            return [sys.executable, str(script), mode, str(output)]
        with patch.object(handoff, "build_command", command):
            review.start()
            if mode != "sleep":
                self.assertTrue(review.done.wait(15))
            else:
                time.sleep(0.3)
        return review

    def test_claude_review_uses_stdout_and_writes_a_private_file(self):
        review = self.run_review("claude", "echo")
        self.assertEqual(review.state, "done")
        text = review.result.read_text(encoding="utf-8")
        self.assertIn("hallazgo: 16", text)
        self.assertIn("Claude sobre cambios de Codex", text)
        if os.name != "nt":
            self.assertEqual(review.result.stat().st_mode & 0o077, 0)

    def test_codex_review_prefers_the_last_message_file(self):
        review = self.run_review("codex", "file")
        self.assertEqual(review.state, "done")
        text = review.result.read_text(encoding="utf-8")
        self.assertIn("revision en archivo", text)
        self.assertNotIn("progreso", text)
        self.assertEqual([p.name for p in review.result.parent.glob(".*.out")], [])

    def test_failures_are_reported_with_the_agent_message(self):
        review = self.run_review("codex", "fail")
        self.assertEqual(review.state, "failed")
        self.assertIn("boom", review.error)
        self.assertIsNone(review.result)

    def test_missing_executable_fails_without_launching(self):
        with patch.object(handoff, "find_agent", return_value=None):
            review = handoff.Review("codex", ".", "p", tempfile.gettempdir(), "x")
        review.start()
        self.assertEqual(review.state, "failed")
        self.assertIn("no se encontró", review.error)

    def test_timeout_and_cancel(self):
        review = self.run_review("claude", "sleep", timeout=1)
        self.assertTrue(review.done.wait(10))
        self.assertEqual(review.state, "failed")
        self.assertIn("tiempo", review.error)
        review = self.run_review("claude", "sleep", timeout=30)
        time.sleep(0.5)
        self.assertTrue(review.running)
        review.cancel()
        self.assertTrue(review.done.wait(10))
        self.assertEqual(review.state, "cancelled")


class WorktreeTests(unittest.TestCase):
    def test_worktree_gets_a_new_branch_and_never_overwrites(self):
        with tempfile.TemporaryDirectory() as directory:
            root = repository(directory)
            destination, branch = handoff.create_worktree(str(root), "codex")
            self.assertEqual(destination.name, "proyecto-pet-codex")
            self.assertTrue((destination / "a.py").is_file())
            self.assertTrue(branch.startswith("pet/codex-"))
            self.assertEqual((root / "a.py").read_text(), "x = 2\n")
            with self.assertRaises(ValueError):
                handoff.create_worktree(str(root), "codex")
            with self.assertRaises(ValueError):
                handoff.create_worktree("relative", "codex")

    def test_hook_ignores_sessions_started_by_a_review(self):
        from queue import Queue
        from pet_ipc import start_server
        with tempfile.TemporaryDirectory() as directory:
            events = Queue()
            listener = start_server(Path(directory) / ".claude-pet", events.put)
            script = Path(__file__).resolve().parents[1] / "pet_hook.py"
            try:
                environment = {**os.environ, "HOME": directory, "USERPROFILE": directory,
                               "CLAUDE_PET_REVIEW": "1"}
                subprocess.run([sys.executable, str(script), "PreToolUse"], input='{"session_id":"s"}',
                               text=True, env=environment, timeout=5, capture_output=True)
                self.assertTrue(events.empty())
            finally:
                listener.close()
