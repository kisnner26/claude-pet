#!/bin/sh
# Pruebas del partido de futbol (solo visual, local; no cambia el protocolo del bus).
#   tests/football.sh logic     reglas (reloj falso): inicio, cancelaciones, cooldown, reducir movimiento
#   tests/football.sh normal    un partido completo en pantalla
#   tests/football.sh cancel    cancelacion al instante por Claude y por el par
#   tests/football.sh reduced   mismo partido con "reducir movimiento"
#   tests/football.sh trigger   dispara las animaciones al instante en la app abierta (sin Codex)
#   tests/football.sh           todo en orden
#
# Las pruebas visuales relanzan la app como instancia de prueba con atajos SOLO para este proceso
# (espera 3 s en vez de 8; cooldown 5 s en vez de 300). No tocan hooks, sockets ni ajustes globales.
# Al terminar se vuelve a abrir la app normal.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/ClaudePet.app"
BIN="$APP/Contents/MacOS/ClaudePet"
SEND="$ROOT/bus/pet-bus-send.sh"
HOOK="$ROOT/tests/manual.sh"
PIDS=""

cleanup() {
  for p in $PIDS; do kill "$p" 2>/dev/null; done
  pkill -x ClaudePet 2>/dev/null; sleep 1
  open "$APP"
}
[ "$1" = "trigger" ] || trap cleanup EXIT INT TERM

start_app() { # [VAR=valor ...]
  pkill -x ClaudePet 2>/dev/null; sleep 1
  env CLAUDE_PET_FOOTBALL_IDLE_SECONDS=3 CLAUDE_PET_FOOTBALL_COOLDOWN=5 "$@" "$BIN" >/dev/null 2>&1 &
  PIDS="$PIDS $!"; sleep 2
  "$HOOK" idle >/dev/null
}
codex_idle() { "$SEND" --hold codex idle >/dev/null 2>&1 & HOLD=$!; PIDS="$PIDS $HOLD"; }
codex_gone() { kill "$HOLD" 2>/dev/null; sleep 1; }

t_logic() {
  echo "[logic] reglas con reloj falso"
  "$BIN" --selftest-football || { echo "FALLO"; exit 1; }
}

t_normal() {
  echo "[normal] mira la mascota: el partido ocurre en un escenario transparente a su lado"
  start_app; codex_idle
  echo " 0 s   Codex aparece: mini en la esquina de la mascota y saludo con el brazo izquierdo"
  sleep 6
  echo " ~3 s  empieza el partido: el avatar de Codex (cuerpo crema) ENTRA CAMINANDO por la izquierda y aparece la pelota"
  echo " ~4.6 s Codex levanta la pierna, sale polvo y la pelota vuela en arco grande con estela y sombra hasta la cabeza de Claude"
  echo " ~6 s  destello naranja al tocar la cabeza, Claude cabecea (salta) y la devuelve; Codex salta al recibirla"
  echo " ~10 s segunda vuelta igual"
  echo " ~13 s celebracion: Claude levanta brazos y salta, Codex salta, confeti cae por toda la escena"
  sleep 14
  echo " ~15 s el escenario desaparece; el mini vuelve a la esquina (no repite hasta pasado el cooldown)"
 codex_gone
}

t_cancel() {
  echo "[cancel] cancelacion inmediata"
  start_app; codex_idle
  sleep 5
  echo " ~5 s  partido en curso (pelota en el aire)"
  "$HOOK" thinking >/dev/null
  echo " ahora Claude pasa a 'thinking': la pelota debe desaparecer AL INSTANTE y aparecer los 3 puntos"
  sleep 3
  "$HOOK" idle >/dev/null
  echo " Claude vuelve a idle: tras ~3 s de inactividad compartida y pasado el cooldown (5 s) empieza otro"
  sleep 7
  echo " ~7 s  segundo partido en curso"
  codex_gone
  "$SEND" codex waiting waiting >/dev/null
  echo " ahora el par pasa a 'waiting': la pelota debe desaparecer al instante y el mini parpadear en terracota"
  sleep 3
  "$SEND" codex idle left >/dev/null
}

t_reduced() {
  echo "[reduced] reducir movimiento (forzado solo para este proceso)"
  start_app CLAUDE_PET_REDUCE_MOTION=1; codex_idle
  sleep 5
  echo " ~3 s  el avatar de Codex y la pelota APARECEN CON UN FUNDIDO, quietos (sin caminar, sin arco, sin patada, sin saltos)"
  sleep 5
  echo " ~8 s  aparece confeti fijo con fundido; nada se mueve"
  sleep 5
  echo " ~13 s todo se desvanece"
  codex_gone
}

t_trigger() {
  echo "[trigger] con la app abierta; cada disparo es inmediato, sin Codex presente"
  for n in greet cheer concern football; do
    "$BIN" --trigger "$n"; echo " --trigger $n"; sleep 4
  done
  echo " (football dura 12 s; el resto 3 s)"; sleep 9
}

case "$1" in
  trigger) t_trigger ;;
  logic) t_logic ;;
  normal) t_normal ;;
  cancel) t_cancel ;;
  reduced) t_reduced ;;
  "") t_logic; t_normal; t_cancel; t_reduced ;;
  *) echo "uso: $0 [logic|normal|cancel|reduced]"; exit 1 ;;
esac
