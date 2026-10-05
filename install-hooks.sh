#!/bin/sh
# Instala el script de hooks y (solo con tu confirmacion) fusiona los hooks en ~/.claude/settings.json.
# Uso: ./install-hooks.sh [--dry-run]     |     ./install-hooks.sh --uninstall
set -e
cd "$(dirname "$0")"
DEST="$HOME/.claude-pet"
SETTINGS="$HOME/.claude/settings.json"
TAG="/.claude-pet/pet-hook.sh"

command -v jq >/dev/null || { echo "falta jq (brew install jq)"; exit 1; }

if [ "$1" = "--uninstall" ]; then
  tmp=$(mktemp)
  jq --arg tag "$TAG" '
    if .hooks then
      .hooks |= with_entries(
        .value |= map(.hooks |= map(select(.command | contains($tag) | not))) | .value |= map(select(.hooks | length > 0)))
      | .hooks |= with_entries(select(.value | length > 0))
      | if (.hooks | length) == 0 then del(.hooks) else . end
    else . end' "$SETTINGS" > "$tmp"
  cp "$SETTINGS" "$SETTINGS.bak-claudepet"
  cp "$tmp" "$SETTINGS"; rm "$tmp"
  rm -rf "$DEST/pet-hook.sh"
  echo "hooks quitados. copia previa: $SETTINGS.bak-claudepet"
  exit 0
fi

# fusion: agrega nuestros hooks sin tocar los existentes
merged=$(mktemp)
jq --slurpfile add hooks/settings-snippet.json '
  .hooks = ((.hooks // {}) as $cur
    | reduce ($add[0].hooks | to_entries[]) as $e ($cur; .[$e.key] = ((.[$e.key] // []) + $e.value)))
' "$SETTINGS" > "$merged"

echo "Se modificara UN archivo: $SETTINGS"
echo "Se copiara: hooks/pet-hook.sh -> $DEST/pet-hook.sh"
echo "Diferencia en settings.json:"
diff "$SETTINGS" "$merged" || true
[ "$1" = "--dry-run" ] && { rm "$merged"; echo "(dry-run: nada cambiado)"; exit 0; }

printf "Aplicar? [s/N] "; read -r ans
[ "$ans" = "s" ] || { rm "$merged"; echo "cancelado"; exit 1; }

mkdir -p "$DEST"; chmod 700 "$DEST"
cp hooks/pet-hook.sh "$DEST/pet-hook.sh"; chmod 755 "$DEST/pet-hook.sh"
cp "$SETTINGS" "$SETTINGS.bak-claudepet"
cp "$merged" "$SETTINGS"; rm "$merged"
echo "listo. copia previa: $SETTINGS.bak-claudepet  (abre una sesion nueva de Claude Code)"
