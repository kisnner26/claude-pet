"""detect project changes by metadata only (names, sizes, dates), never by reading contents.
also the markers read by the hook for the opt-in tool block."""

import hashlib
import os
from pathlib import Path
import re
import threading
import time

THINKING_STALL = 300
TOOL_STALL = 900
MAX_FILES = 8_000
IGNORED_DIRS = {".git", "node_modules", ".build", "build", "dist", ".next", ".nuxt", "__pycache__",
                ".venv", "venv", "target", "DerivedData", "coverage", ".cache", ".gradle", ".idea"}
IGNORED_SUFFIXES = (".log", ".tmp", ".swp", ".pyc")
SESSION = re.compile(r"[A-Za-z0-9_-]{1,16}")


def fingerprint(root):
    """a hash of relative names, sizes and mtimes; None if the folder is missing or too big."""
    base = Path(root)
    if not base.is_absolute() or not base.is_dir():
        return None
    digest, count = hashlib.sha1(), 0
    for folder, dirs, files in os.walk(base):
        dirs[:] = sorted(d for d in dirs if d not in IGNORED_DIRS and not d.startswith("."))
        for name in sorted(files):
            if name.startswith(".") or name.endswith(IGNORED_SUFFIXES):
                continue
            try:
                info = os.stat(os.path.join(folder, name))
            except OSError:
                continue
            count += 1
            if count > MAX_FILES:
                return None
            relative = os.path.relpath(os.path.join(folder, name), base)
            digest.update(f"{relative}\0{info.st_size}\0{int(info.st_mtime * 1000)}\n".encode("utf-8", "replace"))
    return digest.hexdigest()


def stalled(state, since, now):
    elapsed = now - since
    return (state == "thinking" and elapsed >= THINKING_STALL) or (state == "tool" and elapsed >= TOOL_STALL)


class Monitor:
    """watch each session's folder off the ui thread: one scan per session, stale results dropped."""

    def __init__(self, scanner=fingerprint):
        self.scanner = scanner
        self.lock = threading.Lock()
        self.baselines, self.generations = {}, {}
        self.pending, self.changed = set(), set()

    def arm(self, session, workspace):
        with self.lock:
            generation = self.generations.get(session, 0) + 1
            self.generations[session] = generation
            self.baselines.pop(session, None)
            self.changed.discard(session)

        def take():
            value = self.scanner(workspace)
            with self.lock:
                if self.generations.get(session) == generation and value is not None:
                    self.baselines[session] = value
        threading.Thread(target=take, daemon=True).start()

    def check(self, session, workspace):
        with self.lock:
            base, generation = self.baselines.get(session), self.generations.get(session)
            if base is None or session in self.pending or session in self.changed:
                return
            self.pending.add(session)

        def compare():
            value = self.scanner(workspace)
            with self.lock:
                self.pending.discard(session)
                if self.generations.get(session) == generation and value not in (None, base):
                    self.changed.add(session)
        threading.Thread(target=compare, daemon=True).start()

    def changed_sessions(self):
        with self.lock:
            return set(self.changed)

    def forget(self, session):
        with self.lock:
            for table in (self.baselines, self.generations):
                table.pop(session, None)
            self.pending.discard(session)
            self.changed.discard(session)


# markers for the opt-in block (read by pet_hook.py) ------------------------------------------
def flag_path(root):
    return Path(root) / "block-on-change"


def marker_path(root, session):
    return Path(root) / "context-changed" / session


def set_blocking(root, on):
    flag = flag_path(root)
    if on:
        Path(root).mkdir(parents=True, exist_ok=True)
        flag.touch()
    else:
        flag.unlink(missing_ok=True)
        folder = Path(root) / "context-changed"
        if folder.is_dir():
            for item in folder.iterdir():
                item.unlink(missing_ok=True)


def mark(root, session, reason="context"):
    if not SESSION.fullmatch(session):
        return
    path = marker_path(root, session)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(reason, encoding="utf-8")


def clear_mark(root, session):
    if SESSION.fullmatch(session):
        marker_path(root, session).unlink(missing_ok=True)
