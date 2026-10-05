#!/bin/sh
# Traduce un evento de hook de Claude Code a un estado de la mascota.
# Uso: pet-hook.sh <Evento>     (el JSON del hook llega por stdin)
#
# Privacidad: del JSON solo se extraen session_id, tool_name y el nombre (no la ruta) de la carpeta del proyecto, saneados.
# No se reenvia prompt, comando, ruta, salida ni nada de la conversacion.
# No imprime nada en stdout y siempre sale con 0: nunca altera ni bloquea a Claude Code.

SOCK="${CLAUDE_PET_SOCK:-$HOME/.claude-pet/pet.sock}"
[ -S "$SOCK" ] || exit 0

input=$(head -c 8192 2>/dev/null)

field() {
  printf '%s' "$input" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([A-Za-z0-9_.:-]*\)\".*/\1/p" | head -n 1 | cut -c1-40
}

sid=$(field session_id | cut -c1-8)
# solo el nombre de la carpeta del proyecto (no la ruta), saneado
cwd=$(printf '%s' "$input" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
proj=$(printf '%s' "${cwd##*/}" | tr -cd 'A-Za-z0-9_.-' | cut -c1-40)
tool=""

case "$1" in
  SessionStart)        state=starting ;;
  UserPromptSubmit)    state=thinking ;;
  PreToolUse)          state=tool; tool=$(field tool_name) ;;
  PostToolUse)         state=thinking ;;
  PermissionRequest)   state=waiting ;;
  PermissionDenied)    state=thinking ;;
  PostToolUseFailure)  state=error ;;
  StopFailure)         state=error ;;
  Stop)                state=done ;;
  SessionEnd)          state=end ;;
  *) exit 0 ;;
esac

# Detalle para la burbuja (solo local, nunca va al pet bus). Minimo necesario:
#  - descripcion que Claude escribe para Bash/Task, o nombre del archivo, o patron de busqueda;
#  - de un comando solo el programa (nunca argumentos, que pueden llevar secretos); de una URL solo el host.
raw() { printf '%s' "$input" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -n 1; }
detail=""
case "$state" in
  tool|waiting)
    d=$(raw description)
    if [ -z "$d" ]; then f=$(raw file_path); d=${f##*/}; fi
    [ -z "$d" ] && d=$(raw pattern)
    if [ -z "$d" ]; then c=$(raw command); c=${c%% *}; c=${c##*/}; [ -n "$c" ] && d="\$ $c"; fi
    if [ -z "$d" ]; then u=$(raw url); u=${u#*://}; d=${u%%/*}; fi
    detail=$(printf '%s' "$d" | tr -d '\000-\037\\' | head -c 120)
    ;;
esac
# Tarea actual (solo local): tu ultimo mensaje (p:) o la tarea en curso de la lista de Claude (t:).
task=""
clean_text() { sed 's/\\n/ /g; s/\\t/ /g' | tr -d '\000-\037\\' | sed 's/^ *//' | head -c 200; }
case "$1" in
  UserPromptSubmit)
    t=$(printf '%s' "$input" | sed -nE 's/.*"prompt"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)".*/\1/p' | head -n 1 | sed 's/\\"/"/g' | clean_text)
    [ -n "$t" ] && task="p:$t" ;;
  PreToolUse|PostToolUse)
    case "$tool" in
      TodoWrite|TaskUpdate|TaskCreate)
        t=$(printf '%s' "$input" | sed -n 's/.*"status"[[:space:]]*:[[:space:]]*"in_progress"[^}]*"activeForm"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p; s/.*"activeForm"[[:space:]]*:[[:space:]]*"\([^"]*\)"[^}]*"status"[[:space:]]*:[[:space:]]*"in_progress".*/\1/p' | head -n 1 | clean_text)
        [ -n "$t" ] && task="t:$t" ;;
    esac ;;
esac
case "${CLAUDE_CODE_ENTRYPOINT:-}" in
  claude-desktop) origin=desktop ;;
  cli|"") origin=terminal ;;
  *) origin=otro ;;
esac

printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$state" "${sid:-x}" "$tool" "$proj" "$detail" "$origin" "$task" | nc -U -w 1 "$SOCK" >/dev/null 2>&1
exit 0
