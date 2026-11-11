#!/bin/sh
# Pruebas del analisis del JSON en hooks/pet-hook.sh: comillas escapadas, rutas con espacios y unicode,
# payloads de mas de 8 KB, claves anidadas con el mismo nombre que un campo de control, contenido de
# archivos que parece JSON, y el camino sin jq. Usa un HOME temporal y un socket propio: no toca
# ~/.claude-pet ni ~/.claude.
#   tests/hook-parse.sh                           prueba hooks/pet-hook.sh
#   HOOK=/ruta/otro-hook.sh tests/hook-parse.sh   prueba otra version (p. ej. la anterior, para comparar)
HOOK="${HOOK:-$(cd "$(dirname "$0")/.." && pwd)/hooks/pet-hook.sh}"
fail=0
ok() { echo "OK: $1"; }
bad() { echo "FALLO: $1"; fail=1; }

H=$(mktemp -d); export HOME="$H"; mkdir -p "$H/.claude-pet/context-changed"
unset CLAUDE_PET_REVIEW CLAUDE_CODE_ENTRYPOINT

# PATH sin jq para probar el camino de reserva (sed). Solo las herramientas que usa el hook.
NOJQ="$H/nojq-bin"; mkdir -p "$NOJQ"
for t in head sed tr cut find nc rm cat mkdir date grep awk wc; do
  p=$(command -v "$t") && ln -s "$p" "$NOJQ/$t"
done

# cap EVENTO JSON [nojq] -> deja en $LINE lo enviado al socket, en $OUT el stdout, en $ERR el stderr y en $RC la salida
cap() {
  d=$(mktemp -d); sock="$d/s.sock"
  nc -lU "$sock" > "$d/o" 2>/dev/null & lp=$!
  i=0; while [ ! -S "$sock" ] && [ "$i" -lt 60 ]; do sleep 0.05; i=$((i+1)); done
  if [ "$3" = nojq ]; then
    printf '%s' "$2" | PATH="$NOJQ" CLAUDE_PET_SOCK="$sock" /bin/sh "$HOOK" "$1" > "$d/out" 2>"$d/err"; RC=$?
  else
    printf '%s' "$2" | CLAUDE_PET_SOCK="$sock" /bin/sh "$HOOK" "$1" > "$d/out" 2>"$d/err"; RC=$?
  fi
  i=0; while kill -0 "$lp" 2>/dev/null && [ "$i" -lt 40 ]; do sleep 0.05; i=$((i+1)); done
  kill "$lp" 2>/dev/null; wait "$lp" 2>/dev/null
  LINE=$(cat "$d/o"); OUT=$(cat "$d/out"); ERR=$(cat "$d/err"); rm -rf "$d"
}
# campo N (1 estado, 2 sid, 3 herramienta, 4 proyecto, 5 detalle, 6 origen, 7 tarea, 8 ruta)
fld() { printf '%s' "$LINE" | cut -f"$1"; }
# chk NOMBRE N ESPERADO
chk() {
  got=$(fld "$2")
  if [ "$got" = "$3" ]; then ok "$1"; else bad "$1 (campo $2: esperado [$3], llego [$got])"; fi
}
nfields() { printf '%s' "$LINE" | awk -F'\t' '{print NF}'; }
# genera un archivo con N bytes de relleno
filler() { head -c "$1" /dev/zero | tr '\0' 'x' > "$2"; }

# --- linea de base: payload normal, con y sin jq ---
for mode in jq nojq; do
  P=$(jq -nc '{session_id:"abcdef123456",cwd:"/Users/x/proyecto",hook_event_name:"PreToolUse",tool_name:"Read",tool_input:{file_path:"/Users/x/proyecto/src/a.swift"}}')
  cap PreToolUse "$P" $mode
  chk "[$mode] base: estado" 1 tool; chk "[$mode] base: sid recortado a 8" 2 abcdef12; chk "[$mode] base: herramienta" 3 Read
  chk "[$mode] base: proyecto" 4 proyecto; chk "[$mode] base: detalle es el nombre del archivo" 5 a.swift
  chk "[$mode] base: ruta" 8 /Users/x/proyecto
  [ "$RC" = 0 ] && [ -z "$OUT" ] && ok "[$mode] base: sale con 0 y sin stdout" || bad "[$mode] base: rc=$RC stdout=[$OUT]"
