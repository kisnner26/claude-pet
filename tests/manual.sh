#!/bin/sh
# Pruebas manuales: recorre cada estado enviando eventos con la forma real de los hooks
# (JSON ficticio, sin contenido de conversaciones). Requiere la app abierta.
# Uso: tests/manual.sh            (todo en secuencia)
#      tests/manual.sh waiting    (un solo estado)
HOOK="$(cd "$(dirname "$0")/.." && pwd)/hooks/pet-hook.sh"
SID='"session_id":"abc12345-test"'

ev() { printf '{%s,"hook_event_name":"%s"%s}' "$SID" "$1" "$2" | "$HOOK" "$1"; }

run() {
  case "$1" in
    idle)     ev SessionEnd; echo "idle: carbon sin actividad, parpadea y cursor titila" ;;
    starting) ev SessionStart; echo "starting: ojos cerrados y barra de carga sobre la cabeza" ;;
    thinking) ev UserPromptSubmit; echo "thinking: ojos miran arriba y tres puntos aparecen" ;;
    tool)     ev PreToolUse ',"tool_name":"Bash","tool_input":{"command":"ls"}'; echo "tool: brazos tecleando, chispas y nombre 'Bash' abajo" ;;
    waiting)  ev PermissionRequest ',"tool_name":"Bash"'; echo "waiting: brazos arriba, '!' parpadeante, etiqueta en terracota" ;;
    done)     ev Stop; echo "done: ojos felices, salta y check; vuelve a idle a los 5 s" ;;
    error)    ev StopFailure; echo "error: ojos X, temblor y humo; vuelve a idle a los 8 s" ;;
    *) echo "estado desconocido: $1"; exit 1 ;;
  esac
}

if [ -n "$1" ]; then run "$1"; exit 0; fi
for s in starting thinking tool waiting thinking done; do run "$s"; sleep 3; done
run error; sleep 4
run idle
echo "fin. Revisa que cada descripcion coincida con lo que viste."
