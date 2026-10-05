#!/bin/sh
# Cada mascota aparece segun la herramienta que uses. Simula las apps abiertas en una instancia de prueba
# (no cierra tus apps ni cambia ajustes) y al terminar reabre ClaudePet normal.
#   tests/presence.sh           recorre: solo Claude, solo Codex, ambos, ninguno (~25 s)
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/ClaudePet.app"; BIN="$APP/Contents/MacOS/ClaudePet"
trap 'pkill -x ClaudePet 2>/dev/null; sleep 1; open "$APP"' EXIT INT TERM
run() { # modo texto
  pkill -x ClaudePet 2>/dev/null; sleep 1
  CLAUDE_PET_FAKE_APPS="$1" "$BIN" >/dev/null 2>&1 &
  echo " [$1] $2"; sleep 5
}
echo "Presencia por herramienta (instancia de prueba)"
run claude "solo la mascota de Claude (sin robot azul)"
run codex  "solo el robot azul de Codex, en el sitio de la mascota; se puede arrastrar y un clic abre Codex"
run both   "ambos: Codex a la izquierda de Claude, reaccionan entre si y pueden jugar al futbol"
run none   "ninguno: no se ve nada; solo queda el icono de la barra de menu"
echo "fin: se reabre ClaudePet normal"
