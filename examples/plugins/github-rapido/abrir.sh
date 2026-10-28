#!/bin/sh
# Solo GitHub. La direccion sale del remoto "origin" y pierde cualquier usuario o token que llevara.
json() { printf '%s' "$1" | tr -d '\000-\010\013\014\016-\037' | awk 'BEGIN{ORS=""} {gsub(/\\/,"\\\\"); gsub(/"/,"\\\""); gsub(/\t/,"\\t"); gsub(/\r/,""); if (NR>1) printf "\\n"; printf "%s", $0}'; }
say() { printf '{"toast":"%s"}\n' "$(json "$1")"; }
export GIT_OPTIONAL_LOCKS=0
[ -n "${CLAUDE_PET_PROJECT:-}" ] && cd "$CLAUDE_PET_PROJECT" 2>/dev/null || { say "no hay un proyecto activo"; exit 0; }
remote=$(git remote get-url origin 2>/dev/null) || { say "este proyecto no tiene remoto «origin»"; exit 0; }
base=$(printf '%s' "$remote" | sed -E 's#^git@github\.com:#https://github.com/#; s#^ssh://git@github\.com/#https://github.com/#; s#^https?://[^/@]*@#https://#; s#\.git$##; s#/$##')
printf '%s' "$base" | grep -Eq '^https://github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$' || { say "el remoto no es de GitHub"; exit 0; }
case "${1:-}" in
  pulls) url="$base/pulls" ;;
  issues) url="$base/issues" ;;
  actions) url="$base/actions" ;;
  pr)
    branch=$(git symbolic-ref --short -q HEAD) || { say "no estás en una rama"; exit 0; }
    printf '%s' "$branch" | grep -Eq '^[A-Za-z0-9._/-]+$' || { say "el nombre de la rama tiene caracteres raros"; exit 0; }
    url=""
    # si tienes gh, se usa el PR que ya existe; si no, el enlace para crearlo
    if command -v gh >/dev/null 2>&1; then
      found=$(gh pr view --json url --jq .url 2>/dev/null)
      printf '%s' "$found" | grep -Eq '^https://github\.com/' && url="$found"
    fi
    [ -n "$url" ] || url="$base/compare/$branch?expand=1" ;;
  *) say "acción desconocida"; exit 0 ;;
esac
printf '{"toast":"abriendo en GitHub","open":"%s"}\n' "$url"
