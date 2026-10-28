#!/bin/sh
# Taller: el catalogo esta al dia, se instala entero y los paquetes manipulados se rechazan.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${1:-$ROOT/build/ClaudePet.app/Contents/MacOS/ClaudePet}"
[ -x "$BIN" ] || BIN="$ROOT/.build/debug/ClaudePet"
python3 "$ROOT/workshop/build.py" --check || exit 1
EVIL=$(mktemp -d "${TMPDIR:-/tmp}/claudepet-evil.XXXXXX") || exit 1
trap 'rm -rf "$EVIL"' EXIT INT TERM
python3 - "$EVIL" <<'PY'
import sys, zipfile, os, stat
d = sys.argv[1]
def manifest(i, perms): return '{"id":"%s","name":"%s","version":"1.0.0","author":"x","description":"x","permissions":%s}' % (i, i, perms)
def build(name, plugin_id, perms="[]", extra=None, link=None):
    with zipfile.ZipFile(os.path.join(d, name), "w") as z:
        z.writestr(plugin_id + "/plugin.json", manifest(plugin_id, perms))
        for n, data in (extra or []): z.writestr(n, data)
        if link:
            i = zipfile.ZipInfo(plugin_id + "/enlace"); i.external_attr = (stat.S_IFLNK | 0o777) << 16
            z.writestr(i, link)
build("buen.zip", "buen")
build("permisos.zip", "permisos", '["clipboard"]')
build("id.zip", "no-es-otro-id")
build("simbolico.zip", "simbolico", link="/etc/passwd")
build("slip.zip", "slip", extra=[("../../escapada-workshop.txt", "x"), ("slip/../../escapada-workshop.txt", "x")])
PY
"$BIN" --selftest-workshop "$ROOT/workshop" "$EVIL"
