#!/bin/sh
# Codex como companero fijo junto a Claude. Con ClaudePet.app abierto y SIN una conversacion real de Codex activa.
#   tests/companion.sh          recorre los estados de Codex y luego los de Claude (~55 s)
#   tests/companion.sh logic    solo las pruebas automaticas (no toca la app)
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SEND="$ROOT/bus/pet-bus-send.sh"
HOOK="$ROOT/tests/manual.sh"
BIN="$ROOT/build/ClaudePet.app/Contents/MacOS/ClaudePet"

if [ "$1" = "logic" ]; then "$BIN" --selftest-companion; exit $?; fi

say() { echo " $1"; }
cx() { "$SEND" codex "$@" >/dev/null; }          # estado [evento]
cleanup() { cx idle left; "$HOOK" idle >/dev/null 2>&1; }
trap cleanup EXIT INT TERM

echo "[1] Codex (simulado): mira a la izquierda de la mascota de Claude"
cx idle appeared
say "0 s    aparece el robot azul de Codex junto a Claude y Claude levanta el brazo para saludar; cursor parpadeando"; sleep 4
cx thinking working
say "4 s    PENSANDO: puntos en el visor, vaiven suave; Claude lo mira (los ojos se desplazan hacia el)"; sleep 4
cx tool working
say "8 s    HERRAMIENTA: teclea (>_ con cursor en movimiento), rebota y alterna las patas"; sleep 4
cx waiting waiting
say "12 s   APROBACION: signo '!' naranja en el visor y saltito periodico"; sleep 4
cx done finished
say "16 s   TERMINADO: cara feliz (^ ^) y salta; Claude levanta el brazo (choque de manos)"; sleep 4
cx error error
say "20 s   ERROR: visor con x x en coral y Codex tiembla"; sleep 4
cx idle

echo "[2] Claude trabaja con Codex en reposo (hooks simulados, mismo canal que Claude Code)"
"$HOOK" thinking >/dev/null
say "24 s   Claude PIENSA: sobre Codex aparecen tres puntitos (te esta mirando)"; sleep 4
"$HOOK" waiting >/dev/null
say "28 s   Claude ESPERA TU APROBACION: sobre Codex aparece un '!'"; sleep 4
"$HOOK" error >/dev/null
say "32 s   Claude FALLA: sobre Codex aparece un '?'"; sleep 4
"$HOOK" done >/dev/null
say "36 s   Claude TERMINA: Codex pone cara feliz, un check sobre la cabeza y salta (aplaude)"; sleep 5

echo "[3] Clic"
say "40 s   haz clic sobre el robot azul: debe abrir la app de Codex (el cursor muestra 'Abrir Codex'). Clic en Claude abre Claude."
sleep 8
echo "[4] Reducir movimiento: activalo en Ajustes del Sistema > Accesibilidad > Pantalla y repite: mismas caras, sin saltos, vaiven ni paseo."
echo "fin: Codex se retira (left) y desaparece del lado de Claude"
