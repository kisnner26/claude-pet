#!/bin/sh
# Instala el script de hooks y (solo con tu confirmacion) fusiona los hooks en ~/.claude/settings.json.
# Uso: ./install-hooks.sh [--dry-run]     |     ./install-hooks.sh --uninstall
set -e
cd "$(dirname "$0")"
DEST="$HOME/.claude-pet"
SETTINGS="$HOME/.claude/settings.json"
TAG="/.claude-pet/pet-"       # pet-hook.sh, pet-permission.sh y pet-question.sh

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
  # statusline: se quita el nuestro y se devuelve el que tenias (guardado en statusline-chain)
  if jq -e '(.statusLine.command // "") | contains("/.claude-pet/pet-statusline.sh")' "$tmp" >/dev/null 2>&1; then
    prev=$(head -n 1 "$DEST/statusline-chain" 2>/dev/null || true)
    if [ -n "$prev" ]; then jq --arg c "$prev" '.statusLine = {type: "command", command: $c}' "$tmp" > "$tmp.2"; else jq 'del(.statusLine)' "$tmp" > "$tmp.2"; fi
    mv "$tmp.2" "$tmp"
  fi
  cp "$SETTINGS" "$SETTINGS.bak-claudepet"
  cp "$tmp" "$SETTINGS"; rm "$tmp"
  rm -f "$DEST/pet-statusline.sh" "$DEST/statusline-chain" "$DEST/usage.json"
  rm -rf "$DEST/pet-hook.sh" "$DEST/pet-permission.sh" "$DEST/pet-question.sh" "$DEST/island-permissions"
  echo "hooks quitados. copia previa: $SETTINGS.bak-claudepet"
  exit 0
fi

# fusion idempotente: agrega solo los hooks cuyo comando aun no esta en ese evento y no toca los existentes
merged=$(mktemp)
jq --slurpfile add hooks/settings-snippet.json '
  .hooks = ((.hooks // {}) as $cur
    | reduce ($add[0].hooks | to_entries[]) as $e ($cur;
        .[$e.key] as $have
        | ([($have // [])[].hooks[]?.command]) as $cmds
        | .[$e.key] = (($have // []) + [$e.value[] | select(.hooks | all(.command as $c | $cmds | index($c) | not))])))
' "$SETTINGS" > "$merged"

# consumo del plan: el statusline de Claude Code entrega los limites de 5 horas y semanal. Si ya tenias uno, se encadena.
STATUS_CMD='$HOME/.claude-pet/pet-statusline.sh'
prev_status=$(jq -r '.statusLine.command // empty' "$merged")
case "$prev_status" in
  *"/.claude-pet/pet-statusline.sh"*) CHAIN="" ;;
  "") CHAIN=""; jq --arg c "$STATUS_CMD" '.statusLine = {type: "command", command: $c}' "$merged" > "$merged.2" && mv "$merged.2" "$merged" ;;
  *) CHAIN="$prev_status"; jq --arg c "$STATUS_CMD" '.statusLine = {type: "command", command: $c}' "$merged" > "$merged.2" && mv "$merged.2" "$merged"
     echo "Ya tienes un statusline; se conservara y se ejecutara a traves del de claude pet: $CHAIN" ;;
esac

echo "Se modificara UN archivo: $SETTINGS"
echo "Se copiara: hooks/pet-hook.sh, hooks/pet-permission.sh y hooks/pet-question.sh y hooks/pet-statusline.sh -> $DEST/"
echo "Diferencia en settings.json:"
diff "$SETTINGS" "$merged" || true
[ "$1" = "--dry-run" ] && { rm "$merged"; echo "(dry-run: nada cambiado)"; exit 0; }

printf "Aplicar? [s/N] "; read -r ans
[ "$ans" = "s" ] || { rm "$merged"; echo "cancelado"; exit 1; }

mkdir -p "$DEST"; chmod 700 "$DEST"
cp hooks/pet-hook.sh "$DEST/pet-hook.sh"; chmod 755 "$DEST/pet-hook.sh"
cp hooks/pet-permission.sh "$DEST/pet-permission.sh"; chmod 755 "$DEST/pet-permission.sh"
cp hooks/pet-question.sh "$DEST/pet-question.sh"; chmod 755 "$DEST/pet-question.sh"
cp hooks/pet-statusline.sh "$DEST/pet-statusline.sh"; chmod 755 "$DEST/pet-statusline.sh"
[ -n "$CHAIN" ] && { ( umask 077; printf '%s\n' "$CHAIN" > "$DEST/statusline-chain" ); }
cp "$SETTINGS" "$SETTINGS.bak-claudepet"
cp "$merged" "$SETTINGS"; rm "$merged"
echo "listo. copia previa: $SETTINGS.bak-claudepet  (abre una sesion nueva de Claude Code)"
