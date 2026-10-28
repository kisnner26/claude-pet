#!/bin/sh
. "$(dirname "$0")/lib.sh"
last=$(git log -1 --format='%h %s' 2>/dev/null) || { say "este repositorio todavía no tiene commits"; exit 0; }
say_copy "copiado: $last" "$last"
