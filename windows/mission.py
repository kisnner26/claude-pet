"""mission control: timeline, collision radar, attention budget, git pulse and recovery capsule.
everything lives in memory; none of it is written to disk or sent over the pet bus."""

from collections import deque
from dataclasses import dataclass, replace
import threading
import time

from gitpulse import GitHealth, ScanCoordinator, is_directory, scan

ACTIVE = ("starting", "thinking", "tool", "waiting")
COLLISION_WORK = ("thinking", "tool")
GENERIC = {"app", "src", "web", "api", "backend", "frontend", "test", "tests",
           "docs", "lib", "core", "main"}


@dataclass(frozen=True)
class MissionEvent:
    at: float
    agent: str
    state: str
    project: str


@dataclass(frozen=True)
class Recovery:
    created_at: float
    project: str
    workspace: str
    health: GitHealth
    session: str


@dataclass(frozen=True)
class PendingError:
    session: str
    started_at: float
    project: str
    workspace: str


class Mission:
    def __init__(self, clock=time.time, scanner=scan):
        self.clock = clock
        self.coordinator = ScanCoordinator(scanner)
        self.lock = threading.RLock()
        self.timeline = deque(maxlen=16)
        self.git = GitHealth()
        self.collision = False
        self.recovery = None
        self.tool_calls = 0
        self.active_since = None
        self.tools = {}
        self.last_summary = None
        self.local = dict(state="idle", project="", workspace="", session="")
        self.peer = dict(state="idle", project="")
        self.candidate_since = None
        self.clear_since = None
        self.last_active_scan = float("-inf")
        self.last_manual_scan = float("-inf")
        self.health = {}
        self.pending_error = None
        self.dismissed = None
        self.handled = None

    # reads -------------------------------------------------------------
    @property
    def elapsed(self):
        return max(0.0, self.clock() - self.active_since) if self.active_since is not None else 0.0

    @property
    def top_tools(self):
        ordered = sorted(self.tools.items(), key=lambda item: (-item[1], item[0]))
        return ordered[:3]

    @property
    def focus_label(self):
        if self.active_since is not None:
            return self.summary(self.elapsed)
        return self.last_summary or "sin sesión activa"

    def summary(self, elapsed):
        base = f"{int(max(0, elapsed) // 60)} min · {self.tool_calls} herramientas"
        names = ", ".join(f"{name} ×{count}" for name, count in self.top_tools)
        return base + " · " + names if names else base

    # writes ------------------------------------------------------------
    def record_local(self, state, project, workspace="", session=""):
        with self.lock:
            now = self.clock()
            previous = self.local
            state_changed = state != previous["state"]
            workspace_changed = bool(workspace) and workspace != previous["workspace"]
            if state_changed or project != previous["project"]:
                self.timeline.appendleft(MissionEvent(now, "claude", state, project))
            active, was_active = state in ACTIVE, previous["state"] in ACTIVE
            if active and not was_active:
                self.active_since, self.tool_calls, self.tools, self.last_summary = now, 0, {}, None
            elif was_active and not active:
                self.last_summary = self.summary(now - (self.active_since or now))
                self.active_since = None
            if state == "error" and (previous["state"] != "error" or session != previous["session"]):
                self.pending_error = PendingError(session, now, project, workspace or previous["workspace"])
            elif state != "error":
                self.pending_error = self.dismissed = self.handled = None
            self.local = dict(state=state, project=project, session=session,
                              workspace=workspace or previous["workspace"])
            if workspace_changed or (state_changed and state in ("done", "error", "idle")):
                self.request_scan()
            self.update_collision(now)

    def record_tool(self, tool):
        with self.lock:
            self.tool_calls += 1
            name = tool or "herramienta"
            self.tools[name] = self.tools.get(name, 0) + 1

    def record_peer(self, state, project):
        with self.lock:
            now = self.clock()
            if state != self.peer["state"] or project != self.peer["project"]:
                self.timeline.appendleft(MissionEvent(now, "codex", state, project))
            self.peer = dict(state=state, project=project)
            self.update_collision(now)

    def peer_left(self):
        with self.lock:
            self.peer = dict(state="idle", project="")
            self.update_collision(self.clock())

    def tick(self):
        with self.lock:
            now = self.clock()
            self.update_collision(now)
            self.update_recovery(now)
            if self.local["state"] in ACTIVE and now - self.last_active_scan >= 15:
                self.request_scan()

    def clear_recovery(self):
        with self.lock:
            if self.pending_error:
                self.dismissed = self.pending_error
            self.recovery = None

    def refresh_git(self):
        with self.lock:
            now = self.clock()
            if now - self.last_manual_scan < 2:
                return
            self.last_manual_scan = now
            self.request_scan()

    # internals ---------------------------------------------------------
    @staticmethod
    def normalized(project):
        return project.replace("\\", "/").rsplit("/", 1)[-1].strip().lower()

    def update_collision(self, now):
        local, peer = self.normalized(self.local["project"]), self.normalized(self.peer["project"])
        candidate = (self.local["state"] in COLLISION_WORK and self.peer["state"] in COLLISION_WORK
                     and bool(local) and local == peer and local not in GENERIC)
        if candidate:
            self.clear_since = None
            if self.candidate_since is None:
                self.candidate_since = now
            if not self.collision and now - self.candidate_since >= 10:
                self.collision = True
            return
        self.candidate_since = None
        if self.collision:
            if self.clear_since is None:
                self.clear_since = now
            if now - self.clear_since >= 5:
                self.collision, self.clear_since = False, None
        else:
            self.clear_since = None

    def update_recovery(self, now):
        pending = self.pending_error
        if (not pending or self.local["state"] != "error" or now - pending.started_at < 3
                or self.dismissed == pending or self.handled == pending):
            return
        current = self.recovery
        if current and current.session == pending.session and now - current.created_at < 60:
            self.handled = pending
            return
        health = self.health.get(pending.workspace) or (
            self.git if pending.workspace == self.local["workspace"] else GitHealth())
        self.recovery = Recovery(now, pending.project, pending.workspace, health, pending.session)
        self.handled = pending

    def request_scan(self):
        workspace = self.local["workspace"]
        if not workspace or not is_directory(workspace):
            return
        self.last_active_scan = self.clock()
        self.coordinator.request(workspace, self.scanned)

    def scanned(self, workspace, result):
        with self.lock:
            self.health[workspace] = result
            if workspace == self.local["workspace"]:
                self.git = result
            if self.recovery and self.recovery.workspace == workspace:
                self.recovery = replace(self.recovery, health=result)
