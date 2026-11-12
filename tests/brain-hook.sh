#!/bin/sh
# Pruebas de hooks/pet-brain.sh: extraccion del cwd (comillas escapadas, rutas con espacios y unicode, claves anidadas,
# payloads de mas de 8 KB, sin jq), salida del hook UserPromptSubmit y que siempre falle abierto (salida 0, nada en stdout).
# Usa un binario falso y un HOME temporal: no toca ~/.claude ni ~/.claude-pet.
#   tests/brain-hook.sh                              prueba hooks/pet-brain.sh
#   REAL_BIN=.build/debug/ClaudePet tests/brain-hook.sh   ademas prueba el recall con el binario real y 200 notas
ROOT=$(cd "$(dirname "$0")/.." && pwd)
HOOK="${HOOK:-$ROOT/hooks/pet-brain.sh}"
[ -n "$REAL_BIN" ] && REAL_BIN="$(cd "$(dirname "$REAL_BIN")" && pwd)/$(basename "$REAL_BIN")"
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
[ -n "$FAKE_EMPTY" ] && exit 0
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

# --- recall (UserPromptSubmit) con el binario falso ---
rec() { OUT=$(printf '%s' "$1" | CLAUDE_PET_BIN="$FAKE" /bin/sh "$HOOK" recall 2>/dev/null); RC=$?; }
rec "$(jq -nc --arg c "$H/proj" '{cwd:$c,prompt:"como corro las pruebas?",hook_event_name:"UserPromptSubmit"}')"
ctx=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)
ev=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.hookEventName' 2>/dev/null)
[ "$RC" = 0 ] && [ "$ev" = UserPromptSubmit ] && printf '%s' "$ctx" | grep -qF 'ARGS=--brain recall --hook -- como corro las pruebas?' && ok "recall: JSON de hook valido con additionalContext y el prompt tras --" || bad "recall: salida [$OUT]"
printf '%s' "$ctx" | grep -qxF "PWD=$(canon "$H/proj")" && ok "recall: corre en el cwd del payload" || bad "recall: cwd"
rec "$(jq -nc --arg c "$H/proj" '{cwd:$c,prompt:"--max 99 \"comillas\" y $(rm -rf x) `ls`"}')"
printf '%s' "$OUT" | jq -e '.hookSpecificOutput.additionalContext | contains("--max 99")' >/dev/null 2>&1 && ok "recall: un prompt con flags, comillas y shell se pasa como texto, no se interpreta" || bad "recall: prompt hostil [$OUT]"
rec '{"cwd":"/tmp"}'
[ "$RC" = 0 ] && [ -z "$OUT" ] && ok "recall: sin prompt no imprime nada" || bad "recall sin prompt"
rec 'no es json'
[ "$RC" = 0 ] && [ -z "$OUT" ] && ok "recall: entrada rota no imprime nada y sale con 0" || bad "recall rota"
rec '{"prompt":42}'
[ "$RC" = 0 ] && [ -z "$OUT" ] && ok "recall: prompt que no es texto se ignora" || bad "recall prompt numerico"
OUT=$(printf '{"prompt":"hola mundo"}' | FAKE_EMPTY=1 CLAUDE_PET_BIN="$FAKE" /bin/sh "$HOOK" recall 2>/dev/null); RC=$?
printf '%s' "$OUT" | jq -e '.hookSpecificOutput.additionalContext | contains("PWD=")' >/dev/null 2>&1 && bad "recall: con la app muda no deberia haber contexto" || ok "recall: si la app no devuelve nada, no se inyecta nada"
OUT=$(printf '{"prompt":"hola mundo"}' | FAKE_RC=3 CLAUDE_PET_BIN="$FAKE" /bin/sh "$HOOK" recall 2>/dev/null); RC=$?
[ "$RC" = 0 ] && [ -z "$OUT" ] && ok "recall: la app falla, nada y salida 0" || bad "recall app falla rc=$RC out=[$OUT]"
OUT=$(printf '{"prompt":"hola mundo"}' | PATH="$NOJQ" CLAUDE_PET_BIN="$FAKE" /bin/sh "$HOOK" recall 2>/dev/null); RC=$?
[ "$RC" = 0 ] && [ -z "$OUT" ] && ok "recall: sin jq no hace nada (falla abierto)" || bad "recall sin jq"
OUT=$(printf '{"prompt":"hola"}' | CLAUDE_PET_BIN=/no/existe /bin/sh "$HOOK" recall 2>&1); RC=$?
[ "$RC" = 0 ] && [ -z "$OUT" ] && ok "recall: sin la app, nada y salida 0" || bad "recall sin app"

