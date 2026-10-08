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


TEST_COMMANDS = ("swift test", "npm test", "npm run test", "pnpm test", "yarn test",
                 "pytest", "python -m pytest", "python -m unittest", "php artisan test")


def tool_input(payload):
    value = payload.get("tool_input")
    return value if isinstance(value, dict) else {}


def classify_tool(tool, payload):
    """tests are recognised by looking only at the command of a shell tool; it is never kept."""
    if tool in ("Bash", "PowerShell"):
        command = " " + str(tool_input(payload).get("command", "")).lower() + " "
        if any(f" {name} " in command or f" {name}\n" in command for name in TEST_COMMANDS):
            return "test"
    return tool


def bubble_detail(tool, payload):
    """minimum local detail for the bubble: a description, a file name, a pattern, the program
    of a command (never its arguments) or the host of a url."""
    data = tool_input(payload)
    detail = str(data.get("description") or "")
    if not detail and data.get("file_path"):
        detail = PureWindowsPath(str(data["file_path"])).name
    if not detail:
        detail = str(data.get("pattern") or "")
    if not detail and data.get("command"):
        words = str(data["command"]).split()
        program = PureWindowsPath(words[0]).name if words else ""
        detail = f"$ {program}" if program else ""
    if not detail and data.get("url"):
        detail = str(data["url"]).split("://", 1)[-1].split("/", 1)[0]
    return text(detail, 120).replace("\\", "")


def current_task(name, tool, payload):
    """the user's last message (p:) or the task in progress from claude's list (t:)."""
    if name == "UserPromptSubmit":
        prompt = " ".join(str(payload.get("prompt", "")).split())
        return ("p:" + text(prompt, 200)) if prompt else ""
    if name in ("PreToolUse", "PostToolUse") and tool in ("TodoWrite", "TaskUpdate", "TaskCreate"):
        for item in tool_input(payload).get("todos", []) if isinstance(tool_input(payload).get("todos"), list) else []:
            if isinstance(item, dict) and item.get("status") == "in_progress" and item.get("activeForm"):
                return "t:" + text(str(item["activeForm"]), 200)
    return ""


def event_line(name, payload):
    state = HOOKS[name]
    session = identifier(str(payload.get("session_id", "x")), 16) or "x"
    raw_tool = identifier(str(payload.get("tool_name", "")), 40)
    tool = classify_tool(raw_tool, payload) if state == "tool" else raw_tool
    cwd = text(str(payload.get("cwd", "")), 1024)
    project = identifier(PureWindowsPath(cwd).name, 40)
    detail = bubble_detail(raw_tool, payload) if state in ("tool", "waiting") else ""
    task = current_task(name, raw_tool, payload)
    # the detail and the task stay local: they never cross the pet bus.
    fields = [state, session, tool, project, detail.replace("\t", " "), "terminal",
              task.replace("\t", " "), cwd]
    # the local transport rejects lines over 2048 bytes: shed the optional text first.
    for index in (6, 4):
        if len("\t".join(fields).encode("utf-8")) <= 2000:
            break
        fields[index] = ""
    return "\t".join(fields)


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
