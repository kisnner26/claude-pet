#!/bin/sh
# Permisos desde la isla: protocolo del socket y del hook de extremo a extremo (usa un HOME temporal).
#   tests/permission.sh        ejecuta ClaudePet --selftest-permission con el hook del repositorio
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${1:-$ROOT/build/ClaudePet.app/Contents/MacOS/ClaudePet}"
[ -x "$BIN" ] || BIN="$ROOT/.build/debug/ClaudePet"
exec "$BIN" --selftest-permission "$ROOT/hooks/pet-permission.sh"
