#!/bin/sh
# Statusline de Claude Code: guarda el consumo del plan (limite de 5 horas y semanal) para la isla de claude pet.
# Claude Code entrega esos datos por stdin en `rate_limits`; aqui solo se copian dos numeros por ventana a
# ~/.claude-pet/usage.json (0600). No se guarda nada del proyecto, de los mensajes ni de credenciales.
#
# Si ya tenias un statusline, guardalo en ~/.claude-pet/statusline-chain (una linea con su comando): se le pasa
# la misma entrada y se imprime su salida tal cual. Sin cadena imprime un resumen corto, p. ej. "5h 42% · 7d 18%".

PET_DIR="$HOME/.claude-pet"
input=$(head -c 65536 2>/dev/null)

if command -v jq >/dev/null 2>&1; then
  row=$(printf '%s' "$input" | jq -c '(.rate_limits // empty) | {
      five: (.five_hour // null | if . then {p: (.used_percentage // null), r: (.resets_at // null)} else null end),
      week: (.seven_day // null | if . then {p: (.used_percentage // null), r: (.resets_at // null)} else null end)}' 2>/dev/null)
  if [ -n "$row" ]; then
    mkdir -p "$PET_DIR" 2>/dev/null && chmod 700 "$PET_DIR" 2>/dev/null
    tmp="$PET_DIR/.usage.$$"
    ( umask 077; printf '%s' "$row" | jq -c --argjson at "$(date +%s)" '. + {at: $at}' > "$tmp" 2>/dev/null ) && mv -f "$tmp" "$PET_DIR/usage.json" 2>/dev/null
    rm -f "$tmp" 2>/dev/null
  fi
fi

chain=$(head -n 1 "$PET_DIR/statusline-chain" 2>/dev/null)
if [ -n "$chain" ]; then
  printf '%s' "$input" | sh -c "$chain"
  exit 0
fi

if [ -n "$row" ]; then
  five=$(printf '%s' "$row" | jq -r '.five.p // empty | floor' 2>/dev/null)
  week=$(printf '%s' "$row" | jq -r '.week.p // empty | floor' 2>/dev/null)
  out=""
  [ -n "$five" ] && out="5h ${five}%"
  [ -n "$week" ] && out="${out:+$out · }7d ${week}%"
  printf '%s\n' "$out"
fi
exit 0
