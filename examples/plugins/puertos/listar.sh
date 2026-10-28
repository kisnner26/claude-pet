#!/bin/sh
json() { printf '%s' "$1" | tr -d '\000-\010\013\014\016-\037' | awk 'BEGIN{ORS=""} {gsub(/\\/,"\\\\"); gsub(/"/,"\\\""); gsub(/\t/,"\\t"); gsub(/\r/,""); if (NR>1) printf "\\n"; printf "%s", $0}'; }
lista=$(/usr/sbin/lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null | awk 'NR>1 { n = split($9, a, ":"); print a[n] "\t" $1 "\t" $2 }' | sort -n -u | awk -F'\t' '!vistos[$1]++')
if [ -z "$lista" ]; then printf '{"toast":"no hay nada escuchando en TCP"}\n'; exit 0; fi
cuantos=$(printf '%s\n' "$lista" | wc -l | tr -d ' ')
corto=$(printf '%s\n' "$lista" | head -n 6 | awk -F'\t' '{ printf "%s%s %s", (NR>1 ? " · " : ""), $1, $2 }')
[ "$cuantos" -gt 6 ] && corto="$corto · +$((cuantos - 6))"
completo=$(printf '%s\n' "$lista" | awk -F'\t' '{ printf "%s\t%s\tpid %s\n", $1, $2, $3 }')
printf '{"toast":"%s","copy":"%s"}\n' "$(json "$corto")" "$(json "$completo")"
