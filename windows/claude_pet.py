"""desktop pet frontend using the tkinter shipped with python for windows."""

import json
import os
from pathlib import Path
from queue import Empty, Queue
import tkinter as tk

from pet_ipc import start_server
from pet_state import Event, PRIORITY, Sessions

ROOT = Path.home() / ".claude-pet"
LABELS = dict(idle="inactivo", starting="iniciando", thinking="pensando",
              tool="ejecutando", waiting="tu aprobación", done="listo", error="error")
TRANSPARENT = "#ff00ff"


class Pet:
    def __init__(self):
        self.events = Queue()
        self.sessions = Sessions()
        self.listener = start_server(ROOT, self.events.put)
        self.window = tk.Tk()
        self.window.title("claude-pet")
        self.window.overrideredirect(True)
        self.window.attributes("-topmost", True)
        self.window.configure(bg=TRANSPARENT)
        if os.name == "nt":
            self.window.attributes("-transparentcolor", TRANSPARENT)
        self.canvas = tk.Canvas(self.window, width=200, height=160,
                                bg=TRANSPARENT, highlightthickness=0)
        self.canvas.pack()
        self.tick = 0
        self.animations = True
        self.drag = None
        self.settings = ROOT / "windows-position.json"
        try:
            position = json.loads(self.settings.read_text(encoding="utf-8"))
            x, y = int(position["x"]), int(position["y"])
            self.animations = bool(position.get("animations", True))
        except (OSError, ValueError, KeyError, TypeError):
            x, y = self.window.winfo_screenwidth() - 220, self.window.winfo_screenheight() - 220
        x = max(0, min(x, self.window.winfo_screenwidth() - 200))
        y = max(0, min(y, self.window.winfo_screenheight() - 160))
        self.window.geometry(f"200x160+{x}+{y}")
        self.canvas.bind("<ButtonPress-1>", self.begin_drag)
        self.canvas.bind("<B1-Motion>", self.move)
        self.canvas.bind("<ButtonRelease-1>", self.save)
        self.canvas.bind("<Button-3>", self.menu)
        self.window.bind("<Escape>", lambda _: self.close())
        self.window.protocol("WM_DELETE_WINDOW", self.close)
        self.update()

    def begin_drag(self, event):
        self.drag = (event.x_root - self.window.winfo_x(),
                     event.y_root - self.window.winfo_y())

    def move(self, event):
        if self.drag:
            self.window.geometry(f"+{max(0, event.x_root - self.drag[0])}"
                                 f"+{max(0, event.y_root - self.drag[1])}")

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
        scale, left, top = 7, 44, 12
        dy = -1 if state == "done" and tick % 8 < 2 else 0
        dx = (1 if tick % 2 else -1) if state == "error" else 0

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
        label = LABELS[state] + (f" · {event.tool}" if event.tool else "")
        self.canvas.create_rectangle(2, 132, 198, 158, fill=ink, outline="")
        self.canvas.create_text(100, 145, text=label, fill="#ede3da", font=("Consolas", 10))

    def update(self):
        try:
            while True:
                self.sessions.apply(self.events.get_nowait())
        except Empty:
            pass
        self.draw(self.sessions.current())
        self.tick += 1
        self.window.after(150, self.update)

    def close(self):
        self.save()
        self.listener.close()
        self.window.destroy()


if __name__ == "__main__":
    Pet().window.mainloop()
