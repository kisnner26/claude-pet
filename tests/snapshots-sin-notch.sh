#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BIN=${1:-"$ROOT/.build/debug/ClaudePet"}
OUT=${2:-"$ROOT/docs/img/sin-notch"}
mkdir -p "$OUT"
"$BIN" --snapshot-island "$OUT/isla-1x.png"
CLAUDE_PET_SNAPSHOT_SCALE=2 "$BIN" --snapshot-island "$OUT/isla-2x.png"
printf '%s\n' "snapshots sin notch generados en $OUT"
