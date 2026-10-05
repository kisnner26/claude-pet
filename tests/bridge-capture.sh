#!/bin/sh
# Verifica que el hook reenvia solo lo previsto y nunca rutas, contenido de archivos ni argumentos de comandos.
# No necesita la app: levanta un oyente temporal propio.
HOOK="$(cd "$(dirname "$0")/.." && pwd)/hooks/pet-hook.sh"
fail=0
run() { # evento json
  DIR=$(mktemp -d); export CLAUDE_PET_SOCK="$DIR/t.sock"
  nc -lU "$CLAUDE_PET_SOCK" > "$DIR/out" & LP=$!; sleep 0.4
  printf '%s' "$2" | "$HOOK" "$1"; sleep 0.4; kill $LP 2>/dev/null
  OUT=$(cat "$DIR/out"); rm -rf "$DIR"
}
check() { # descripcion patron-que-NO-debe-estar
  if printf '%s' "$OUT" | grep -q -e "$2"; then echo "FALLO ($1): aparece '$2'"; fail=1; else echo "OK: $1"; fi
}
run PreToolUse '{"session_id":"abcdef123456","prompt":"SECRETO-PROMPT","tool_name":"Edit","tool_input":{"file_path":"/ruta/privada/main.swift","new_string":"SECRETO-CONTENIDO"}}'
check "Edit: ni ruta ni contenido ni prompt" "privada\|SECRETO"
printf '%s' "$OUT" | grep -q "main.swift" && echo "OK: si viaja el nombre del archivo" || { echo "FALLO: falta el nombre del archivo"; fail=1; }
run PermissionRequest '{"session_id":"abcdef123456","tool_name":"Bash","tool_input":{"command":"curl -H \"Authorization: Bearer SECRETO-TOKEN\" https://x.io"}}'
check "Bash sin descripcion: solo el programa, sin argumentos" "SECRETO\|Bearer"
run Stop '{"session_id":"abcdef123456","prompt":"SECRETO-PROMPT"}'
check "Stop: el mensaje solo se toma en UserPromptSubmit" "SECRETO"
exit $fail