# --- recall con el binario real: interruptor, relevancia y tiempo con 200 notas ---
if [ -n "$REAL_BIN" ] && [ -x "$REAL_BIN" ]; then
  export CLAUDE_PET_BRAIN="$H/brain"; mkdir -p "$H/demo"
  "$REAL_BIN" --brain add tu cuidado "no usar la camara jamas en las apps" demo >/dev/null
  "$REAL_BIN" --brain add claude hecho "las pruebas se corren con tests/selftests.sh" demo >/dev/null
  P=$(jq -nc --arg c "$H/demo" '{cwd:$c,prompt:"como corro las pruebas?"}')
  OUT=$(printf '%s' "$P" | CLAUDE_PET_BIN="$REAL_BIN" /bin/sh "$HOOK" recall 2>/dev/null)
  [ -z "$OUT" ] && ok "real: con el interruptor apagado (defecto) no inyecta nada" || bad "real: apagado inyecto [$OUT]"
  "$REAL_BIN" --brain config smart on >/dev/null
  OUT=$(printf '%s' "$P" | CLAUDE_PET_BIN="$REAL_BIN" /bin/sh "$HOOK" recall 2>/dev/null)
  printf '%s' "$OUT" | jq -e '.hookSpecificOutput.additionalContext | contains("selftests.sh") and (contains("camara") | not)' >/dev/null 2>&1 && ok "real: activo, devuelve solo la nota relevante" || bad "real: activo [$OUT]"
  # 200 notas: tiempo del hook completo
  i=0; : > "$H/many.txt"
  while [ $i -lt 200 ]; do echo "nota $i sobre el modulo numero $i que usa cache y relay con puerto $((8000+i))"; i=$((i+1)); done > "$H/many.txt"
  mkdir -p "$H/brain"
  jq -Rn '[inputs] | to_entries | map({id: ("00000000-0000-4000-8000-" + (("000000000000" + (.key|tostring)) | .[-12:])), at: "2026-11-01T10:00:00Z", agent: "claude", kind: "hecho", text: .value})' < "$H/many.txt" > "$H/brain/big.json"
  mkdir -p "$H/big"; P=$(jq -nc --arg c "$H/big" '{cwd:$c,prompt:"que puerto usa el relay y el cache del modulo 150"}')
  t0=$(date +%s%N 2>/dev/null); case "$t0" in *N) t0=$(python3 -c 'import time;print(int(time.time()*1e9))');; esac
  OUT=$(printf '%s' "$P" | CLAUDE_PET_BIN="$REAL_BIN" /bin/sh "$HOOK" recall 2>/dev/null)
  t1=$(date +%s%N 2>/dev/null); case "$t1" in *N) t1=$(python3 -c 'import time;print(int(time.time()*1e9))');; esac
  ms=$(( (t1 - t0) / 1000000 ))
  echo "tiempo del hook con 200 notas (binario real, incluye arranque del proceso): ${ms} ms"
  [ "$ms" -lt 800 ] && ok "real: el hook con 200 notas tarda menos de 800 ms" || bad "real: ${ms} ms"
  printf '%s' "$OUT" | jq -e '.hookSpecificOutput.additionalContext | contains("<notas-del-proyecto")' >/dev/null 2>&1 && ok "real: con 200 notas devuelve un bloque valido" || bad "real: 200 notas [$OUT]"
fi

rm -rf "$H"
[ "$fail" = 0 ] && echo "TODO BIEN" || echo "HAY FALLOS"
exit "$fail"
