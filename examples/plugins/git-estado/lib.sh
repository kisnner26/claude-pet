# Utilidades comunes. Todo lo que se mete en el JSON se escapa antes: nombres de rama, mensajes de commit y rutas son datos ajenos.
json() { printf '%s' "$1" | tr -d '\000-\010\013\014\016-\037' | awk 'BEGIN{ORS=""} {gsub(/\\/,"\\\\"); gsub(/"/,"\\\""); gsub(/\t/,"\\t"); gsub(/\r/,""); if (NR>1) printf "\\n"; printf "%s", $0}'; }
say() { printf '{"toast":"%s"}\n' "$(json "$1")"; }
say_copy() { printf '{"toast":"%s","copy":"%s"}\n' "$(json "$1")" "$(json "$2")"; }
export GIT_OPTIONAL_LOCKS=0
[ -n "${CLAUDE_PET_PROJECT:-}" ] && cd "$CLAUDE_PET_PROJECT" 2>/dev/null || { say "no hay un proyecto activo"; exit 0; }
git rev-parse --git-dir >/dev/null 2>&1 || { say "${CLAUDE_PET_PROJECT_NAME:-el proyecto} no es un repositorio git"; exit 0; }
branch=$(git symbolic-ref --short -q HEAD || git rev-parse --short HEAD)
