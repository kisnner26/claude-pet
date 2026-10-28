#!/bin/sh
# Los ajustes del manifiesto llegan como CLAUDE_PET_SETTING_<CLAVE>. La respuesta es una linea JSON; "toast" necesita el permiso notify.
# Todo lo que no controlas (aqui, el nombre que escribe el usuario) se escapa antes de meterlo en el JSON.
esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\000-\037'; }
msg="hola, ${CLAUDE_PET_SETTING_NOMBRE:-mundo}"
[ "$CLAUDE_PET_SETTING_GRITO" = "true" ] && msg=$(printf '%s' "$msg" | tr '[:lower:]' '[:upper:]')
printf '{"toast":"%s"}\n' "$(esc "$msg")"
