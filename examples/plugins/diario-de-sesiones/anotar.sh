#!/bin/sh
# El evento llega por la entrada estandar como JSON (claves ordenadas). Se guarda una linea por sesion en la carpeta de datos propia.
payload=$(cat)
# Tolera JSON con o sin espacios y valores con comillas o numericos.
campo() {
  v=$(printf '%s' "$payload" | sed -n "s/.*\"$1\" *: *\"\([^\"]*\)\".*/\1/p" | head -1)
  [ -n "$v" ] || v=$(printf '%s' "$payload" | sed -n "s/.*\"$1\" *: *\([0-9][0-9]*\).*/\1/p" | head -1)
  printf '%s' "$v"
}
agente=$(campo agent); segundos=$(campo seconds); proyecto=$(campo project_name)
case "$segundos" in ''|*[!0-9]*) segundos=0 ;; esac
case "$agente" in claude|codex) ;; *) agente=otro ;; esac
# los escapes de JSON (\t, \n, \") se vuelven espacios o desaparecen: el nombre acaba en un TSV de una linea
proyecto=$(printf '%s' "$proyecto" | sed 's/\\[tnr]/ /g; s/\\//g' | tr -d '\t\r\n' | cut -c1-60)
log="$CLAUDE_PET_DATA_DIR/sesiones.tsv"
printf '%s\t%s\t%s\t%s\n' "$(date '+%F %T')" "$agente" "$segundos" "${proyecto:--}" >> "$log"
# se conservan las ultimas 5000 lineas
if [ "$(wc -l < "$log")" -gt 6000 ]; then tail -n 5000 "$log" > "$log.tmp" && mv "$log.tmp" "$log"; fi
