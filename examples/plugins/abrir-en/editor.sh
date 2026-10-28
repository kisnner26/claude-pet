#!/bin/sh
json() { printf '%s' "$1" | tr -d '\000-\010\013\014\016-\037' | awk 'BEGIN{ORS=""} {gsub(/\\/,"\\\\"); gsub(/"/,"\\\""); gsub(/\t/,"\\t"); gsub(/\r/,""); if (NR>1) printf "\\n"; printf "%s", $0}'; }
say() { printf '{"toast":"%s"}\n' "$(json "$1")"; }
[ -d "${CLAUDE_PET_PROJECT:-}" ] || { say "no hay un proyecto activo"; exit 0; }
# el ajuste solo vale si es uno de la lista: nunca se pasa texto libre a `open`
case "${CLAUDE_PET_SETTING_EDITOR:-Visual Studio Code}" in
  "Visual Studio Code"|Cursor|Xcode|Zed|"Sublime Text"|Nova) editor="${CLAUDE_PET_SETTING_EDITOR:-Visual Studio Code}" ;;
  *) say "editor no reconocido"; exit 0 ;;
esac
/usr/bin/open -Ra "$editor" 2>/dev/null || { say "no encuentro $editor en este Mac"; exit 0; }
destino="$CLAUDE_PET_PROJECT"
if [ "$editor" = "Xcode" ]; then
  for patron in '*.xcworkspace' 'Package.swift' '*.xcodeproj'; do
    hallado=$(find "$CLAUDE_PET_PROJECT" -maxdepth 1 -name "$patron" ! -name '.*' | head -n 1)
    [ -n "$hallado" ] && { destino="$hallado"; break; }
  done
fi
/usr/bin/open -a "$editor" "$destino" && say "abriendo ${CLAUDE_PET_PROJECT_NAME:-el proyecto} en $editor" || say "no se pudo abrir en $editor"
