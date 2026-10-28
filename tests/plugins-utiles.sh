#!/bin/sh
# Los plugins incluidos en examples/plugins, ejecutados de verdad contra un repositorio temporal.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec python3 "$ROOT/tests/plugins_utiles.py" "$ROOT/examples/plugins"
