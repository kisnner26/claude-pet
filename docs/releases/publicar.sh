#!/bin/sh
# Crea en GitHub una release por cada etiqueta vX.Y.Z usando las notas de esta carpeta. Requiere `gh` con sesión iniciada.
set -e
cd "$(dirname "$0")/../.."
for v in 0.1.0 0.2.0 0.3.0 1.0.0 1.1.0 1.2.0 2.0.0 2.1.0 2.2.0; do
  latest="--latest=false"; [ "$v" = "2.2.0" ] && latest="--latest"
  gh release view "v$v" >/dev/null 2>&1 && { echo "v$v ya existe"; continue; }
  gh release create "v$v" --title "claude-pet $v" --notes-file "docs/releases/$v.md" --verify-tag $latest
done
