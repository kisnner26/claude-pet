#!/bin/sh
# Cerebro compartido de claude pet. Siempre sale con 0 si la app no esta instalada: nunca estorba a un agente.
#   pet-brain.sh start          hook SessionStart de Claude Code: imprime las notas del proyecto como contexto
#   pet-brain.sh recall         hook UserPromptSubmit: notas relevantes al mensaje (solo con la recuperacion inteligente activa)
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
if [ "$1" = "recall" ]; then
  # Hook UserPromptSubmit: devuelve notas relevantes al mensaje como contexto adicional (hookSpecificOutput.additionalContext).
  # Falla abierto: sin jq, sin mensaje, con el interruptor apagado (por defecto) o ante cualquier error no imprime nada y sale con 0.
  command -v jq >/dev/null 2>&1 || exit 0
  full=$(head -c 1048577 2>/dev/null)
  SEP=$(printf '\037')
  parsed=$(printf '%s' "$full" | jq -r 'if type == "object" then ((.cwd | if type == "string" then . else "" end) + "\u001f" + ((.prompt | if type == "string" then . else "" end) | .[0:800])) else "" end' 2>/dev/null) || exit 0
  cwd=${parsed%%"$SEP"*}; prompt=${parsed#*"$SEP"}
  [ -n "$prompt" ] || exit 0
  [ -n "$cwd" ] && cd "$cwd" 2>/dev/null
  out=$("$BIN" --brain recall --hook -- "$prompt" 2>/dev/null) || exit 0
  [ -n "$out" ] || exit 0
  printf '%s' "$out" | jq -Rs '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: .}}' 2>/dev/null
  exit 0
fi
exec "$BIN" --brain "$@"
