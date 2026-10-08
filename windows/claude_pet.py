"""desktop pet frontend using the tkinter shipped with python for windows."""

import json
import os
import sys
import tempfile
from pathlib import Path
from queue import Empty, Queue
import tkinter as tk

from pet_ipc import start_server
from pet_state import Event, PRIORITY, Sessions
from pet_bus import PeerMessage, Peers
from bubble import LABELS, describe
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
                    animations=self.animations)
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
        menu.add_command(label="pausar animación" if self.animations else "activar animación",
                         command=self.toggle_animation)
        menu.add_separator()
        menu.add_command(label="salir", command=self.close)
        try:
            menu.tk_popup(event.x_root, event.y_root)
        finally:
            menu.grab_release()

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

    def update(self):
        try:
            while True:
                event = self.events.get_nowait()
                if isinstance(event, PeerMessage):
                    self.peers.apply(event)
                else:
                    self.sessions.apply(event)
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
