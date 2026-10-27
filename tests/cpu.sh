#!/bin/sh
set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BIN=${1:-"$ROOT/.build/debug/ClaudePet"}
TMP_HOME=$(mktemp -d "${TMPDIR:-/tmp}/claudepet-cpu.XXXXXX") || exit 1
PID=""
cleanup() {
  if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then kill "$PID" 2>/dev/null || true; wait "$PID" 2>/dev/null || true; fi
  rm -rf "$TMP_HOME"
}
trap cleanup EXIT INT TERM

[ -x "$BIN" ] || { echo "compila primero con swift build" >&2; exit 1; }
HOME="$TMP_HOME" "$BIN" --cpu-island-hidden >/dev/null 2>&1 &
PID=$!
# El %cpu de ps es un promedio que arrastra el arranque (la app es de debug y cargar la interfaz pesa). Para medir el
# reposo de verdad se deja pasar un calentamiento y se mide el tiempo de cpu consumido entre dos instantes.
WARMUP=${CPU_WARMUP:-10}
WINDOW=${CPU_WINDOW:-20}
cpu_seconds() {
  ps -p "$PID" -o cputime= 2>/dev/null | tr -d ' ' | awk -F: '{ t=0; for (i=1; i<=NF; i++) t = t*60 + $i; printf "%.3f", t }'
}
sleep "$WARMUP"
start=$(cpu_seconds)
[ -n "$start" ] || { echo "cpu medio: sin muestras"; exit 1; }
sleep "$WINDOW"
end=$(cpu_seconds)
[ -n "$end" ] || { echo "cpu medio: sin muestras"; exit 1; }
awk -v a="$start" -v b="$end" -v w="$WINDOW" 'BEGIN { avg = (b - a) / w * 100; printf "cpu medio en reposo durante %d s (tras %d s de arranque): %.2f%%\n", w, '"$WARMUP"', avg; exit(avg > 5 ? 1 : 0) }'
