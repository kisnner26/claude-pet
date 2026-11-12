#!/bin/sh
# Cerebro compartido de claude pet. Siempre sale con 0 si la app no esta instalada: nunca estorba a un agente.
#   pet-brain.sh start          hook SessionStart de Claude Code: imprime las notas del proyecto como contexto
#   pet-brain.sh show <agente>  lo mismo, a mano (para codex)
#   pet-brain.sh add <agente> <decision|hecho|cuidado|pendiente> "nota" [proyecto]
#   pet-brain.sh forget <id> [proyecto]   |   pet-brain.sh list
BIN="${CLAUDE_PET_BIN:-/Applications/ClaudePet.app/Contents/MacOS/ClaudePet}"
[ -x "$BIN" ] || exit 0
if [ "$1" = "start" ]; then
  # Mismo criterio que pet-hook.sh: con jq se lee el payload completo (hasta 1 MiB) y solo el "cwd" de primer nivel,
  # sin confundirlo con claves anidadas ni con comillas escapadas; sin jq, o si jq falla, sed sobre los primeros 8 KB.
  full=$(head -c 1048577 2>/dev/null)
  cwd=""; jqok=""
  if command -v jq >/dev/null 2>&1; then
    if cwd=$(printf '%s' "$full" | jq -r 'if type == "object" and (.cwd | type) == "string" then .cwd else "" end' 2>/dev/null); then jqok=1; else cwd=""; fi
  fi
  if [ -z "$jqok" ]; then
    cwd=$(printf '%s' "$full" | head -c 8192 | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
  fi
  [ -n "$cwd" ] && cd "$cwd" 2>/dev/null
  # falla abierto: si la app da error, no se imprime nada y se sale con 0
  out=$("$BIN" --brain show claude 2>/dev/null) && [ -n "$out" ] && printf '%s\n' "$out"
  exit 0
fi
exec "$BIN" --brain "$@"
