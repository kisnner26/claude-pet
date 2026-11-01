#!/bin/sh
# Cerebro compartido de claude pet. Siempre sale con 0 si la app no esta instalada: nunca estorba a un agente.
#   pet-brain.sh start          hook SessionStart de Claude Code: imprime las notas del proyecto como contexto
#   pet-brain.sh show <agente>  lo mismo, a mano (para codex)
#   pet-brain.sh add <agente> <decision|hecho|cuidado|pendiente> "nota" [proyecto]
#   pet-brain.sh forget <id> [proyecto]   |   pet-brain.sh list
BIN="${CLAUDE_PET_BIN:-/Applications/ClaudePet.app/Contents/MacOS/ClaudePet}"
[ -x "$BIN" ] || exit 0
if [ "$1" = "start" ]; then
  input=$(head -c 8192 2>/dev/null)
  cwd=$(printf '%s' "$input" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
  [ -n "$cwd" ] && cd "$cwd" 2>/dev/null
  exec "$BIN" --brain show claude
fi
exec "$BIN" --brain "$@"
