#!/bin/sh
# Aprobar desde otro dispositivo: politica de riesgo, caducidad y el socket real con un cliente de prueba.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${1:-$ROOT/build/ClaudePet.app/Contents/MacOS/ClaudePet}"
[ -x "$BIN" ] || BIN="$ROOT/.build/debug/ClaudePet"
"$BIN" --selftest-remote
