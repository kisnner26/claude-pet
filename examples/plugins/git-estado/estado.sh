#!/bin/sh
# Rama, cambios y adelanto/atraso respecto a su remota.
. "$(dirname "$0")/lib.sh"
total=$(git status --porcelain | wc -l | tr -d ' ')
nuevos=$(git status --porcelain | grep -c '^??')
msg="$branch"
if [ "$total" -eq 0 ]; then msg="$msg · limpio"; else msg="$msg · $total cambios"; [ "$nuevos" -gt 0 ] && msg="$msg ($nuevos sin seguir)"; fi
if counts=$(git rev-list --left-right --count '@{u}...HEAD' 2>/dev/null); then
  atras=${counts%%[[:space:]]*}; adelante=${counts##*[[:space:]]}
  [ "$adelante" -gt 0 ] && msg="$msg · ↑$adelante por subir"
  [ "$atras" -gt 0 ] && msg="$msg · ↓$atras por bajar"
else
  msg="$msg · sin remota"
fi
say "$msg"
