"""fail-open claude code hook: no stdout and no transcript persistence."""

import json
from pathlib import Path, PureWindowsPath
import subprocess
import sys

from pet_ipc import send
from pet_state import identifier, text

HOOKS = dict(SessionStart="starting", UserPromptSubmit="thinking", PreToolUse="tool",
             PostToolUse="thinking", PermissionRequest="waiting", PermissionDenied="thinking",
             PostToolUseFailure="error", StopFailure="error", Stop="done", SessionEnd="end")


def event_line(name, payload):
    state = HOOKS[name]
    session = identifier(str(payload.get("session_id", "x")), 16) or "x"
    tool = identifier(str(payload.get("tool_name", "")), 40)
    cwd = text(str(payload.get("cwd", "")), 1024)
    project = identifier(PureWindowsPath(cwd).name, 40)
    # command arguments and prompts are deliberately excluded from this port.
    return "\t".join((state, session, tool, project, "", "terminal", "", cwd))


def main():
    try:
        if len(sys.argv) != 2 or sys.argv[1] not in HOOKS:
            return
        raw = sys.stdin.buffer.read(65537)
        if len(raw) > 65536:
            return
        payload = json.loads(raw)
        if not isinstance(payload, dict):
            return
        line = event_line(sys.argv[1], payload)
        root = Path.home() / ".claude-pet"
        if not (root / "windows-pet.key").is_file():
            return
        # isolate the connection so a stopped or wedged pet cannot block a tool.
        worker = [sys.executable]
        if not getattr(sys, "frozen", False):
            worker.append(str(Path(__file__).resolve()))
        subprocess.run([*worker, "--send", line],
                       timeout=1, stdin=subprocess.DEVNULL,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                       creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    except (OSError, ValueError, KeyError, subprocess.TimeoutExpired):
        pass


def run():
    if len(sys.argv) == 3 and sys.argv[1] == "--send":
        try:
            send(Path.home() / ".claude-pet", sys.argv[2])
        except Exception:
            pass
    else:
        main()


if __name__ == "__main__":
    run()
