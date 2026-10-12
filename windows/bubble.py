"""text for the activity bubble; the same wording as PetStore.describe on macos."""

LABELS = dict(idle="inactivo", starting="iniciando", thinking="pensando",
              tool="ejecutando", waiting="tu aprobación", done="listo", error="error")


def action(tool, detail, task):
    if tool == "Bash":
        if detail.startswith("$ "):
            return "Ejecutando " + detail[2:]
        return detail or "Ejecutando un comando"
    if tool == "test":
        if detail.startswith("$ "):
            return f"Ejecutando pruebas ({detail[2:]})"
        return detail or "Ejecutando pruebas"
    simple = {"Read": ("Leyendo un archivo", "Leyendo "),
              "Edit": ("Editando un archivo", "Editando "),
              "MultiEdit": ("Editando un archivo", "Editando "),
              "Write": ("Escribiendo un archivo", "Escribiendo "),
              "NotebookEdit": ("Editando un notebook", "Editando "),
              "WebFetch": ("Consultando una página", "Consultando "),
              "WebSearch": ("Buscando en la web", "Buscando en la web: "),
              "Task": ("Delegando a un subagente", "Subagente: "),
              "Agent": ("Delegando a un subagente", "Subagente: ")}
    if tool in simple:
        empty, prefix = simple[tool]
        return prefix + detail if detail else empty
    if tool == "Grep":
        return f"Buscando «{detail}»" if detail else "Buscando en el código"
    if tool == "Glob":
        return f"Buscando archivos «{detail}»" if detail else "Buscando archivos"
    if tool in ("TodoWrite", "TaskUpdate", "TaskCreate"):
        return task or "Actualizando tareas"
    if tool == "":
        return task or "Trabajando"
    if tool.startswith("mcp__"):
        parts = tool.split("__")
        name = parts[2] if len(parts) > 2 else tool
        return f"{name}: {detail}" if detail else "Usando " + name
    return f"{tool}: {detail}" if detail else tool


def describe(state, tool="", detail="", task=""):
    """return (title, subtitle) for the bubble."""
    if state == "starting":
        return "Iniciando sesión", ""
    if state == "thinking":
        return (task or "Pensando"), ("Pensando" if task else "")
    if state == "tool":
        return action(tool, detail, task), task
    if state == "waiting":
        return action(tool, detail, task), "Esperando tu aprobación"
    if state == "done":
        return (task or "Terminó"), "Terminó"
    if state == "error":
        return (task or "Algo falló"), "Algo falló"
    return "", ""
