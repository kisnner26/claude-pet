"""build and verify a standalone windows distribution with pyinstaller."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from zipfile import ZipFile, ZIP_DEFLATED


def main():
    if os.name != "nt":
        raise SystemExit("el paquete de windows debe compilarse en windows")
    repository = Path(__file__).resolve().parent.parent
    source = repository / "windows"
    output = repository / "build" / "windows"
    distribution = output / "dist"
    targets = (("claude-pet", "claude_pet.py", True),
               ("claude-pet-hook", "hook_entry.py", False),
               ("install-hooks", "install_hooks.py", False))
    for name, entry, windowed in targets:
        command = [sys.executable, "-m", "PyInstaller", "--noconfirm", "--clean",
                   "--onedir", "--noupx", "--name", name, "--paths", str(source),
                   "--distpath", str(distribution), "--workpath", str(output / "work" / name),
                   "--specpath", str(output / "spec"), str(source / entry)]
        if windowed:
            command.append("--windowed")
        subprocess.run(command, check=True, cwd=repository)

    application = distribution / "claude-pet" / "claude-pet.exe"
    hook = distribution / "claude-pet-hook" / "claude-pet-hook.exe"
    installer = distribution / "install-hooks" / "install-hooks.exe"
    subprocess.run([str(application), "--self-test"], check=True, timeout=30)
    environment = {**os.environ, "PYTHONPATH": str(source), "PET_HOOK_EXECUTABLE": str(hook)}
    subprocess.run([sys.executable, "-m", "unittest", "discover", "-s", str(source / "tests"),
                    "-p", "test_hooks.py", "-v"], env=environment, check=True, timeout=60)
    with tempfile.TemporaryDirectory() as directory:
        settings = Path(directory) / "settings.json"
        subprocess.run([str(installer), "--settings", str(settings), "--apply"], check=True, timeout=30)
        configured = json.loads(settings.read_text(encoding="utf-8"))
        installed = configured["hooks"]["Stop"][0]["hooks"][0]
        if installed["command"] != str(hook) or installed["args"] != ["Stop"]:
            raise RuntimeError("el instalador no apunta al hook empaquetado")
        subprocess.run([str(installer), "--settings", str(settings), "--uninstall", "--apply"],
                       check=True, timeout=30)
        if json.loads(settings.read_text(encoding="utf-8"))["hooks"]:
            raise RuntimeError("el instalador no retiró los hooks empaquetados")
    with ZipFile(output / "claude-pet-windows.zip", "w", ZIP_DEFLATED) as archive:
        for path in sorted(distribution.rglob("*")):
            if path.is_file():
                archive.write(path, path.relative_to(distribution))
        archive.write(source / "README.md", "README.md")


if __name__ == "__main__":
    main()
