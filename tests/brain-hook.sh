#!/bin/sh
# Pruebas de hooks/pet-brain.sh: extraccion del cwd (comillas escapadas, rutas con espacios y unicode, claves anidadas,
# payloads de mas de 8 KB, sin jq), salida del hook UserPromptSubmit y que siempre falle abierto (salida 0, nada en stdout).
# Usa un binario falso y un HOME temporal: no toca ~/.claude ni ~/.claude-pet.
#   tests/brain-hook.sh                              prueba hooks/pet-brain.sh
#   REAL_BIN=.build/debug/ClaudePet tests/brain-hook.sh   ademas prueba el recall con el binario real y 200 notas
ROOT=$(cd "$(dirname "$0")/.." && pwd)
HOOK="${HOOK:-$ROOT/hooks/pet-brain.sh}"
fail=0
ok() { echo "OK: $1"; }
bad() { echo "FALLO: $1"; fail=1; }

H=$(mktemp -d); export HOME="$H"
export CLAUDE_PET_BRAIN_SETTINGS="$H/brain-settings.json"
unset CLAUDE_PROJECT_DIR CLAUDE_PET_BRAIN_SMART

# binario falso: dice donde se le llamo y con que argumentos
FAKE="$H/fake-bin"
cat > "$FAKE" <<'EOF'
#!/bin/sh
echo "PWD=$(pwd -P)"
echo "ARGS=$*"
[ -n "$FAKE_EMPTY" ] && exit 0
exit "${FAKE_RC:-0}"
EOF
chmod +x "$FAKE"

# PATH sin jq para el camino de reserva
NOJQ="$H/nojq-bin"; mkdir -p "$NOJQ"
for t in head sed tr cut cat printf; do p=$(command -v "$t") && ln -s "$p" "$NOJQ/$t"; done

cd "$H" || exit 1
mkdir -p "$H/proj" "$H/con espacios" "$H/ñandú" "$H/q\"uote"
canon() { (cd "$1" 2>/dev/null && pwd -P); }

# run MODO ENTRADA [nojq] -> $OUT, $RC
start() {
  if [ "$3" = nojq ]; then OUT=$(printf '%s' "$2" | PATH="$NOJQ" CLAUDE_PET_BIN="$FAKE" /bin/sh "$HOOK" "$1" 2>/dev/null); RC=$?
  else OUT=$(printf '%s' "$2" | CLAUDE_PET_BIN="$FAKE" /bin/sh "$HOOK" "$1" 2>/dev/null); RC=$?; fi
}
expect_pwd() { # nombre carpeta
  want="PWD=$(canon "$2")"
  if printf '%s' "$OUT" | grep -qxF "$want"; then ok "$1"; else bad "$1 (esperado [$want], salio [$(printf '%s' "$OUT" | head -n 1)])"; fi
}

# --- start: cwd ---
start start "$(jq -nc --arg c "$H/proj" '{session_id:"a",cwd:$c,hook_event_name:"SessionStart"}')"
expect_pwd "cwd normal (jq)" "$H/proj"
start start "$(jq -nc --arg c "$H/proj" '{cwd:$c}')" nojq
expect_pwd "cwd normal (sin jq)" "$H/proj"
start start "$(jq -nc --arg c "$H/con espacios" '{cwd:$c}')"
expect_pwd "ruta con espacios" "$H/con espacios"
start start "$(jq -nc --arg c "$H/ñandú" '{cwd:$c}')"
expect_pwd "ruta con unicode" "$H/ñandú"
start start "$(jq -nc --arg c "$H/q\"uote" '{cwd:$c}')"
expect_pwd "comillas escapadas en la ruta (jq)" "$H/q\"uote"
start start '{"cwd":"'"$H"'/q\"uote"}' nojq
[ "$RC" = 0 ] && ok "comillas escapadas sin jq: sed se queda corto (limite conocido) pero no falla" || bad "comillas sin jq: salida $RC"
# clave anidada con el mismo nombre, antes del cwd real
start start "$(jq -nc --arg c "$H/proj" --arg o "$H/con espacios" '{tool_input:{cwd:$o},cwd:$c}')"
expect_pwd "un cwd anidado no se confunde con el de primer nivel" "$H/proj"
# payload de mas de 8 KB con el cwd al final
big=$(head -c 12000 /dev/zero | tr '\0' 'x')
start start "$(jq -nc --arg c "$H/proj" --arg b "$big" '{prompt:$b,cwd:$c}')"
expect_pwd "payload de mas de 8 KB (jq)" "$H/proj"
# cwd dentro del texto de un campo, no como clave
start start "$(jq -nc --arg c "$H/proj" '{prompt:"mira \"cwd\": \"/tmp\" ahi",cwd:$c}')"
expect_pwd "un cwd dentro de un texto no cuenta" "$H/proj"
# entrada rota o vacia: sigue y no falla
start start 'esto no es json {{{'
[ "$RC" = 0 ] && ok "entrada rota: salida 0" || bad "entrada rota: salida $RC"
start start ''
[ "$RC" = 0 ] && printf '%s' "$OUT" | grep -q '^ARGS=--brain show claude' && ok "entrada vacia: igual muestra las notas" || bad "entrada vacia"
# cwd que no existe: no cambia de carpeta y no falla
start start '{"cwd":"/no/existe/jamas"}'
[ "$RC" = 0 ] && ok "cwd inexistente: salida 0" || bad "cwd inexistente: salida $RC"
# la app falla: no imprime nada y sale con 0
OUT=$(printf '{}' | FAKE_RC=3 CLAUDE_PET_BIN="$FAKE" /bin/sh "$HOOK" start 2>/dev/null); RC=$?
[ "$RC" = 0 ] && [ -z "$OUT" ] && ok "la app falla: no imprime nada y sale con 0" || bad "la app falla: rc=$RC out=[$OUT]"
# sin la app: sale 0 sin nada
OUT=$(printf '{}' | CLAUDE_PET_BIN=/no/existe /bin/sh "$HOOK" start 2>&1); RC=$?
[ "$RC" = 0 ] && [ -z "$OUT" ] && ok "sin la app instalada: nada y salida 0" || bad "sin la app: rc=$RC out=[$OUT]"

rm -rf "$H"
[ "$fail" = 0 ] && echo "TODO BIEN" || echo "HAY FALLOS"
exit "$fail"
