#!/bin/sh
# Solo nombres de directorios y conteos: nunca el contenido de ningun archivo.
json() { printf '%s' "$1" | tr -d '\000-\010\013\014\016-\037' | awk 'BEGIN{ORS=""} {gsub(/\\/,"\\\\"); gsub(/"/,"\\\""); gsub(/\t/,"\\t"); gsub(/\r/,""); if (NR>1) printf "\\n"; printf "%s", $0}'; }
say() { printf '{"toast":"%s"}\n' "$(json "$1")"; }
export GIT_OPTIONAL_LOCKS=0
[ -n "${CLAUDE_PET_PROJECT:-}" ] && cd "$CLAUDE_PET_PROJECT" 2>/dev/null || { say "no hay un proyecto activo"; exit 0; }
git rev-parse --git-dir >/dev/null 2>&1 || { say "${CLAUDE_PET_PROJECT_NAME:-el proyecto} no es un repositorio git"; exit 0; }
rama=$(git symbolic-ref --short -q HEAD || git rev-parse --short HEAD)
cambios=$(git status --porcelain | wc -l | tr -d ' ')
commits=$(git log -n 5 --format='- %h %s' 2>/dev/null | cut -c1-120)
estructura=$(git ls-files | awk -F/ '{ k = (NF > 1) ? $1 "/" : "(raíz)"; c[k]++ } END { for (k in c) printf "%d\t%s\n", c[k], k }' | sort -rn | head -n 10 | awk -F'\t' '{ printf "- %s: %s archivos\n", $2, $1 }')
total=$(git ls-files | wc -l | tr -d ' ')
texto="# proyecto: ${CLAUDE_PET_PROJECT_NAME:-?}
rama: $rama · cambios sin commit: $cambios · archivos versionados: $total

## últimos commits
${commits:-- (sin commits)}

## estructura
$estructura"
texto=$(printf '%s' "$texto" | head -c 3000)
printf '{"toast":"%s","copy":"%s"}\n' "contexto copiado ($total archivos)" "$(json "$texto")"
