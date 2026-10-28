#!/bin/sh
json() { printf '%s' "$1" | tr -d '\000-\010\013\014\016-\037' | awk 'BEGIN{ORS=""} {gsub(/\\/,"\\\\"); gsub(/"/,"\\\""); gsub(/\t/,"\\t"); gsub(/\r/,""); if (NR>1) printf "\\n"; printf "%s", $0}'; }
[ -d "${CLAUDE_PET_PROJECT:-}" ] || { printf '{"toast":"no hay un proyecto activo"}\n'; exit 0; }
/usr/bin/open -a Terminal "$CLAUDE_PET_PROJECT" && printf '{"toast":"terminal abierta en %s"}\n' "$(json "${CLAUDE_PET_PROJECT_NAME:-el proyecto}")"
