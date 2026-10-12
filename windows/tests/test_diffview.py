from pathlib import Path
import subprocess
import tempfile
import unittest

import diffview


def git(directory, *arguments):
    subprocess.run(["git", "-C", str(directory), "-c", "user.name=t", "-c", "user.email=t@t", *arguments],
                   check=True, capture_output=True)


class DiffTests(unittest.TestCase):
    def test_diff_of_a_repository_and_limits(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            git(root, "init", "-q", "-b", "main")
            (root / "a.txt").write_text("uno\n")
            git(root, "add", "a.txt")
            git(root, "commit", "-q", "-m", "x")
            self.assertIn(b"sin cambios", diffview.diff_bytes(str(root)))
            (root / "a.txt").write_text("dos\n" * 5000)
            data = diffview.diff_bytes(str(root))
            self.assertIn(b"+dos", data)
            small = diffview.diff_bytes(str(root), limit=1024 * 1024)
            self.assertEqual(small, data)
            capped = diffview.diff_bytes(str(root), limit=1024)
            self.assertIn(b"recortado", capped)
            self.assertIsNone(diffview.diff_bytes(str(root / "missing")))
            self.assertIsNone(diffview.diff_bytes("relative"))

    def test_repo_cannot_run_its_own_diff_driver(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            marker = root / "ran.txt"
            git(root, "init", "-q", "-b", "main")
            (root / ".gitattributes").write_text("*.txt diff=evil\n")
            (root / "a.txt").write_text("1\n")
            git(root, "add", "-A")
            git(root, "commit", "-q", "-m", "x")
            git(root, "config", "diff.evil.command", f"python3 -c \"open(r'{marker}','w').write('x')\"")
            git(root, "config", "diff.evil.textconv", f"python3 -c \"open(r'{marker}','w').write('x')\"")
            (root / "a.txt").write_text("2\n")
            diffview.diff_bytes(str(root))
            self.assertFalse(marker.exists())

    def test_review_file_is_private(self):
        with tempfile.TemporaryDirectory() as directory:
            path = diffview.private_file(directory, "x.diff", b"secret")
            self.assertEqual(path.read_bytes(), b"secret")
            if path.stat().st_mode & 0o077:
                self.assertEqual(__import__("os").name, "nt")
