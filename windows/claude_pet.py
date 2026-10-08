"""desktop pet frontend using the tkinter shipped with python for windows."""

import json
import os
import sys
import tempfile
import threading
import time
from pathlib import Path
from queue import Empty, Queue
import tkinter as tk
from tkinter import messagebox

from pet_ipc import start_server
from pet_state import Event, PRIORITY, Sessions
from pet_bus import PeerMessage, Peers
from bubble import LABELS, describe
from diffview import open_diff, open_file
import handoff
from mission import Mission
from workspace import Monitor, clear_mark, flag_path, mark, set_blocking, stalled
from pet_position import HEIGHT, WIDTH, desktop_bounds, geometry

ROOT = Path.home() / ".claude-pet"
TRANSPARENT = "#ff00ff"


class Pet:
    def __init__(self, kind="claude", master=None):
        self.kind = kind
        self.codex = None
        self.peer_event = None
        self.events = Queue()
        self.sessions = Sessions()
        self.peers = Peers()
        self.mission = Mission() if kind == "claude" else None
        self.monitor = Monitor()
        self.alert = None
        self.alert_tone = "warn"
        self.last_key = None
        self.marked = set()
        self.next_scan = 0.0
        self.stall_watch = True
        self.review = None
        self.notice = None
        self.notice_done = True
        self.listener = start_server(ROOT, self.events.put) if master is None else None
        self.window = tk.Tk() if master is None else tk.Toplevel(master)
        self.window.title(f"{kind}-pet")
        self.window.overrideredirect(True)
        self.window.attributes("-topmost", True)
        self.window.configure(bg=TRANSPARENT)
        if os.name == "nt":
            self.window.attributes("-transparentcolor", TRANSPARENT)
        self.canvas = tk.Canvas(self.window, width=WIDTH, height=HEIGHT,
                                bg=TRANSPARENT, highlightthickness=0)
        self.canvas.pack()
        self.tick = 0
        self.animations = True
        self.drag = None
        self.settings = ROOT / f"windows-{kind}-position.json"
        try:
            position = json.loads(self.settings.read_text(encoding="utf-8"))
            x, y = int(position["x"]), int(position["y"])
            self.animations = bool(position.get("animations", True))
            self.stall_watch = bool(position.get("stall_watch", True))
        except (OSError, ValueError, OverflowError, KeyError, TypeError):
            x = self.window.winfo_screenwidth() - (WIDTH + 20 if kind == "claude" else 2 * WIDTH + 40)
            y = self.window.winfo_screenheight() - HEIGHT - 60
        x, y = desktop_bounds(self.window).clamp(x, y)
        self.window.geometry(geometry(x, y))
        self.canvas.bind("<ButtonPress-1>", self.begin_drag)
        self.canvas.bind("<B1-Motion>", self.move)
        self.canvas.bind("<ButtonRelease-1>", self.save)
        self.canvas.bind("<Button-3>", self.menu)
        self.window.bind("<Escape>", lambda _: self.close())
        self.window.protocol("WM_DELETE_WINDOW", self.close)
        self.window.bind("<<PetQuit>>", lambda _: self.close())
        if kind == "claude":
            self.codex = Pet("codex", self.window)
        else:
            self.window.withdraw()
        self.update()

    def begin_drag(self, event):
        self.drag = (event.x_root - self.window.winfo_x(),
                     event.y_root - self.window.winfo_y())

    def move(self, event):
        if self.drag:
            x, y = desktop_bounds(self.window).clamp(event.x_root - self.drag[0],
                                                     event.y_root - self.drag[1])
            self.window.geometry(geometry(x, y))

    def save(self, _event=None):
        self.drag = None
        data = dict(x=self.window.winfo_x(), y=self.window.winfo_y(),
                    animations=self.animations, stall_watch=self.stall_watch)
        temporary = self.settings.with_suffix(".tmp")
        temporary.write_text(json.dumps(data), encoding="utf-8")
        temporary.replace(self.settings)

    def toggle_animation(self):
        self.animations = not self.animations
        self.save()

    def demo(self, state):
        self.sessions.apply(Event(state, "preview"))
        if self.kind == "codex" and state != "end":
            self.window.deiconify()

    def menu(self, event):
        menu = tk.Menu(self.window, tearoff=False)
        preview = tk.Menu(menu, tearoff=False)
        for state in PRIORITY:
            preview.add_command(label=LABELS[state], command=lambda s=state: self.demo(s))
        preview.add_command(label="terminar prueba", command=lambda: self.demo("end"))
        menu.add_cascade(label="probar estado", menu=preview)
        if self.mission:
            self.mission_menu(menu)
        menu.add_command(label="pausar animación" if self.animations else "activar animación",
                         command=self.toggle_animation)
        menu.add_separator()
        menu.add_command(label="salir", command=self.close)
        try:
            menu.tk_popup(event.x_root, event.y_root)
        finally:
            menu.grab_release()

    def mission_menu(self, menu):
        mission, panel = self.mission, tk.Menu(menu, tearoff=False)
        panel.add_command(label=f"git: {mission.git.label}", state="disabled")
        if mission.git.branch:
            panel.add_command(label=f"rama: {mission.git.branch}", state="disabled")
        panel.add_command(label=f"atención: {mission.focus_label}", state="disabled")
        panel.add_separator()
        history = tk.Menu(panel, tearoff=False)
        for item in list(mission.timeline)[:8]:
            history.add_command(label=f"{time.strftime('%H:%M:%S', time.localtime(item.at))}  "
                                f"{item.agent}: {LABELS.get(item.state, item.state)}"
                                + (f" · {item.project}" if item.project else ""), state="disabled")
        if not mission.timeline:
            history.add_command(label="sin cambios todavía", state="disabled")
        panel.add_cascade(label="línea de tiempo", menu=history)
        panel.add_separator()
        workspace = self.current_workspace()
        panel.add_command(label="abrir diff del proyecto", command=self.show_diff,
                          state="normal" if workspace else "disabled")
        if mission.recovery:
            panel.add_command(label=f"recuperar: abrir diff de {mission.recovery.project or 'el proyecto'}",
                              command=lambda: self.show_diff(mission.recovery.workspace))
            panel.add_command(label="descartar cápsula de recuperación", command=mission.clear_recovery)
        panel.add_command(label="actualizar git", command=mission.refresh_git)
        panel.add_separator()
        panel.add_checkbutton(label="avisar si algo se atasca", onvalue=True, offvalue=False,
                              variable=self.flag("stall_watch"), command=self.toggle_stall)
        blocking = flag_path(ROOT).is_file()
        panel.add_command(label=("desactivar" if blocking else "activar") +
                          " bloqueo de herramientas si el proyecto cambia",
                          command=lambda: set_blocking(ROOT, not blocking))
        menu.add_cascade(label="mission control", menu=panel)
        self.handoff_menu(menu)

    def handoff_menu(self, menu):
        panel, review = tk.Menu(menu, tearoff=False), self.review
        workspace = self.known_workspace()
        busy = bool(review and review.running)
        if busy:
            panel.add_command(label=f"{handoff.NAMES[review.reviewer]} está revisando…", state="disabled")
            panel.add_command(label="cancelar revisión", command=review.cancel)
        else:
            for reviewer in ("codex", "claude"):
                author = "claude" if reviewer == "codex" else "codex"
                available = bool(workspace and handoff.find_agent(reviewer))
                panel.add_command(
                    label=f"pedir a {reviewer} que revise lo de {author}",
                    command=lambda r=reviewer: self.start_review(r),
                    state="normal" if available else "disabled")
            if not workspace:
                panel.add_command(label="aún no conozco el proyecto (usa claude una vez)", state="disabled")
        if review and review.result:
            panel.add_command(label="abrir la última revisión", command=lambda: open_file(review.result))
        if self.mission and self.mission.collision:
            panel.add_separator()
            panel.add_command(label="colisión: pausar a claude hasta mi próximo mensaje",
                              command=self.pause_claude)
            panel.add_command(label="colisión: worktree aislado para codex",
                              command=lambda: self.isolate("codex"))
            panel.add_command(label="colisión: worktree aislado para claude",
                              command=lambda: self.isolate("claude"))
        menu.add_cascade(label="traspaso claude y codex", menu=panel)

    def known_workspace(self):
        return self.current_workspace() or (self.mission.local["workspace"] if self.mission else "")

    def start_review(self, reviewer):
        workspace = self.known_workspace()
        author = "claude" if reviewer == "codex" else "codex"
        project = self.mission.local["project"]
        task = self.sessions.task(self.sessions.current())
        prompt, detail = handoff.prepare(workspace, author, project, task)
        if prompt is None:
            messagebox.showinfo("claude pet", detail, parent=self.window)
            return
        provider = "OpenAI" if reviewer == "codex" else "Anthropic"
        if not messagebox.askokcancel(
                "claude pet", f"Se enviará el diff sin commitear de «{project or workspace}» "
                f"(unos {detail // 1024 + 1} KB), junto con tu última tarea, a {reviewer} ({provider}) "
                "en modo solo lectura. ¿Continuar?", parent=self.window):
            return
        self.review = handoff.Review(reviewer, workspace, project, ROOT, prompt)
        self.review.start()
        self.notice_done = False

    def pause_claude(self):
        project = self.mission.local["project"]
        for session, (event, _) in list(self.sessions.entries.items()):
            if event.project == project and event.state != "end":
                mark(ROOT, session, "paused")

    def isolate(self, agent):
        try:
            destination, branch = handoff.create_worktree(self.known_workspace(), agent)
        except ValueError as error:
            messagebox.showerror("claude pet", str(error), parent=self.window)
            return
        self.window.clipboard_clear()
        self.window.clipboard_append(str(destination))
        messagebox.showinfo("claude pet", f"Worktree creado en la rama {branch}.\n{destination}\n"
                            f"La ruta está en el portapapeles: abre {agent} ahí.", parent=self.window)

    def flag(self, name):
        return tk.BooleanVar(master=self.window, value=getattr(self, name))

    def toggle_stall(self):
        self.stall_watch = not self.stall_watch
        self.save()

    def current_workspace(self):
        event = self.sessions.current()
        return event.workspace

    def show_diff(self, workspace=None):
        workspace = workspace or self.current_workspace()
        if workspace:
            threading.Thread(target=open_diff, args=(ROOT, workspace), daemon=True).start()

    def draw(self, event):
        self.canvas.delete("all")
        state, tick = event.state, self.tick if self.animations else 0
        if self.kind == "codex":
            self.draw_codex(state, tick)
            return
        scale, left, top = 7, 44, 12
        dy = -1 if self.animations and state == "done" and tick % 8 < 2 else 0
        dx = (1 if tick % 2 else -1) if self.animations and state == "error" else 0

        def rect(x, y, w, h, color):
            self.canvas.create_rectangle(left + (x + dx) * scale,
                                         top + (y + dy) * scale,
                                         left + (x + dx + w) * scale,
                                         top + (y + dy + h) * scale,
                                         fill=color, outline="")

        body, light, dark, ink = "#e0824f", "#ec9a6e", "#b9603a", "#1c1b1a"
        ear = -3 if state == "waiting" else -2 if state == "done" else 2 if state == "error" else 0
        if state == "tool":
            ear = tick % 2
        rect(0, 7 + ear, 2, 4, body)
        rect(14, 7 + ear, 2, 4, body)
        for x in (3, 6, 9, 12):
            rect(x, 13, 2, 3, body)
            rect(x, 15, 2, 1, dark)
        rect(2, 4, 12, 9, body)
        rect(2, 4, 12, 1, light)
        rect(13, 5, 1, 8, dark)
        rect(2, 12, 12, 1, dark)
        eyes = [(4, 6), (5, 7), (6, 8), (5, 9), (4, 10),
                (11, 6), (10, 7), (9, 8), (10, 9), (11, 10)]
        if state == "waiting":
            rect(4, 6, 2, 5, ink)
            rect(10, 6, 2, 5, ink)
            eyes = []
        elif state == "done":
            eyes = [(4, 9), (5, 8), (6, 9), (9, 9), (10, 8), (11, 9)]
        elif state == "error":
            eyes = [(4, 6), (6, 6), (5, 7), (4, 8), (6, 8),
                    (9, 6), (11, 6), (10, 7), (9, 8), (11, 8)]
        elif state == "starting" or state == "idle" and tick % 30 >= 28:
            eyes = [(x, 8) for x in (4, 5, 6, 9, 10, 11)]
        elif state == "thinking":
            shift = (-1, 0, 1, 0)[(tick // 4) % 4]
            eyes = [(x + shift, y - 1) for x, y in eyes]
        for x, y in eyes:
            rect(x, y, 1, 1, ink)
        if state == "thinking":
            for index in range((tick // 3) % 4):
                rect(5 + index * 3, 1, 1, 1, "#ede3da")
        elif state == "waiting":
            rect(7, 0, 2, 2, "#ede3da")
            rect(7, 3, 2, 1, "#ede3da")
        elif state == "tool":
            rect(5 + tick % 4, 11, 3, 1, ink)
        title, subtitle = describe(state, event.tool, event.detail, self.sessions.task(event))
        if self.alert:
            self.finish("claude", "error" if self.alert_tone == "warn" else "tool", *self.alert)
        else:
            self.finish("claude", state, title or LABELS[state], subtitle or event.origin)

    def finish(self, who, state, title, subtitle):
        """center the sprite in the wider window, then draw the bubble under it."""
        self.canvas.move("all", (WIDTH - 200) // 2, 0)
        if state == "idle" and not subtitle:
            title = LABELS["idle"]
        self.bubble(title, subtitle, "#e0824f" if state == "waiting" else
                    "#ff8a7a" if state == "error" else "#ede3da")

    def bubble(self, title, subtitle, accent):
        left, top, right, bottom = 6, 128, WIDTH - 6, HEIGHT - 4
        r = 10
        points = [left + r, top, right - r, top, right, top, right, top + r,
                  right, bottom - r, right, bottom, right - r, bottom, left + r, bottom,
                  left, bottom, left, bottom - r, left, top + r, left, top]
        self.canvas.create_polygon(points, smooth=True, fill="#1c1b1a", outline="#3a3835")
        limit = 32
        title = title if len(title) <= limit else title[:limit - 1] + "…"
        subtitle = subtitle if len(subtitle) <= 38 else subtitle[:37] + "…"
        self.canvas.create_text(left + 12, top + (14 if subtitle else 29), anchor="w", text=title,
                                fill=accent, font=("Segoe UI", 10, "bold"))
        if subtitle:
            self.canvas.create_text(left + 12, top + 38, anchor="w", text=subtitle,
                                    fill="#9a948c", font=("Consolas", 9))

    def draw_codex(self, state, tick):
        # the same cloud robot grid and palette as CodexAvatar.swift.
        head = (".....OOOOOOOO.....", "..OLOOBBBBBBOOOO..", ".OLLBBBBBBBBBBBBO.",
                ".OLBBssssssssBBBO.", "OLBBsSSSSSSSSsBBBO", "OLBBsSSSSSSSSsBBBO",
                "OBBBsSSSSSSSSsBBBO", "OBBBsSSSSSSSSsBBBO", "OBBBsSSSSSSSSsBBBO",
                ".OBBBssssssssBBBO.", "..ODDDDDDDDDDDDO..", "...OOOOOOOOOOOO...")
        body = (".....OOOOOOOO.....", "..OOOBBBBBBBBOOO..", "..OBBBBCWWWBBBBO..",
                "..ODDBBWCWWBBDDO..", "..OOODBCWCCBDOOO..", ".....OBDOODBO.....",
                ".....OBO..OBO.....", ".....ODO..ODO.....", ".....OOO..OOO.....")
        palette = dict(O="#223496", B="#5270e8", D="#3e5ace", L="#7e98ff",
                       W="#6e8cf5", s="#2c346e", S="#161b40", C="#96ebff")
        hop = -5 if self.animations and state == "done" and tick % 8 < 2 else 0
        for rows, offset in ((body, 11), (head, 0)):
            for y, row in enumerate(rows):
                for x, cell in enumerate(row):
                    if cell in palette:
                        self.canvas.create_rectangle(46 + x * 6, 6 + (y + offset) * 6 + hop,
                                                     52 + x * 6, 12 + (y + offset) * 6 + hop,
                                                     fill=palette[cell], outline="")
        face = {"idle": ">_" if tick % 8 < 4 else ">", "starting": "·",
                "thinking": "." * (1 + (tick // 3) % 3), "tool": ">_",
                "waiting": "!", "done": "^ ^", "error": "x x"}[state]
        color = "#e0824f" if state == "waiting" else "#ff8a7a" if state == "error" else "#96ebff"
        self.canvas.create_text(100, 44 + hop, text=face, fill=color, font=("Consolas", 16, "bold"))
        self.finish("codex", state, f"Codex: {LABELS[state].capitalize()}", "")

    def ingest(self, event):
        self.sessions.apply(event)
        if event.state == "end":
            self.monitor.forget(event.session)
            self.marked.discard(event.session)
            clear_mark(ROOT, event.session)
            return
        if event.state == "tool" and self.mission:
            self.mission.record_tool(event.tool)
        # a new baseline when claude starts thinking or comes back from a tool, so its own edits
        # do not count as the project changing underneath it.
        if event.state == "thinking" and event.workspace:
            self.monitor.arm(event.session, event.workspace)
            self.marked.discard(event.session)

    def watch(self, now):
        """ask for project scans every 3 s, then pick the alert for the bubble."""
        entries = self.sessions.entries
        if now >= self.next_scan:
            self.next_scan = now + 3
            for session, (event, _) in entries.items():
                if event.state == "thinking" and event.workspace:
                    self.monitor.check(session, event.workspace)
        changed = [s for s in self.monitor.changed_sessions() if s in entries]
        for session in changed:
            if session not in self.marked and flag_path(ROOT).is_file():
                mark(ROOT, session)
            self.marked.add(session)
        if changed:
            self.raise_alert("El proyecto cambió mientras claude pensaba",
                             "herramientas detenidas hasta nuevo mensaje" if flag_path(ROOT).is_file()
                             else "revisa el diff antes de seguir")
            return
        if self.stall_watch:
            for event, since in entries.values():
                if stalled(event.state, since, self.sessions.clock()):
                    minutes = int((self.sessions.clock() - since) // 60)
                    self.raise_alert("claude parece bloqueado", f"sin actividad desde hace {minutes} min")
                    return
        review = self.review
        if review and review.running:
            self.raise_alert(f"{handoff.NAMES[review.reviewer]} revisa lo de {handoff.NAMES[review.author]}",
                             f"{int(time.monotonic() - review.started)} s · solo lectura", "info")
            return
        if review and review.state in ("done", "failed") and not self.notice_done:
            if review.state == "done":
                open_file(review.result)
            self.notice_done = True
            self.notice = (time.monotonic() + 12, "revisión lista" if review.state == "done"
                           else "revisión fallida", review.error or handoff.NAMES[review.reviewer])
        if self.notice and time.monotonic() < self.notice[0]:
            self.raise_alert(*self.notice[1:], "info" if review.state == "done" else "warn")
            return
        if self.mission and self.mission.collision:
            project = self.mission.local["project"]
            self.raise_alert("claude y codex en el mismo proyecto", project or "revisen quién edita qué")
            return
        self.alert = None

    def raise_alert(self, title, subtitle, tone="warn"):
        self.alert, self.alert_tone = (title, subtitle), tone

    def sync_mission(self, current, peer):
        mission = self.mission
        key = (current.state, current.project, current.workspace, current.session)
        if key != self.last_key:
            self.last_key = key
            mission.record_local(current.state, current.project, current.workspace, current.session)
        if peer:
            mission.record_peer(peer.state, peer.project)
        else:
            mission.peer_left()
        mission.tick()

    def update(self):
        try:
            while True:
                event = self.events.get_nowait()
                if isinstance(event, PeerMessage):
                    self.peers.apply(event)
                else:
                    self.ingest(event)
        except Empty:
            pass
        current = self.sessions.current()
        if self.codex:
            peer = self.peers.current("codex")
            self.codex.peer_event = Event(peer.state, "codex") if peer else None
            if peer and self.codex.window.state() == "withdrawn":
                self.codex.window.deiconify()
            elif not peer and not self.codex.sessions.entries and self.codex.window.state() != "withdrawn":
                self.codex.window.withdraw()
            self.sync_mission(current, peer)
            self.watch(time.monotonic())
        self.draw(self.peer_event if self.peer_event and not self.sessions.entries else current)
        self.tick += 1
        self.window.after(150, self.update)

    def close(self):
        self.save()
        if self.listener is None:
            self.window.master.event_generate("<<PetQuit>>")
            return
        if self.codex:
            self.codex.save()
        self.listener.close()
        self.window.destroy()


if __name__ == "__main__":
    try:
        if sys.argv[1:] == ["--self-test"]:
            with tempfile.TemporaryDirectory() as directory:
                ROOT = Path(directory) / "pet"
                pet = Pet()
                try:
                    for state in PRIORITY:
                        pet.demo(state)
                        pet.codex.demo(state)
                        pet.update()
                        pet.codex.update()
                        pet.window.update()
                finally:
                    pet.close()
        else:
            Pet().window.mainloop()
    except (RuntimeError, OSError) as error:
        if sys.stderr is not None:
            print(str(error), file=sys.stderr)
        else:
            from tkinter import messagebox
            messagebox.showerror("claude-pet", str(error))
        sys.exit(1)
