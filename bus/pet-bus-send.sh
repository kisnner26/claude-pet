#!/bin/sh
# Cliente de referencia del pet bus (v1). Publica la presencia de UNA mascota a las demas.
# Pensado para el adaptador de Codex, pero sirve para cualquier id valido ([a-z0-9-]{1,16}).
#
#   pet-bus-send.sh <id> <estado> [evento] [proyecto]     envia un mensaje y sale
#   pet-bus-send.sh --hold <id> [estado]                  presencia continua: envia "appeared",
#                                                          reenvia cada 10 s y manda "left" al salir
#                                                          (el estado se puede cambiar escribiendo
#                                                          una palabra en ~/.claude-pet/bus/<id>.state)
#
# Estados: idle starting thinking tool waiting done error
# Eventos: appeared working waiting finished error left   (opcional)
#
# Solo habla con sockets Unix locales de ~/.claude-pet/bus/. Sin red, sin credenciales.

BUS="${CLAUDE_PET_BUS:-$HOME/.claude-pet/bus}"

send() { # id state event project
  id=$1; state=$2; event=$3; project=$4
  ts=$(date +%s)
  msg="{\"v\":1,\"id\":\"$id\",\"state\":\"$state\",\"ts\":$ts"
  [ -n "$project" ] && msg="$msg,\"project\":\"$project\""
  [ -n "$event" ] && msg="$msg,\"event\":\"$event\""
  msg="$msg}"
  for s in "$BUS"/*.sock; do
    [ -S "$s" ] || continue
    [ "$s" = "$BUS/$id.sock" ] && continue
    printf '%s\n' "$msg" | nc -U -w 1 "$s" >/dev/null 2>&1
  done
}

valid() { printf '%s' "$1" | grep -Eq '^[a-z0-9-]{1,16}$'; }
clean() { printf '%s' "$1" | tr -cd 'A-Za-z0-9_.-' | cut -c1-40; }

if [ "$1" = "--hold" ]; then
  id=$2; state=${3:-idle}
  valid "$id" || { echo "id invalido" >&2; exit 1; }
  trap 'send "$id" idle left; exit 0' INT TERM
  send "$id" "$state" appeared
  while :; do
    [ -f "$BUS/$id.state" ] && state=$(clean "$(cat "$BUS/$id.state")")
    send "$id" "${state:-idle}" ""
    sleep 10 & wait $!
  done
fi

id=$1; state=$2
valid "$id" && [ -n "$state" ] || { sed -n '2,17p' "$0" | cut -c3-; exit 1; }
send "$id" "$(clean "$state")" "$(clean "$3")" "$(clean "$4")"
