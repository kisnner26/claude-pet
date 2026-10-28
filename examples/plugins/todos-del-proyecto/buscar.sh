#!/bin/sh
# Solo archivos versionados (git grep): nunca node_modules ni lo ignorado.
json() { printf '%s' "$1" | tr -d '\000-\010\013\014\016-\037' | awk 'BEGIN{ORS=""} {gsub(/\\/,"\\\\"); gsub(/"/,"\\\""); gsub(/\t/,"\\t"); gsub(/\r/,""); if (NR>1) printf "\\n"; printf "%s", $0}'; }
say() { printf '{"toast":"%s"}\n' "$(json "$1")"; }
export GIT_OPTIONAL_LOCKS=0
[ -n "${CLAUDE_PET_PROJECT:-}" ] && cd "$CLAUDE_PET_PROJECT" 2>/dev/null || { say "no hay un proyecto activo"; exit 0; }
git rev-parse --git-dir >/dev/null 2>&1 || { say "${CLAUDE_PET_PROJECT_NAME:-el proyecto} no es un repositorio git"; exit 0; }
todo=$(git grep -n -I -w -e TODO -e FIXME -- . ':(exclude)*.lock' ':(exclude)*-lock.json' ':(exclude)*.min.js' 2>/dev/null | cut -c1-170)
if [ -z "$todo" ]; then say "ningún TODO ni FIXME en $CLAUDE_PET_PROJECT_NAME"; exit 0; fi
total=$(printf '%s\n' "$todo" | wc -l | tr -d ' ')
archivos=$(printf '%s\n' "$todo" | cut -d: -f1 | sort -u | wc -l | tr -d ' ')
lista=$(printf '%s\n' "$todo" | head -n 40 | head -c 3000)
printf '{"toast":"%s","copy":"%s"}\n' "$total pendientes en $archivos archivos" "$(json "$lista")"