done

# --- comillas escapadas en el detalle ---
P=$(jq -nc '{session_id:"abcdef123456",cwd:"/Users/x/p",tool_name:"Bash",tool_input:{command:"ls",description:"Corre \"npm install\" en el proyecto"}}')
cap PreToolUse "$P"
chk "comillas escapadas en description no cortan el detalle" 5 'Corre "npm install" en el proyecto'

# --- clasificacion de pruebas con comillas escapadas antes del comando ---
P=$(jq -nc '{session_id:"abcdef123456",cwd:"/Users/x/p",tool_name:"Bash",tool_input:{command:"FOO=\"a b\" swift test --filter Secreto123"}}')
cap PreToolUse "$P"
chk "swift test tras una asignacion con comillas se marca como prueba" 3 test
case "$LINE" in *Secreto123*|*filter*) bad "se filtraron argumentos del comando";; *) ok "los argumentos del comando no viajan";; esac
P=$(jq -nc '{session_id:"abcdef123456",cwd:"/Users/x/p",tool_name:"Bash",tool_input:{command:"cd /tmp\nswift test"}}')
cap PreToolUse "$P"
chk "swift test en otra linea del comando se marca como prueba" 3 test
P=$(jq -nc '{session_id:"abcdef123456",cwd:"/Users/x/p",tool_name:"Bash",tool_input:{command:"echo \"swift test\" > /dev/null; ls"}}')
cap PreToolUse "$P"
chk "detalle de un comando: solo el programa" 5 '$ echo'

# --- rutas cwd ---
P=$(jq -nc '{session_id:"abcdef123456",cwd:"/Users/x/mi proyecto grande",tool_name:"Read"}')
cap PreToolUse "$P"; chk "cwd con espacios llega entera" 8 "/Users/x/mi proyecto grande"
P=$(jq -nc '{session_id:"abcdef123456",cwd:"/Users/x/canción ñandú",tool_name:"Read"}')
cap PreToolUse "$P"; chk "cwd con tildes y enie llega entera" 8 "/Users/x/canción ñandú"
P=$(jq -nca '{session_id:"abcdef123456",cwd:"/Users/x/café",tool_name:"Read"}')   # -a: la salida lleva é escapado
printf '%s' "$P" | grep -Fq 'u00e9' || bad "preparacion: el payload no lleva el escape unicode"
cap PreToolUse "$P"; chk "cwd con escape unicode se decodifica" 8 "/Users/x/café"
P=$(jq -nc '{session_id:"abcdef123456",cwd:"/Users/x/co\"mi\"llas",tool_name:"Read"}')
cap PreToolUse "$P"; chk "cwd con comillas escapadas no se corta" 8 '/Users/x/co"mi"llas'
P=$(jq -nc '{session_id:"abcdef123456",cwd:"/Users/x/con\\barra",tool_name:"Read"}')
cap PreToolUse "$P"; chk "cwd con barra invertida: se quita la barra, resto intacto" 8 "/Users/x/conbarra"
[ "$(nfields)" = 8 ] && ok "siempre 8 campos" || bad "campos: $(nfields)"
P=$(jq -nc '{session_id:"abcdef123456",cwd:"/Users/x/a\tb\nc",tool_name:"Read",tool_input:{description:"x\ty\nz"}}')
cap PreToolUse "$P"
[ "$(nfields)" = 8 ] && ok "tabuladores y saltos dentro de valores no rompen el formato" || bad "campos con tab/salto: $(nfields) [$LINE]"

