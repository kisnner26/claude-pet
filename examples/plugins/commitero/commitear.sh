#!/bin/sh
# Abre commitero con el proyecto activo. claude-pet nos da CLAUDE_PET_PROJECT porque el manifiesto pide el permiso "project".
esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\000-\037'; }
name=$(esc "$CLAUDE_PET_PROJECT_NAME")
if ! command -v commitero >/dev/null 2>&1; then
  printf '{"toast":"commitero no está instalado: npm link en su carpeta"}\n'
  exit 0
fi
git -C "$CLAUDE_PET_PROJECT" rev-parse --git-dir >/dev/null 2>&1 || { printf '{"toast":"%s no es un repositorio git"}\n' "$name"; exit 0; }
nohup commitero "$CLAUDE_PET_PROJECT" >/dev/null 2>&1 &
printf '{"toast":"commitero abierto en %s"}\n' "$name"
