"""cross review between claude code and codex, and ways out of a project collision.

a review sends the project's uncommitted diff to the *other* agent, in read-only mode, only when
the user asks for it from the menu. nothing here runs on its own."""

from datetime import datetime
import os
from pathlib import Path
import shutil
import subprocess
import threading
import time

from diffview import private_file, raw_diff
from gitpulse import is_directory, run

PROMPT_DIFF_LIMIT = 120 * 1024
OUTPUT_LIMIT = 1024 * 1024
TIMEOUT = 600
NAMES = {"claude": "Claude", "codex": "Codex"}
EXTRA_DIRS = (".local/bin", ".npm-global/bin", ".bun/bin", ".volta/bin", "AppData/Roaming/npm",
              ".claude/local", ".codex/bin")


def find_agent(name, home=None):
    """locate the cli of an agent; apps launched from a menu often lack the shell's PATH."""
    found = shutil.which(name)
    if found:
        return found
    home = Path(home or Path.home())
    candidates = [home / folder / name for folder in EXTRA_DIRS]
    candidates += [Path("/opt/homebrew/bin") / name, Path("/usr/local/bin") / name]
    for base in candidates:
        for suffix in ("", ".cmd", ".exe"):
            path = base.with_name(base.name + suffix)
            if path.is_file() and os.access(path, os.X_OK):
                return str(path)
    return None


def build_command(reviewer, executable, workspace, output):
    """read-only invocation of the reviewing agent; the prompt always goes through stdin."""
    if reviewer == "codex":
        return [executable, "exec", "--sandbox", "read-only", "--skip-git-repo-check",
                "--ephemeral", "-C", str(workspace), "-o", str(output), "-"]
    if reviewer == "claude":
        return [executable, "-p", "--permission-mode", "plan", "--tools", "Read,Grep,Glob",
                "--no-session-persistence"]
    raise ValueError("revisor desconocido")


def untracked_names(workspace, limit=50):
    result = run(["--no-optional-locks", "-c", "core.fsmonitor=false", "-C", str(workspace),
                  "ls-files", "--others", "--exclude-standard", "-z"], timeout=10, limit=256 * 1024)
    if result is None or result[2] != 0:
        return []
    names = [n.decode("utf-8", "replace") for n in result[0].split(b"\0") if n]
    return names[:limit]


def review_prompt(author, project, task, diff, truncated, untracked):
    parts = [
        f"Eres el segundo par de ojos de un cambio hecho por {NAMES[author]}"
        + (f" en el proyecto «{project}»." if project else "."),
        "Revisa el diff de abajo. Solo lectura: no modifiques archivos ni ejecutes nada que escriba.",
        "Busca, por orden de importancia: errores de lógica, problemas de seguridad, casos límite sin "
        "cubrir, pruebas que faltan y regresiones. Puedes leer los archivos del proyecto para entender "
        "el contexto. Ignora el estilo salvo que cause errores.",
        "Responde en español, breve. Por cada hallazgo: severidad (alta/media/baja), archivo:línea, "
        "el problema y un arreglo concreto. Si no encuentras nada serio, dilo claramente.",
    ]
    if task:
        parts.append(f"Tarea que se le pidió al otro agente: {task}")
    if untracked:
        parts.append("Archivos nuevos sin seguimiento (no están en el diff, léelos): "
                     + ", ".join(untracked))
    body = diff.decode("utf-8", "replace")
    parts.append("--- diff ---\n" + body + ("\n[diff recortado por tamaño; lee el resto con git diff]"
                                            if truncated else ""))
    return "\n\n".join(parts)


def prepare(workspace, author, project="", task=""):
    """collect what would be sent. returns (prompt, size_in_bytes) or an error string."""
    if not is_directory(workspace):
        return None, "no hay una carpeta de proyecto conocida"
    result = raw_diff(workspace, limit=PROMPT_DIFF_LIMIT)
    if result is None:
        return None, "el proyecto no es un repositorio git"
    diff, truncated = result
    untracked = untracked_names(workspace)
    if not diff and not untracked:
        return None, "no hay cambios sin commitear para revisar"
    prompt = review_prompt(author, project, task, diff, truncated, untracked)
    return prompt, len(prompt.encode("utf-8"))


