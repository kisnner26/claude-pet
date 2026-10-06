"""preview by default; --apply installs only this frontend's hook commands."""

import argparse
import copy
from datetime import datetime, timezone
import difflib
import json
from pathlib import Path
import subprocess
import sys

from pet_hook import HOOKS


def merge(settings, script, executable, uninstall=False):
    result = copy.deepcopy(settings)
    hooks = result.setdefault("hooks", {})
    marker = subprocess.list2cmdline([str(script)])
    for event in HOOKS:
        entries = []
        for entry in hooks.get(event, []):
            remaining = [hook for hook in entry.get("hooks", [])
                         if not (hook.get("args", [None])[0:1] == [str(script)]
                                 or marker in hook.get("command", ""))]
            if remaining:
                entries.append({**entry, "hooks": remaining})
        if not uninstall:
            entries.append({"matcher": "", "hooks": [{"type": "command",
                            "command": executable, "args": [str(script), event]}]})
        if entries:
            hooks[event] = entries
        else:
            hooks.pop(event, None)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--uninstall", action="store_true")
    parser.add_argument("--settings", type=Path, default=Path.home() / ".claude" / "settings.json")
    args = parser.parse_args()
    path = args.settings
    original = path.read_text(encoding="utf-8") if path.exists() else "{}\n"
    settings = json.loads(original)
    script = Path(__file__).resolve().with_name("pet_hook.py")
    updated = json.dumps(merge(settings, script, sys.executable, args.uninstall),
                         indent=2, ensure_ascii=False) + "\n"
    print("".join(difflib.unified_diff(original.splitlines(True), updated.splitlines(True),
                                     fromfile=str(path), tofile=str(path))), end="")
    if not args.apply:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        suffix = datetime.now(timezone.utc).strftime("%Y%m%d%H%M%S%f")
        path.with_name(path.name + f".claudepet-{suffix}.bak").write_text(original, encoding="utf-8")
    temporary = path.with_name(path.name + ".claudepet.tmp")
    temporary.write_text(updated, encoding="utf-8")
    temporary.replace(path)


if __name__ == "__main__":
    main()
