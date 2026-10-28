#!/usr/bin/env python3
"""Taller de claude-pet: valida los plugins y genera workshop/index.json y los paquetes .zip.

  python3 workshop/build.py          genera paquetes e indice
  python3 workshop/build.py --check  solo valida (lo usa la CI en cada pull request); falla si el indice esta desactualizado

Fuentes: workshop/plugins/* (comunidad) y examples/plugins/* (oficiales). Los paquetes son deterministas:
el mismo plugin produce siempre el mismo zip y el mismo sha256.
"""
import hashlib, json, os, re, stat, sys, zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCES = [("workshop/plugins", False), ("examples/plugins", True)]
BASE = "https://raw.githubusercontent.com/kisnner26/claude-pet/main/workshop/packages/"
PERMS = {"project", "events", "clipboard", "notify", "open-url", "music"}
ID_RE = re.compile(r"^[a-z0-9][a-z0-9-]{1,39}$")
VER_RE = re.compile(r"^\d+\.\d+\.\d+$")
MAX_BYTES, MAX_FILES = 2 * 1024 * 1024, 200
errors = []

def fail(pid, msg): errors.append(f"{pid}: {msg}")

def files_of(d):
    out = []
    for base, dirs, names in os.walk(d):
        dirs.sort()
        for n in sorted(names):
            out.append(os.path.join(base, n))
    return out

def validate(d, dirname):
    mp = os.path.join(d, "plugin.json")
    if not os.path.isfile(mp): fail(dirname, "falta plugin.json"); return None
    try: m = json.load(open(mp))
    except Exception as e: fail(dirname, f"plugin.json no es JSON valido ({e})"); return None
    for k in ("id", "name", "version", "author", "description"):
        if not isinstance(m.get(k), str) or not m[k].strip(): fail(dirname, f"falta «{k}»")
    if m.get("id") != dirname: fail(dirname, f"el id «{m.get('id')}» debe coincidir con el nombre de la carpeta")
    if not ID_RE.match(str(m.get("id", ""))): fail(dirname, "id invalido (minusculas, numeros y guiones, 2-40)")
    if not VER_RE.match(str(m.get("version", ""))): fail(dirname, "la version debe ser x.y.z")
    perms = m.get("permissions", [])
    if not isinstance(perms, list) or any(p not in PERMS for p in perms): fail(dirname, f"permisos desconocidos: {perms}")
    if len(m.get("description", "")) > 400: fail(dirname, "descripcion de mas de 400 caracteres")
    fs = files_of(d)
    if len(fs) > MAX_FILES or sum(os.path.getsize(f) for f in fs if os.path.isfile(f)) > MAX_BYTES: fail(dirname, "demasiado grande (2 MB / 200 archivos)")
    for base, dirs, names in os.walk(d):
        for n in dirs + names:
            if os.path.islink(os.path.join(base, n)): fail(dirname, f"enlace simbolico no permitido: {n}")
    runs = [a.get("run") for a in m.get("actions", [])] + list(m.get("events", {}).values())
    for r in runs:
        p = os.path.join(d, r or "")
        if not r or r.startswith("/") or ".." in r.split("/") or not os.path.isfile(p): fail(dirname, f"ejecutable inexistente o fuera del plugin: {r}")
        elif not os.access(p, os.X_OK): fail(dirname, f"{r} no es ejecutable (chmod +x)")
    return m

def package(d, pid, version):
    out = os.path.join(ROOT, "workshop", "packages", f"{pid}-{version}.zip")
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for f in files_of(d):
            rel = os.path.join(pid, os.path.relpath(f, d))
            info = zipfile.ZipInfo(rel, (1980, 1, 1, 0, 0, 0))
            mode = 0o755 if os.access(f, os.X_OK) else 0o644
            info.external_attr = (stat.S_IFREG | mode) << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            z.writestr(info, open(f, "rb").read())
    data = open(out, "rb").read()
    return out, hashlib.sha256(data).hexdigest(), len(data)

def main():
    check = "--check" in sys.argv
    entries, seen = [], {}
    for rel, official in SOURCES:
        base = os.path.join(ROOT, rel)
        if not os.path.isdir(base): continue
        for name in sorted(os.listdir(base)):
            d = os.path.join(base, name)
            if not os.path.isdir(d): continue
            m = validate(d, name)
            if not m: continue
            if m["id"] in seen: fail(name, f"id repetido (ya esta en {seen[m['id']]})"); continue
            seen[m["id"]] = rel
            if errors: continue
            out, sha, size = package(d, m["id"], m["version"])
            e = {"id": m["id"], "name": m["name"], "version": m["version"], "author": m["author"], "description": m["description"],
                 "permissions": m.get("permissions", []), "official": official, "url": BASE + os.path.basename(out), "sha256": sha, "size": size}
            if m.get("homepage"): e["homepage"] = m["homepage"]
            entries.append(e)
    if errors:
        print("\n".join("ERROR " + e for e in errors)); sys.exit(1)
    entries.sort(key=lambda e: (not e["official"], e["id"]))
    text = json.dumps({"schema": 1, "plugins": entries}, indent=2, ensure_ascii=False) + "\n"
    path = os.path.join(ROOT, "workshop", "index.json")
    if check:
        if not os.path.exists(path) or open(path).read() != text:
            print("ERROR index.json esta desactualizado: ejecuta python3 workshop/build.py y sube el resultado"); sys.exit(1)
        print(f"OK {len(entries)} plugins validos"); return
    open(path, "w").write(text)
    keep = {os.path.basename(e["url"]) for e in entries}
    for f in os.listdir(os.path.join(ROOT, "workshop", "packages")):
        if f.endswith(".zip") and f not in keep: os.remove(os.path.join(ROOT, "workshop", "packages", f))
    print(f"OK {len(entries)} plugins en workshop/index.json")

main()