# --- payloads de mas de 8 KB ---
T=$(mktemp); filler 20000 "$T"
# orden realista de Claude Code: los campos de control van antes de tool_input
P=$(jq -nc --rawfile big "$T" '{session_id:"abcdef123456",cwd:"/Users/x/p",hook_event_name:"PreToolUse",tool_name:"Write",tool_input:{file_path:"/Users/x/p/grande.txt",content:$big}}')
cap PreToolUse "$P"
chk "Write grande (orden de Claude Code): herramienta" 3 Write; chk "Write grande: detalle" 5 grande.txt; chk "Write grande: sid" 2 abcdef12
# orden no garantizado: el contenido grande antes de los campos de control
P=$(jq -nc --rawfile big "$T" '{tool_input:{content:$big,file_path:"/Users/x/p/grande.txt"},tool_name:"Write",session_id:"abcdef123456",cwd:"/Users/x/p"}')
cap PreToolUse "$P"
chk "Write grande con tool_input primero: herramienta" 3 Write; chk "Write grande con tool_input primero: sid" 2 abcdef12
chk "Write grande con tool_input primero: proyecto" 4 p; chk "Write grande con tool_input primero: detalle" 5 grande.txt
# prompt largo
P=$(jq -nc --rawfile big "$T" '{session_id:"abcdef123456",cwd:"/Users/x/p",hook_event_name:"UserPromptSubmit",prompt:("hola " + $big)}')
cap UserPromptSubmit "$P"
case "$(fld 7)" in p:hola\ xxx*) ok "prompt de mas de 8 KB: la tarea llega (recortada)";; *) bad "prompt largo: tarea [$(fld 7 | cut -c1-30)]";; esac
[ "$(fld 7 | wc -c)" -le 204 ] && ok "la tarea sigue recortada a 200" || bad "tarea sin recortar"
# lista de tareas con el elemento en curso despues de mucho texto
P=$(jq -nc --rawfile big "$T" '{session_id:"abcdef123456",cwd:"/Users/x/p",tool_name:"TodoWrite",tool_input:{todos:[{content:$big,status:"completed",activeForm:"hecho"},{content:"b",status:"in_progress",activeForm:"Escribiendo las pruebas"}]}}')
cap PreToolUse "$P"; chk "TodoWrite con la tarea en curso pasado 8 KB" 7 "t:Escribiendo las pruebas"
# mas de 1 MB: debe seguir funcionando con lo que quepa en la ventana
filler 1500000 "$T"
P=$(jq -nc --rawfile big "$T" '{session_id:"abcdef123456",cwd:"/Users/x/p",tool_name:"Write",tool_input:{file_path:"/Users/x/p/enorme.txt",content:$big}}')
cap PreToolUse "$P"
chk "Write de 1,5 MB: herramienta" 3 Write; chk "Write de 1,5 MB: proyecto" 4 p
[ "$RC" = 0 ] && [ -z "$OUT" ] && ok "Write de 1,5 MB: sale con 0 y sin stdout" || bad "Write enorme: rc=$RC stdout=[$OUT]"
rm -f "$T"

# --- claves anidadas con el nombre de un campo de control (la ultima ganaba) ---
P=$(jq -nc '{session_id:"abcdef123456",cwd:"/Users/x/real",hook_event_name:"PreToolUse",tool_name:"mcp__term__run",tool_input:{cwd:"/otro/sitio/ajeno",tool_name:"Falsa",session_id:"zzzzzzzz9999",command:"ls"}}')
cap PreToolUse "$P"
chk "clave tool_name anidada no suplanta a la herramienta" 3 mcp__term__run
chk "clave cwd anidada no suplanta a la ruta" 8 /Users/x/real; chk "clave cwd anidada: proyecto" 4 real
chk "clave session_id anidada no suplanta a la sesion" 2 abcdef12
P=$(jq -nc '{session_id:"abcdef123456",cwd:"/Users/x/real",hook_event_name:"PostToolUse",tool_name:"mcp__x__y",tool_input:{},tool_response:{session_id:"zzzzzzzz9999",cwd:"/otro",tool_name:"Falsa"}}')
cap PostToolUse "$P"
chk "tool_response con session_id propio no suplanta a la sesion" 2 abcdef12; chk "tool_response con cwd propio no suplanta a la ruta" 8 /Users/x/real

