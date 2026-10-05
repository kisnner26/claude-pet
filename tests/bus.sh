#!/bin/sh
# Pruebas del pet bus. Requiere la app abierta.
#  1. Simula a Codex enviando presencia: la mascota debe saludar y mostrar un mini companero.
#  2. Comprueba que Claude publica su estado a un par que escucha (socket temporal "codex-test").
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SEND="$ROOT/bus/pet-bus-send.sh"
BUS="$HOME/.claude-pet/bus"

echo "[1] Codex simulado (mira la mascota)"
"$SEND" codex idle appeared;    echo " appeared: saluda con la oreja izquierda y aparece el mini en la esquina sup. izquierda"; sleep 4
"$SEND" codex thinking working; echo " working: el mini muestra un punto que se desplaza"; sleep 3
"$SEND" codex waiting waiting;  echo " waiting: el mini parpadea en terracota"; sleep 3
"$SEND" codex done finished;    echo " finished: destellos de celebracion"; sleep 3
"$SEND" codex error error;      echo " error: el mini parpadea oscuro con una marca de preocupacion"; sleep 3
"$SEND" codex idle left;        echo " left: el mini desaparece"; sleep 1

echo "[2] Tolerancia a mensajes invalidos (no debe pasar nada ni caerse la app)"
for bad in 'basura' '{"v":2,"id":"codex","state":"idle","ts":1}' '{"v":1,"id":"CLAUDE","state":"idle","ts":1}' '{"v":1,"id":"codex","state":"inventado","ts":1,"extra":[1,2]}'; do
  printf '%s\n' "$bad" | nc -U -w 1 "$BUS/claude.sock" >/dev/null 2>&1
done
sleep 1; pgrep -x ClaudePet >/dev/null && echo " OK: la app sigue viva (el ultimo mensaje es valido con estado desconocido: mini sin estado)"
"$SEND" codex idle left; sleep 1

echo "[3] Claude publica a un par que escucha"
SOCK="$BUS/codex-test.sock"; OUT=$(mktemp)
rm -f "$SOCK"; nc -lU "$SOCK" > "$OUT" & LP=$!; sleep 0.5
"$ROOT/tests/manual.sh" thinking >/dev/null
sleep 1; kill $LP 2>/dev/null; rm -f "$SOCK"
echo " recibido: $(cat "$OUT")"
grep -q '"id":"claude"' "$OUT" && grep -q '"state":"thinking"' "$OUT" && echo " OK" || echo " FALLO"
grep -q project "$OUT" && echo " FALLO: el proyecto salio sin activar 'Compartir nombre del proyecto'" || echo " OK: sin nombre de proyecto por defecto"
rm -f "$OUT"
