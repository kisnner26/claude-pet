#!/bin/sh
# Traduce un evento de hook de Claude Code a un estado de la mascota.
# Uso: pet-hook.sh <Evento>     (el JSON del hook llega por stdin)
#
# Privacidad: todo es local (socket unix 0600). Del JSON se extraen session_id, tool_name, el nombre
# de la carpeta del proyecto, un detalle minimo para la burbuja (descripcion del comando, nombre de
# archivo, patron, programa de un comando sin argumentos, host de una URL), tu ultimo mensaje y la
# ruta del proyecto (solo para que la app detecte cambios y abra el diff; no se muestra, no se
# escribe a disco y no cruza el pet bus).
#
# Por defecto no imprime nada en stdout y siempre sale con 0: no altera ni bloquea a Claude Code.
# Excepciones, ambas bajo tu control: (1) OPT-IN, si activas "Bloquear herramientas si el proyecto
# cambia" (crea ~/.claude-pet/block-on-change); (2) si pides "pausar a claude" ante una colision.
# En los dos casos una marca reciente (< 10 min) de la app deniega la siguiente herramienta de esa
# sesion con la salida documentada de PreToolUse. La marca se borra con tu siguiente mensaje o al
# terminar la sesion.

# Una revision lanzada por la propia mascota no es una sesion del usuario: no se reporta.
[ -n "$CLAUDE_PET_REVIEW" ] && exit 0

SOCK="${CLAUDE_PET_SOCK:-$HOME/.claude-pet/pet.sock}"
PET_DIR="$HOME/.claude-pet"

input=$(head -c 8192 2>/dev/null)

field() {
  printf '%s' "$input" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([A-Za-z0-9_.:-]*\)\".*/\1/p" | head -n 1 | cut -c1-40
}

sid=$(field session_id | cut -c1-8)
MARK="$PET_DIR/context-changed/${sid:-x}"

[ "$1" = "UserPromptSubmit" ] && rm -f "$MARK"
[ "$1" = "SessionEnd" ] && rm -f "$MARK"

# Bloqueo: una marca reciente (< 10 min) de la app deniega la siguiente herramienta de esa sesion.
# Marca vacia = "el proyecto cambio" y solo cuenta con la bandera opt-in; "paused" = el usuario
# pidio pausar a claude desde el menu (colision con codex) y no necesita la bandera.
if [ "$1" = "PreToolUse" ] && [ -n "$(find "$MARK" -mmin -10 2>/dev/null)" ]; then
  kind=$(head -c 16 "$MARK" 2>/dev/null | tr -cd 'a-z')
  if [ "$kind" = "paused" ]; then
    printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Pausado desde claude pet: otra herramienta trabaja en este proyecto. Envia un nuevo mensaje cuando quieras continuar."}}'
    exit 0
  elif [ -f "$PET_DIR/block-on-change" ]; then
    printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"El proyecto cambio mientras Claude pensaba. Revisa el diff y envia un nuevo mensaje para continuar con contexto actualizado."}}'
    exit 0
  fi
fi

[ -S "$SOCK" ] || exit 0

cwd=$(printf '%s' "$input" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
proj=$(printf '%s' "${cwd##*/}" | tr -cd 'A-Za-z0-9_.-' | cut -c1-40)
ws=$(printf '%s' "$cwd" | tr -d '\000-\037\\' | cut -c1-1000)
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

raw() { printf '%s' "$input" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -n 1; }

# Pruebas: se clasifican mirando SOLO el campo "command" de una herramienta Bash
# (nunca el resto del payload, que puede llevar el texto de un archivo). No se conserva el comando.
if [ "$1" = "PreToolUse" ] && [ "$tool" = "Bash" ]; then
  case " $(raw command) " in
    *' swift test'*|*' npm test'*|*' npm run test'*|*' pnpm test'*|*' yarn test'*|*' pytest'*|*' php artisan test'*|*'/pytest '*) tool=test ;;
  esac
fi

# Detalle para la burbuja (solo local, nunca va al pet bus). Minimo necesario:
#  - descripcion que Claude escribe para Bash/Task, o nombre del archivo, o patron de busqueda;
#  - de un comando solo el programa (nunca argumentos, que pueden llevar secretos); de una URL solo el host.
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

printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$state" "${sid:-x}" "$tool" "$proj" "$detail" "$origin" "$task" "$ws" | nc -U -w 1 "$SOCK" >/dev/null 2>&1
exit 0
