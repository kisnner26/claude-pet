#!/bin/sh
# Plugins: seguridad y ciclo de vida con scripts reales, y los ejemplos del repositorio de extremo a extremo.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${1:-$ROOT/build/ClaudePet.app/Contents/MacOS/ClaudePet}"
[ -x "$BIN" ] || BIN="$ROOT/.build/debug/ClaudePet"
HOME_TMP=$(mktemp -d "${TMPDIR:-/tmp}/claudepet-plugins.XXXXXX") || exit 1
trap 'rm -rf "$HOME_TMP"' EXIT INT TERM
HOME="$HOME_TMP" "$BIN" --selftest-plugins || exit 1
HOME="$HOME_TMP" "$BIN" --selftest-plugin-examples "$ROOT/examples/plugins"
