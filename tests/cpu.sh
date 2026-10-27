#!/bin/sh
set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BIN="$ROOT/.build/debug/ClaudePet"
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
sleep 1

sum=0
count=0
for _ in $(jot 30 2>/dev/null || seq 30); do
  value=$(ps -p "$PID" -o %cpu= 2>/dev/null | tr -d ' ')
  case "$value" in ''|*[!0-9.]* ) ;; *) sum=$(awk -v a="$sum" -v b="$value" 'BEGIN { print a+b }'); count=$((count + 1));; esac
  sleep 1
done

if [ "$count" -gt 0 ]; then
  awk -v sum="$sum" -v count="$count" 'BEGIN { printf "cpu medio durante %d s: %.2f%%\n", count, sum/count }'
else
  echo "cpu medio: sin muestras"
fi
exit 0
