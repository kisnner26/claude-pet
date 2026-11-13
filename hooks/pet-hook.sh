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

# Analisis del JSON: con jq, una sola pasada sobre el payload completo (hasta 1 MiB) y solo los campos de
# primer nivel o de tool_input, sin confundir claves anidadas ni texto de archivos con campos de control.
# Sin jq, o si jq falla (entrada rota o de mas de 1 MiB), se usa el camino de sed sobre los primeros 8 KB.
JQ_PROG='
def s: if type == "string" then . else "" end;
def nz: select(. != "");
def clean: s | gsub("[\\x00-\\x1f\\\\]"; "");
def flat: gsub("[\\n\\r\\t]"; " ");
def ident: s | if test("^[A-Za-z0-9_.:-]*\\z") then . else "" end;
def first_word: sub("[ \\t\\r\\n].*"; ""; "s") | sub("^.*/"; "");
(if type == "object" then . else {} end) as $r
| ($r.tool_input | if type == "object" then . else {} end) as $ti
| ($r.tool_name | ident | .[0:40]) as $tool
| ($r.cwd | s) as $cwd
| ($ti.command | s) as $cmd
| (" " + ($cmd | flat) + " ") as $padded
| (if $ev == "PreToolUse" and $tool == "Bash"
     and ([" swift test", " npm test", " npm run test", " pnpm test", " yarn test", " pytest", " php artisan test", "/pytest "]
          | map(. as $p | $padded | contains($p)) | any)
   then "1" else "0" end) as $test
| (($ti.description | s | nz)
   // ($ti.file_path | s | sub("^.*/"; "") | nz)
   // ($ti.pattern | s | nz)
   // ($cmd | first_word | nz | "$ " + .)
   // ($ti.url | s | sub("^.*?://"; "") | sub("/.*$"; "") | nz)
   // "") as $detail
| (if $ev == "UserPromptSubmit" then
     ($r.prompt | s | flat | clean | sub("^ +"; "") | .[0:200]) | if . != "" then "p:" + . else "" end
   elif $ev == "PreToolUse" and ($tool == "TodoWrite" or $tool == "TaskUpdate" or $tool == "TaskCreate") then
     ([$ti | (.todos[]?, .) | objects | select(.status == "in_progress") | .activeForm | strings | flat | clean | sub("^ +"; "") | nz] | first // "")
       | if . != "" then "t:" + .[0:200] else "" end
   else "" end) as $task
| [ ($r.session_id | ident | .[0:8]), $tool, ($cwd | sub("^.*/"; "") | gsub("[^A-Za-z0-9_.-]"; "") | .[0:40]),
    ($detail | clean | .[0:120]), $task, $test, ($cwd | clean | .[0:1000]) ] | join("\u001f")'

full=$(head -c 1048577 2>/dev/null)
jqok=""
if command -v jq >/dev/null 2>&1; then
  parsed=$(printf '%s' "$full" | jq -r --arg ev "$1" "$JQ_PROG" 2>/dev/null) || parsed=""
  if [ -n "$parsed" ]; then
    IFS=$(printf '\037') read -r j_sid j_tool j_proj j_detail j_task j_test j_ws <<EOF
$parsed
EOF
    jqok=1
  fi
fi
[ -n "$jqok" ] || input=$(printf '%s' "$full" | head -c 8192)

field() {
  printf '%s' "$input" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([A-Za-z0-9_.:-]*\)\".*/\1/p" | head -n 1 | cut -c1-40
}

if [ -n "$jqok" ]; then sid=$j_sid; else sid=$(field session_id | cut -c1-8); fi
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

if [ -n "$jqok" ]; then
  proj=$j_proj; ws=$j_ws
else
  cwd=$(printf '%s' "$input" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
  proj=$(printf '%s' "${cwd##*/}" | tr -cd 'A-Za-z0-9_.-' | cut -c1-40)
  ws=$(printf '%s' "$cwd" | tr -d '\000-\037\\' | cut -c1-1000)
fi
tool=""

case "$1" in
  SessionStart)        state=starting ;;
  UserPromptSubmit)    state=thinking ;;
  PreToolUse)          state=tool; if [ -n "$jqok" ]; then tool=$j_tool; else tool=$(field tool_name); fi ;;
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
if [ -n "$jqok" ]; then
  [ "$j_test" = 1 ] && tool=test
elif [ "$1" = "PreToolUse" ] && [ "$tool" = "Bash" ]; then
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
    if [ -n "$jqok" ]; then
      detail=$j_detail
    else
      d=$(raw description)
      if [ -z "$d" ]; then f=$(raw file_path); d=${f##*/}; fi
      [ -z "$d" ] && d=$(raw pattern)
      if [ -z "$d" ]; then c=$(raw command); c=${c%% *}; c=${c##*/}; [ -n "$c" ] && d="\$ $c"; fi
      if [ -z "$d" ]; then u=$(raw url); u=${u#*://}; d=${u%%/*}; fi
      detail=$(printf '%s' "$d" | tr -d '\000-\037\\' | head -c 120)
    fi
    ;;
esac

# Tarea actual (solo local): tu ultimo mensaje (p:) o la tarea en curso de la lista de Claude (t:).
task=""
clean_text() { sed 's/\\n/ /g; s/\\t/ /g' | tr -d '\000-\037\\' | sed 's/^ *//' | head -c 200; }
if [ -n "$jqok" ]; then
  task=$j_task
else
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
fi

case "${CLAUDE_CODE_ENTRYPOINT:-}" in
  claude-desktop) origin=desktop ;;
  cli|"") origin=terminal ;;
  *) origin=otro ;;
esac

printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$state" "${sid:-x}" "$tool" "$proj" "$detail" "$origin" "$task" "$ws" | nc -U -w 1 "$SOCK" >/dev/null 2>&1
exit 0
