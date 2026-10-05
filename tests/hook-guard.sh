#!/bin/sh
# Pruebas del hook: no bloquea por defecto, el bloqueo es opt-in y caduca, y las pruebas se clasifican
# solo por el comando. Usa un HOME temporal: no toca ~/.claude-pet ni ~/.claude.
HOOK="$(cd "$(dirname "$0")/.." && pwd)/hooks/pet-hook.sh"
fail=0
ok() { echo "OK: $1"; }
bad() { echo "FALLO: $1"; fail=1; }

H=$(mktemp -d); export HOME="$H"; mkdir -p "$H/.claude-pet/context-changed"
export CLAUDE_PET_SOCK="$H/none.sock"      # sin app: el hook no debe fallar ni imprimir
PAYLOAD='{"session_id":"guardtst-1","tool_name":"Read","cwd":"/Users/x/p"}'
MARK="$H/.claude-pet/context-changed/guardtst"

: > "$MARK"
out=$(printf '%s' "$PAYLOAD" | sh "$HOOK" PreToolUse)
[ -z "$out" ] && ok "con marca pero SIN la opcion activada: no bloquea ni imprime" || bad "bloqueo sin opt-in: $out"

: > "$H/.claude-pet/block-on-change"
out=$(printf '%s' "$PAYLOAD" | sh "$HOOK" PreToolUse)
printf '%s' "$out" | grep -q '"permissionDecision":"deny"' && ok "con opcion y marca reciente: deniega con el formato documentado" || bad "no deniega: $out"
printf '%s' "$out" | grep -q '"hookEventName":"PreToolUse"' || bad "falta hookEventName"

touch -t 202001010000 "$MARK"
out=$(printf '%s' "$PAYLOAD" | sh "$HOOK" PreToolUse)
[ -z "$out" ] && ok "una marca de mas de 10 min se ignora (no queda bloqueada para siempre)" || bad "marca vieja bloquea: $out"

: > "$MARK"; printf '%s' "$PAYLOAD" | sh "$HOOK" UserPromptSubmit >/dev/null
[ ! -f "$MARK" ] && ok "tu siguiente mensaje borra la marca" || bad "la marca sigue tras UserPromptSubmit"
: > "$MARK"; printf '%s' "$PAYLOAD" | sh "$HOOK" SessionEnd >/dev/null
[ ! -f "$MARK" ] && ok "terminar la sesion borra la marca" || bad "la marca sigue tras SessionEnd"
out=$(printf '%s' "$PAYLOAD" | sh "$HOOK" PostToolUse); [ -z "$out" ] && ok "otros eventos nunca imprimen" || bad "imprime en PostToolUse"

# clasificacion de pruebas con un oyente real
nc_capture() { # evento json -> linea enviada
  d=$(mktemp -d); export CLAUDE_PET_SOCK="$d/s.sock"
  nc -lU "$CLAUDE_PET_SOCK" > "$d/o" & lp=$!; sleep 0.4
  printf '%s' "$2" | sh "$HOOK" "$1"; sleep 0.4; kill $lp 2>/dev/null
  cat "$d/o"; rm -rf "$d"
}
r=$(nc_capture PreToolUse '{"session_id":"abcdef123456","cwd":"/Users/x/p","tool_name":"Edit","tool_input":{"file_path":"/Users/x/p/README.md","new_string":"ejecuta pytest y npm test antes de subir"}}')
printf '%s' "$r" | cut -f3 | grep -qx "Edit" && ok "editar un archivo que menciona pytest NO se marca como prueba" || bad "falsa prueba: $r"
r=$(nc_capture PreToolUse '{"session_id":"abcdef123456","cwd":"/Users/x/p","tool_name":"Bash","tool_input":{"command":"swift test --filter Secreto123"}}')
printf '%s' "$r" | cut -f3 | grep -qx "test" && ok "un comando 'swift test' se marca como prueba" || bad "no detecta swift test: $r"
printf '%s' "$r" | grep -q "Secreto123\|filter" && bad "se filtraron los argumentos del comando" || ok "los argumentos del comando no viajan"
r=$(nc_capture PreToolUse '{"session_id":"abcdef123456","cwd":"/Users/x/p","tool_name":"Bash","tool_input":{"command":"echo hola"}}')
printf '%s' "$r" | cut -f3 | grep -qx "Bash" && ok "un comando normal sigue siendo Bash" || bad "mal clasificado: $r"
r=$(nc_capture PreToolUse "{\"session_id\":\"abcdef123456\",\"cwd\":\"/$(printf 'a%.0s' $(seq 1 1500))\",\"tool_name\":\"Read\"}")
[ "$(printf '%s' "$r" | cut -f8 | wc -c)" -le 1002 ] && ok "una ruta enorme se recorta (no revienta el limite del socket)" || bad "ruta sin recortar"

rm -rf "$H"
exit $fail
