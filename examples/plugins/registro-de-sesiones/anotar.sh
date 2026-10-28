#!/bin/sh
# Los eventos llegan por la entrada estandar como JSON y en CLAUDE_PET_EVENT. Lo propio se guarda en CLAUDE_PET_DATA_DIR.
payload=$(cat)
printf '%s\t%s\n' "$CLAUDE_PET_EVENT" "$payload" >> "$CLAUDE_PET_DATA_DIR/sesiones.log"
