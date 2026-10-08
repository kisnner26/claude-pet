"""render the project's uncommitted diff to a private file and open it."""

import os
from pathlib import Path
import subprocess
import sys

from gitpulse import is_directory, run

MAX_BYTES = 5 * 1024 * 1024
TIMEOUT = 20
ARGUMENTS = ["-c", "core.fsmonitor=false", "-c", "core.pager=cat", "diff",
             "--no-ext-diff", "--no-textconv", "--no-color", "--"]


def diff_bytes(workspace, limit=MAX_BYTES, timeout=TIMEOUT):
    """git diff without external drivers or filters defined by the repo; capped in size and time."""
    if not is_directory(workspace):
        return None
    result = run(["-C", workspace, *ARGUMENTS], timeout=timeout, limit=limit)
    if result is None or result[2] not in (0, None):
        return None
    data, truncated, _ = result
    if not data:
        data = "sin cambios sin commitear en el proyecto (git diff)\n".encode()
    if truncated:
        data += f"\n[recortado: el diff supera {limit // 1024 // 1024} MB]\n".encode()
    return data


def private_file(root, name, data):
    """write under the pet folder; the file may hold sensitive code, so keep it user-only."""
    folder = Path(root) / "review"
    folder.mkdir(parents=True, exist_ok=True, mode=0o700)
    path = folder / name
    path.write_bytes(data)
    if os.name != "nt":
        path.chmod(0o600)
    return path


def open_file(path):
    if os.name == "nt":
        os.startfile(str(path))  # noqa: S606 - opens the user's default viewer
    else:
        subprocess.Popen(["open" if sys.platform == "darwin" else "xdg-open", str(path)],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def open_diff(root, workspace):
    data = diff_bytes(workspace)
    if data is None:
        return None
    path = private_file(root, "claude-pet-review.diff", data)
    open_file(path)
    return path
