#!/bin/sh
# Consumo del plan: el hook del statusline escribe el archivo y la app lo lee; avisos, ventanas vencidas y datos viejos.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${1:-$ROOT/build/ClaudePet.app/Contents/MacOS/ClaudePet}"
[ -x "$BIN" ] || BIN="$ROOT/.build/debug/ClaudePet"
T=$(mktemp -d "${TMPDIR:-/tmp}/claudepet-plan.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT INT TERM
fail() { echo "FALLO $1"; exit 1; }
HOOK="$ROOT/hooks/pet-statusline.sh"
IN='{"session_id":"abc","cwd":"/tmp/x","model":{"id":"m"},"rate_limits":{"five_hour":{"used_percentage":42.7,"resets_at":1800007200},"seven_day":{"used_percentage":18,"resets_at":1800400000}}}'
OUT=$(printf '%s' "$IN" | HOME="$T" sh "$HOOK") || fail "el hook sale con error"
[ "$OUT" = "5h 42% · 7d 18%" ] || fail "salida del statusline: $OUT"
[ -f "$T/.claude-pet/usage.json" ] || fail "no escribio usage.json"
grep -q "/tmp/x\|abc" "$T/.claude-pet/usage.json" && fail "usage.json guarda datos del proyecto o la sesion"
# sin rate_limits (cuenta con API key) no escribe nada y no rompe
T2="$T/sin"; mkdir -p "$T2"
printf '%s' '{"session_id":"abc"}' | HOME="$T2" sh "$HOOK" >/dev/null || fail "sin rate_limits sale con error"
[ ! -e "$T2/.claude-pet/usage.json" ] || fail "escribio usage.json sin datos"
# con statusline previo encadenado: lo ejecuta con la misma entrada y conserva su salida
T3="$T/cadena"; mkdir -p "$T3/.claude-pet"
echo "cat >/dev/null; echo mi-statusline" > "$T3/.claude-pet/statusline-chain"
OUT=$(printf '%s' "$IN" | HOME="$T3" sh "$HOOK") || fail "cadena sale con error"
[ "$OUT" = "mi-statusline" ] || fail "cadena: $OUT"
[ -f "$T3/.claude-pet/usage.json" ] || fail "con cadena tambien debe guardar el consumo"
# basura en la entrada
printf 'no es json' | HOME="$T/basura" sh "$HOOK" >/dev/null || fail "basura rompe el hook"
"$BIN" --selftest-plan "$T/.claude-pet/usage.json"