class Review:
    """one review running in the background; at most one at a time per pet."""

    def __init__(self, reviewer, workspace, project, root, prompt, executable=None, timeout=TIMEOUT):
        self.reviewer, self.workspace, self.project = reviewer, str(workspace), project
        self.root, self.prompt, self.timeout = Path(root), prompt, timeout
        self.executable = executable or find_agent(reviewer)
        self.state, self.error, self.result, self.started = "idle", "", None, 0.0
        self.process = None
        self.cancelled = False
        self.done = threading.Event()

    @property
    def author(self):
        return "claude" if self.reviewer == "codex" else "codex"

    @property
    def running(self):
        return self.state == "running"

    def start(self):
        if not self.executable:
            self.state, self.error = "failed", f"no se encontró {self.reviewer} en este equipo"
            self.done.set()
            return
        self.state, self.started = "running", time.monotonic()
        threading.Thread(target=self.work, daemon=True).start()

    def cancel(self):
        self.cancelled = True
        process = self.process
        if process and process.poll() is None:
            process.kill()

    def work(self):
        stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        folder = self.root / "review"
        folder.mkdir(parents=True, exist_ok=True, mode=0o700)
        output = folder / f".{self.reviewer}-{stamp}.out"
        environment = {**os.environ, "CLAUDE_PET_REVIEW": "1", "GIT_TERMINAL_PROMPT": "0"}
        try:
            self.process = subprocess.Popen(
                build_command(self.reviewer, self.executable, self.workspace, output),
                cwd=self.workspace, env=environment, stdin=subprocess.PIPE,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
            stdout, stderr = self.process.communicate(self.prompt.encode("utf-8"), self.timeout)
            code = self.process.returncode
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.communicate()
            self.state, self.error = "failed", "la revisión superó el tiempo máximo"
            return self.finish(output)
        except OSError as error:
            self.state, self.error = "failed", f"no se pudo lanzar {self.reviewer}: {error.strerror or error}"
            return self.finish(output)
        if self.cancelled:
            self.state = "cancelled"
            return self.finish(output)
        text = ""
        if self.reviewer == "codex" and output.is_file():
            text = output.read_text(encoding="utf-8", errors="replace")
        text = (text or stdout.decode("utf-8", "replace")).strip()[:OUTPUT_LIMIT]
        if code != 0 or not text:
            detail = stderr.decode("utf-8", "replace").strip().splitlines()[-1:] or ["sin respuesta"]
            self.state, self.error = "failed", f"{self.reviewer} terminó con error ({code}): {detail[0][:160]}"
            return self.finish(output)
        header = (f"# revisión de {NAMES[self.reviewer]} sobre cambios de {NAMES[self.author]}\n"
                  f"proyecto: {self.project or '-'} · {datetime.now():%Y-%m-%d %H:%M}\n\n")
        self.result = private_file(self.root, f"review-{self.reviewer}-{stamp}.md",
                                   (header + text + "\n").encode("utf-8"))
        self.state = "done"
        self.finish(output)

    def finish(self, output):
        output.unlink(missing_ok=True)
        self.done.set()


def worktree_destination(workspace, agent):
    base = Path(workspace)
    return base.with_name(f"{base.name}-pet-{agent}")


def create_worktree(workspace, agent):
    """give the second agent its own checkout on a new branch, so the two stop editing the same
    files. nothing is deleted or moved; uncommitted changes stay where they are."""
    if not is_directory(workspace):
        raise ValueError("no hay una carpeta de proyecto conocida")
    destination = worktree_destination(workspace, agent)
    if destination.exists():
        raise ValueError(f"ya existe {destination}")
    branch = f"pet/{agent}-{datetime.now():%Y%m%d-%H%M%S}"
    result = run(["-C", str(workspace), "worktree", "add", "-b", branch, str(destination)], timeout=60)
    if result is None or result[2] != 0:
        raise ValueError("git no pudo crear el worktree (¿repositorio sin commits?)")
    return destination, branch