# --- contenido de un archivo que parece JSON de control (va escapado dentro de una cadena) ---
CONT='{"session_id":"hostil123","tool_name":"Bash","cwd":"/etc/hostil","command":"rm -rf x","description":"falso"}
"tool_name": "Bash", "cwd": "/etc/hostil"'
P=$(jq -nc --arg c "$CONT" '{session_id:"abcdef123456",cwd:"/Users/x/real",hook_event_name:"PreToolUse",tool_name:"Write",tool_input:{file_path:"/Users/x/real/notas.json",content:$c}}')
for mode in jq nojq; do
  cap PreToolUse "$P" $mode
  chk "[$mode] contenido de archivo con claves falsas: herramienta" 3 Write; chk "[$mode] contenido falso: sid" 2 abcdef12
  chk "[$mode] contenido falso: ruta" 8 /Users/x/real; chk "[$mode] contenido falso: detalle" 5 notas.json
done
P=$(jq -nc --arg c "$CONT" '{session_id:"abcdef123456",cwd:"/Users/x/real",hook_event_name:"PostToolUse",tool_name:"Edit",tool_input:{file_path:"/Users/x/real/a.json",old_string:"x",new_string:$c},tool_response:{filePath:"/Users/x/real/a.json",newString:$c}}')
cap PostToolUse "$P"; chk "PostToolUse con contenido falso: sid" 2 abcdef12; chk "PostToolUse con contenido falso: ruta" 8 /Users/x/real

# --- prompt y tareas con escapes ---
P=$(jq -nc '{session_id:"abcdef123456",cwd:"/Users/x/p",hook_event_name:"UserPromptSubmit",prompt:"di \"hola\"\ny \\ adios café"}')
cap UserPromptSubmit "$P"; chk "prompt con comillas, salto, barra y acento" 7 'p:di "hola" y  adios café'
P=$(jq -nc '{session_id:"abcdef123456",cwd:"/Users/x/p",tool_name:"TodoWrite",tool_input:{todos:[{content:"a",status:"pending",activeForm:"Otra"},{content:"b",status:"in_progress",activeForm:"Probando \"todo\""}]}}')
cap PreToolUse "$P"; chk "tarea en curso con comillas escapadas" 7 't:Probando "todo"'

# --- fallos que deben abrir: entrada rota, vacia o truncada ---
for mode in jq nojq; do
  cap PreToolUse 'esto no es json' $mode
  [ "$RC" = 0 ] && [ -z "$OUT" ] && [ -z "$ERR" ] && ok "[$mode] entrada que no es JSON: sale con 0, sin stdout ni stderr" || bad "[$mode] basura: rc=$RC out=[$OUT] err=[$ERR]"
  cap PreToolUse '' $mode
  [ "$RC" = 0 ] && [ -z "$OUT" ] && ok "[$mode] entrada vacia: sale con 0 y sin stdout" || bad "[$mode] vacia: rc=$RC out=[$OUT]"
  cap PreToolUse '{"session_id":"abcdef123456","cwd":"/Users/x/p","tool_name":"Read","tool_input":{"file_path":"/Users/x/p/a' $mode
  chk "[$mode] JSON truncado: aun se rescata la herramienta" 3 Read
  cap Evento_desconocido '{"session_id":"abcdef123456"}' $mode
  [ "$RC" = 0 ] && [ -z "$LINE" ] && ok "[$mode] evento desconocido: no envia nada" || bad "[$mode] evento desconocido envio [$LINE]"
done

# --- el camino sin jq sigue dando lo mismo en los casos normales ---
P=$(jq -nc '{session_id:"abcdef123456",cwd:"/Users/x/mi proyecto",tool_name:"Bash",tool_input:{command:"swift test",description:"Corre las pruebas"}}')
cap PreToolUse "$P" nojq
chk "[nojq] herramienta clasificada como prueba" 3 test; chk "[nojq] detalle" 5 "Corre las pruebas"; chk "[nojq] ruta con espacios" 8 "/Users/x/mi proyecto"

rm -rf "$H"
exit $fail
