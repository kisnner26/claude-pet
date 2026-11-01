#!/bin/sh
# Conecta el cerebro compartido: hook SessionStart en ~/.claude/settings.json (claude) y un bloque marcado en ~/.codex/AGENTS.md (codex).
# Uso: ./install-brain.sh [--dry-run] [--yes]     |     ./install-brain.sh --uninstall
set -e
cd "$(dirname "$0")"
DEST="$HOME/.claude-pet"
SETTINGS="$HOME/.claude/settings.json"
CODEX="$HOME/.codex/AGENTS.md"
TAG="/.claude-pet/pet-brain.sh"
START="<!-- claude-pet-brain:start -->"; END="<!-- claude-pet-brain:end -->"

command -v jq >/dev/null || { echo "falta jq (brew install jq)"; exit 1; }

strip_block() { awk -v s="$START" -v e="$END" '$0==s{skip=1} !skip{print} $0==e{skip=0}' "$1"; }

if [ "$1" = "--uninstall" ]; then
  if [ -f "$SETTINGS" ]; then
    tmp=$(mktemp)
    jq --arg tag "$TAG" '
      if .hooks then .hooks |= with_entries(.value |= map(.hooks |= map(select(.command | contains($tag) | not))) | .value |= map(select(.hooks | length > 0)))
        | .hooks |= with_entries(select(.value | length > 0)) | if (.hooks | length) == 0 then del(.hooks) else . end else . end' "$SETTINGS" > "$tmp"
    cp "$SETTINGS" "$SETTINGS.bak-claudepet-brain"; cp "$tmp" "$SETTINGS"; rm "$tmp"
  fi
  if [ -f "$CODEX" ]; then cp "$CODEX" "$CODEX.bak-claudepet-brain"; strip_block "$CODEX" > "$CODEX.tmp" && mv "$CODEX.tmp" "$CODEX"; fi
  rm -f "$DEST/pet-brain.sh"
  echo "cerebro desconectado (las notas en $DEST/brain se conservan). copias: *.bak-claudepet-brain"
  exit 0
fi

[ -f "$SETTINGS" ] || { mkdir -p "$(dirname "$SETTINGS")"; echo '{}' > "$SETTINGS"; }
merged=$(mktemp)
jq --slurpfile add hooks/brain-snippet.json '
  .hooks = ((.hooks // {}) as $cur
    | reduce ($add[0].hooks | to_entries[]) as $e ($cur;
        .[$e.key] as $have
        | ([($have // [])[].hooks[]?.command]) as $cmds
        | .[$e.key] = (($have // []) + [$e.value[] | select(.hooks | all(.command as $c | $cmds | index($c) | not))])))
' "$SETTINGS" > "$merged"

block=$(mktemp)
cat > "$block" <<BLOCK
$START
## cerebro de claude pet
- al empezar una tarea en un repo, corre \`~/.claude-pet/pet-brain.sh show codex\` y úsalo como pistas: verifica antes de actuar.
- al terminar algo que la próxima sesión deba saber (una decisión, un cuidado, un pendiente), guarda una nota corta: \`~/.claude-pet/pet-brain.sh add codex <decision|hecho|cuidado|pendiente> "nota"\`. nunca claves, tokens ni contenido de archivos.
$END
BLOCK

echo "Se modificaran: $SETTINGS (hook SessionStart) y $CODEX (bloque entre marcas)."
echo "Se copiara hooks/pet-brain.sh -> $DEST/"
echo "Diferencia en settings.json:"; diff "$SETTINGS" "$merged" || true
echo "Bloque para codex:"; cat "$block"
[ "$1" = "--dry-run" ] && { rm "$merged" "$block"; echo "(dry-run: nada cambiado)"; exit 0; }
if [ "$1" != "--yes" ]; then printf "Aplicar? [s/N] "; read -r ans; [ "$ans" = "s" ] || { rm "$merged" "$block"; echo "cancelado"; exit 1; }; fi

mkdir -p "$DEST"; chmod 700 "$DEST"
cp hooks/pet-brain.sh "$DEST/pet-brain.sh"; chmod 755 "$DEST/pet-brain.sh"
cp "$SETTINGS" "$SETTINGS.bak-claudepet-brain"; cp "$merged" "$SETTINGS"; rm "$merged"
mkdir -p "$(dirname "$CODEX")"; [ -f "$CODEX" ] || : > "$CODEX"
cp "$CODEX" "$CODEX.bak-claudepet-brain"
{ strip_block "$CODEX"; printf '\n'; cat "$block"; } > "$CODEX.tmp" && mv "$CODEX.tmp" "$CODEX"; rm "$block"
echo "listo. abre una sesion nueva de claude code; codex lo lee en su proxima tarea. copias: *.bak-claudepet-brain"
