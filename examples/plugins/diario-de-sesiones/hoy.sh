#!/bin/sh
json() { printf '%s' "$1" | tr -d '\000-\010\013\014\016-\037' | awk 'BEGIN{ORS=""} {gsub(/\\/,"\\\\"); gsub(/"/,"\\\""); gsub(/\t/,"\\t"); gsub(/\r/,""); if (NR>1) printf "\\n"; printf "%s", $0}'; }
log="$CLAUDE_PET_DATA_DIR/sesiones.tsv"
hoy=$(date '+%F')
if [ ! -s "$log" ] || ! grep -q "^$hoy" "$log"; then printf '{"toast":"hoy todavía no hay sesiones anotadas"}\n'; exit 0; fi
resumen=$(grep "^$hoy" "$log" | awk -F'\t' '
  { n++; seg += $3; ag[$2]++; pr[$4] += $3 }
  END {
    h = int(seg / 3600); m = int((seg % 3600) / 60)
    dur = (h > 0) ? h "h " m "m" : m "m"
    out = n " sesion" (n == 1 ? "" : "es") " · " dur
    sep = " · "
    for (a in ag) { out = out sep a " " ag[a]; sep = ", " }
    best = ""; bs = -1
    for (p in pr) if (pr[p] > bs) { bs = pr[p]; best = p }
    if (best != "" && best != "-") out = out " · más tiempo en " best
    print out
  }')
detalle=$(grep "^$hoy" "$log" | tail -n 30 | awk -F'\t' '{ printf "- %s %s %dm %s\n", substr($1,12,5), $2, int($3/60), $4 }')
copia="## sesiones de hoy ($hoy)
$resumen

$detalle"
printf '{"toast":"%s","copy":"%s"}\n' "$(json "hoy: $resumen")" "$(json "$copia")"
