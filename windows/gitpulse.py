"""read-only git health of a project: counts only, never file contents."""

from dataclasses import dataclass, replace
import os
from pathlib import Path
import subprocess
import threading

OUTPUT_LIMIT = 4 * 1024 * 1024
ENTRY_LIMIT = 20_000
CONFLICTS = {"UU", "AA", "DD", "AU", "UA", "DU", "UD"}


@dataclass(frozen=True)
class GitHealth:
    changed: int = 0
    staged: int = 0
    untracked: int = 0
    conflicts: int = 0
    affected: int = 0
    branch: str = ""
    available: bool = False
    limited: bool = False

    @property
    def label(self):
        if not self.available:
            return "sin repositorio git"
        if self.conflicts:
            return f"{self.conflicts} conflictos"
        if not self.affected:
            return "árbol limpio"
        noun = "cambio" if self.affected == 1 else "cambios"
        return f"{self.affected} {noun} · {self.staged} staged" + (" · sin untracked" if self.limited else "")


def branch_name(header):
    value = header[3:]
    for prefix in ("No commits yet on ", "Initial commit on "):
        if value.startswith(prefix):
            return value[len(prefix):]
    return value.split("...")[0]


def parse(data, limited=False):
    """parse `git status -b --porcelain=v1 -z` output."""
    records = [part.decode("utf-8", "replace") for part in data.split(b"\0")]
    health = dict(changed=0, staged=0, untracked=0, conflicts=0, affected=0, branch="")
    index = 0
    while index < len(records):
        record = records[index]
        if record.startswith("## "):
            health["branch"] = branch_name(record)
            index += 1
            continue
        if len(record) < 2:
            index += 1
            continue
        status = record[:2]
        health["affected"] += 1
        if status == "??":
            health["untracked"] += 1
        elif status in CONFLICTS:
            health["conflicts"] += 1
        else:
            if status[0] not in " ?":
                health["staged"] += 1
            if status[1] != " ":
                health["changed"] += 1
        if status[0] in "RC" or status[1] in "RC":
            index += 1  # porcelain -z puts the origin path in the next record
        index += 1
    return GitHealth(**health, available=True, limited=limited)


def is_directory(workspace):
    try:
        path = Path(workspace)
        return path.is_absolute() and path.is_dir()
    except (OSError, ValueError):
        return False


def run(arguments, cwd=None, timeout=10, limit=OUTPUT_LIMIT):
    """run git without prompts, optional locks or repo-defined helpers; capped in size and time."""
    environment = {**os.environ, "GIT_OPTIONAL_LOCKS": "0", "GIT_TERMINAL_PROMPT": "0"}
    flags = getattr(subprocess, "CREATE_NO_WINDOW", 0)
    try:
        process = subprocess.Popen(["git", *arguments], cwd=cwd, env=environment,
                                   stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                   stderr=subprocess.DEVNULL, creationflags=flags)
    except OSError:
        return None
    chunks, size, truncated = [], 0, False

    def pump():
        nonlocal size, truncated
        while True:
            chunk = process.stdout.read(65536)
            if not chunk:
                return
            room = limit - size
            if room > 0:
                chunks.append(chunk[:room])
                size += min(room, len(chunk))
            if len(chunk) > room:
                truncated = True

    reader = threading.Thread(target=pump, daemon=True)
    reader.start()
    try:
        process.wait(timeout)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()
    reader.join(1)
    process.stdout.close()
    return b"".join(chunks), truncated, process.returncode


def status(workspace, untracked, timeout):
    result = run(["--no-optional-locks", "-c", "core.fsmonitor=false", "-C", workspace,
                  "status", "-b", "--porcelain=v1", "-z",
                  "--untracked-files=normal" if untracked else "--untracked-files=no"],
                 timeout=timeout)
    if result is None or result[2] != 0:
        return None
    return result[0], result[1]


def scan(workspace, timeout=10):
    if not is_directory(workspace):
        return GitHealth()
    first = status(workspace, True, timeout)
    if first is None:
        return GitHealth()
    if first[1] or first[0].count(b"\0") > ENTRY_LIMIT:
        compact = status(workspace, False, timeout)
        return parse(compact[0], limited=True) if compact else GitHealth()
    return parse(first[0])


class ScanCoordinator:
    """at most one scan running and one waiting: the newest request replaces the older one."""

    def __init__(self, scanner=scan):
        self.scanner = scanner
        self.lock = threading.Lock()
        self.running = False
        self.pending = None
        self.starts = 0

    def request(self, workspace, completion):
        with self.lock:
            if self.running:
                self.pending = (workspace, completion)
                return
            self.running = True
            self.starts += 1
        threading.Thread(target=self.work, args=(workspace, completion), daemon=True).start()

    def work(self, workspace, completion):
        while True:
            try:
                completion(workspace, self.scanner(workspace))
            except Exception:
                pass
            with self.lock:
                if self.pending is None:
                    self.running = False
                    return
                workspace, completion = self.pending
                self.pending = None
                self.starts += 1
