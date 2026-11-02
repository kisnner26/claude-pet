#!/bin/sh
# Corre todas las pruebas internas (--selftest-*) de ClaudePet y dice cuales fallan.
#   tests/selftests.sh              usa .build/debug/ClaudePet
#   tests/selftests.sh RUTA         usa otro binario
#   WITH_NET=1 tests/selftests.sh   incluye las que necesitan internet
#   ONLY="brain memory" tests/selftests.sh   solo esas
# Sale con 0 si todo pasa y con 1 si algo falla o se queda colgado (cada prueba tiene 90 s).
set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BIN=${1:-"$ROOT/.build/debug/ClaudePet"}
[ -x "$BIN" ] || { echo "compila primero con swift build" >&2; exit 1; }

# claudwler necesita internet (solo con WITH_NET=1); workshop recibe paquetes manipulados y los fabrica tests/workshop.sh
SKIP=" claudwler workshop "
[ "${WITH_NET:-0}" = "1" ] && SKIP=" workshop "
# algunas pruebas reciben una carpeta y las rutas son relativas a la raiz del repositorio
cd "$ROOT" || exit 1
# usan el llavero o carpetas del usuario y no funcionan con un HOME vacio
REAL_HOME=" quest "
extra_args() {
  case "$1" in
    plugin-examples) echo "$ROOT/examples/plugins" ;;
    *) ;;
  esac
}

NAMES=${ONLY:-$(grep -o '"--selftest-[a-z0-9-]*"' "$ROOT/Sources/ClaudePet/ClaudePetApp.swift" | tr -d '"' | sed 's/^--selftest-//' | sort -u)}
WORK=$(mktemp -d "${TMPDIR:-/tmp}/claudepet-selftests.XXXXXX") || exit 1
trap 'rm -rf "$WORK"' EXIT INT TERM

pass=0; fail=0; failed=""
for name in $NAMES; do
  case "$SKIP" in *" $name "*) echo "salto   $name"; continue ;; esac
  # un HOME nuevo por prueba: ninguna toca tus notas, tu memoria ni tus ajustes, y ninguna hereda el estado de la anterior
  TMP_HOME="$WORK/$name"; mkdir -p "$TMP_HOME"
  case "$REAL_HOME" in *" $name "*) RUN_HOME="$HOME" ;; *) RUN_HOME="$TMP_HOME" ;; esac
  HOME="$RUN_HOME" "$BIN" "--selftest-$name" $(extra_args "$name") >"$TMP_HOME/out.txt" 2>&1 &
  pid=$!
  waited=0
  while kill -0 "$pid" 2>/dev/null && [ "$waited" -lt 90 ]; do sleep 1; waited=$((waited + 1)); done
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
    echo "COLGADA $name"; fail=$((fail + 1)); failed="$failed $name"
    continue
  fi
  if wait "$pid"; then pass=$((pass + 1)); echo "ok      $name"
  else fail=$((fail + 1)); failed="$failed $name"; echo "FALLA   $name"; grep -E "^FAIL" "$TMP_HOME/out.txt" | head -5 | sed 's/^/          /'; fi
done

echo
echo "$pass pasan, $fail fallan"
[ "$fail" -eq 0 ] || { echo "revisa:$failed"; exit 1; }
