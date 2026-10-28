import json, os, shutil, socket, subprocess, sys, tempfile, time

PLUGINS = sys.argv[1]
fails = 0
def check(name, ok, extra=""):
    global fails
    if not ok:
        fails += 1
        print("FALLO", name, extra)

tmp = tempfile.mkdtemp(prefix="plugins-utiles-")
data = os.path.join(tmp, "datos"); os.makedirs(data)
# nombre hostil a proposito: comillas, apostrofe, acento y espacio
proj = os.path.join(tmp, 'mi "proyecto" it\'s ñ')
os.makedirs(proj)

def git(*a, cwd=None):
    return subprocess.run(["git", *a], cwd=cwd or proj, capture_output=True, text=True, env={**os.environ, "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t"}).stdout.strip()

def run(plugin, script, args=(), project=proj, settings=None, stdin=None, extra_env=None):
    env = {"PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": tmp, "CLAUDE_PET_DATA_DIR": data, "CLAUDE_PET_PLUGIN_DIR": os.path.join(PLUGINS, plugin)}
    if project is not None:
        env["CLAUDE_PET_PROJECT"] = project; env["CLAUDE_PET_PROJECT_NAME"] = os.path.basename(project)
    for k, v in (settings or {}).items(): env["CLAUDE_PET_SETTING_" + k.upper()] = v
    env.update(extra_env or {})
    p = subprocess.run(["/bin/sh", os.path.join(PLUGINS, plugin, script), *args], input=stdin, capture_output=True, text=True, env=env, cwd=os.path.join(PLUGINS, plugin), timeout=20)
    lines = [l for l in p.stdout.splitlines() if l.strip()]
    fx = {}
    if lines:
        try: fx = json.loads(lines[-1])
        except Exception as e: check(f"{plugin}/{script}: la ultima linea es JSON valido", False, f"{e}: {lines[-1][:120]!r}")
    return p, fx

# ---- repositorio de prueba
git("init", "-q", "-b", "main")
with open(os.path.join(proj, "app.py"), "w") as f: f.write("# TODO: separar esto\nprint('hola')\n# FIXME esto falla con \"comillas\" y \\ barras\n")
with open(os.path.join(proj, ".env"), "w") as f: f.write("API_KEY=SECRETO_XYZ_NO_DEBE_SALIR\n")
os.makedirs(os.path.join(proj, "src")); open(os.path.join(proj, "src", "a.js"), "w").write("// TODO cambiar\n")
git("add", "-A"); git("commit", "-q", "-m", 'primer commit con "comillas" y acento ñ')
remote = os.path.join(tmp, "remoto.git"); subprocess.run(["git", "init", "-q", "--bare", remote])
git("remote", "add", "origin", remote); git("push", "-q", "-u", "origin", "main")
open(os.path.join(proj, "nuevo.txt"), "w").write("x"); open(os.path.join(proj, "app.py"), "a").write("# otro\n")

# ---- git-estado
p, fx = run("git-estado", "estado.sh")
check("git-estado: rama, cambios y archivos sin seguir", "main" in fx.get("toast", "") and "2 cambios" in fx["toast"] and "1 sin seguir" in fx["toast"], fx)
git("add", "-A"); git("commit", "-q", "-m", "segundo")
p, fx = run("git-estado", "estado.sh")
check("git-estado: limpio y por subir", "limpio" in fx.get("toast", "") and "↑1" in fx["toast"], fx)
p, fx = run("git-estado", "rama.sh"); check("git-estado: copia la rama", fx.get("copy") == "main", fx)
p, fx = run("git-estado", "commit.sh"); check("git-estado: copia el ultimo commit", fx.get("copy", "").endswith(" segundo") and len(fx["copy"].split()[0]) >= 7, fx)
plain = os.path.join(tmp, "no-git"); os.makedirs(plain)
p, fx = run("git-estado", "estado.sh", project=plain); check("git-estado: carpeta sin git avisa", "no es un repositorio" in fx.get("toast", ""), fx)
p, fx = run("git-estado", "estado.sh", project=None); check("git-estado: sin proyecto avisa", "no hay un proyecto" in fx.get("toast", ""), fx)
empty = os.path.join(tmp, "vacio"); os.makedirs(empty); git("init", "-q", cwd=empty)
p, fx = run("git-estado", "commit.sh", project=empty); check("git-estado: repo sin commits", "todavía no tiene commits" in fx.get("toast", ""), fx)

# ---- github-rapido
def remote_of(url): git("remote", "set-url", "origin", url)
remote_of("https://usuario:ghp_TOKEN_SECRETO@github.com/kisnner26/claude-pet.git")
p, fx = run("github-rapido", "abrir.sh", ["pulls"])
check("github: pulls sin credenciales", fx.get("open") == "https://github.com/kisnner26/claude-pet/pulls" and "TOKEN" not in p.stdout, fx)
remote_of("git@github.com:kisnner26/claude-pet.git")
for kind, tail in [("issues", "issues"), ("actions", "actions")]:
    p, fx = run("github-rapido", "abrir.sh", [kind]); check(f"github: {kind} desde ssh", fx.get("open") == f"https://github.com/kisnner26/claude-pet/{tail}", fx)
git("checkout", "-q", "-b", "feature/x")
p, fx = run("github-rapido", "abrir.sh", ["pr"]); check("github: PR de la rama (enlace para crearlo, sin gh)", fx.get("open") == "https://github.com/kisnner26/claude-pet/compare/feature/x?expand=1", fx)
git("checkout", "-q", "-b", "x'y;z"); p, fx = run("github-rapido", "abrir.sh", ["pr"]); check("github: rama con caracteres raros se rechaza", "open" not in fx and "raros" in fx.get("toast", ""), fx)
git("checkout", "-q", "main")
remote_of("https://gitlab.com/a/b.git"); p, fx = run("github-rapido", "abrir.sh", ["pulls"]); check("github: remoto que no es GitHub", "open" not in fx and "no es de GitHub" in fx.get("toast", ""), fx)
remote_of("https://github.com.evil.com/a/b.git"); p, fx = run("github-rapido", "abrir.sh", ["pulls"]); check("github: dominio parecido se rechaza", "open" not in fx, fx)
remote_of("https://github.com/a/b/../../c.git"); p, fx = run("github-rapido", "abrir.sh", ["pulls"]); check("github: ruta con .. se rechaza", "open" not in fx, fx)
p, fx = run("github-rapido", "abrir.sh", ["borrar"]); check("github: accion desconocida", "open" not in fx, fx)
remote_of(remote)

# ---- diario-de-sesiones
p, fx = run("diario-de-sesiones", "hoy.sh"); check("diario: sin datos", "todavía no hay sesiones" in fx.get("toast", ""), fx)
ev = lambda agent, secs, name: json.dumps({"agent": agent, "app": "claude-pet", "event": "session.done", "project_name": name, "seconds": secs, "time": "2026-10-27T10:00:00Z", "version": "2.4.2"}, sort_keys=True, separators=(",", ":"))
run("diario-de-sesiones", "anotar.sh", stdin=ev("claude", "1800", "alfa"))
run("diario-de-sesiones", "anotar.sh", stdin=ev("claude", "600", "alfa"))
run("diario-de-sesiones", "anotar.sh", stdin=ev("codex", "x;rm -rf", "beta\tcon tab"))
run("diario-de-sesiones", "anotar.sh", stdin=ev("agente-raro\"", "60", "gamma"))
run("diario-de-sesiones", "anotar.sh", stdin='{ "agent" : "codex", "seconds" : 120, "project_name" : "delta" }')
rows = [l.split("\t") for l in open(os.path.join(data, "sesiones.tsv")).read().splitlines()]
check("diario: tolera espacios y segundos sin comillas", rows[-1][1:] == ["codex", "120", "delta"], rows[-1])
rows = rows[:-1]
check("diario: una linea por sesion con 4 columnas", len(rows) == 4 and all(len(r) == 4 for r in rows), rows)
check("diario: segundos no numericos pasan a 0 y agente raro a 'otro'", rows[2][2] == "0" and rows[3][1] == "otro", rows)
check("diario: el nombre sin tabuladores ni barras", rows[2][3] == "beta con tab", rows)
p, fx = run("diario-de-sesiones", "hoy.sh")
check("diario: resumen del dia", "5 sesiones" in fx.get("toast", "") and "43m" in fx["toast"] and "claude 2" in fx["toast"] and "alfa" in fx["toast"], fx)
check("diario: copia el detalle en markdown", fx.get("copy", "").startswith("## sesiones de hoy") and "claude" in fx["copy"], fx)
big = os.path.join(data, "sesiones.tsv")
with open(big, "a") as f: f.write(("2026-01-01 00:00:00\tclaude\t1\tx\n") * 6100)
run("diario-de-sesiones", "anotar.sh", stdin=ev("claude", "5", "alfa"))
check("diario: se conservan 5000 lineas", sum(1 for _ in open(big)) <= 5001)

# ---- puertos
srv = socket.socket(); srv.bind(("127.0.0.1", 0)); srv.listen(1); port = srv.getsockname()[1]
p, fx = run("puertos", "listar.sh")
check("puertos: encuentra el puerto abierto", str(port) in fx.get("toast", "") or str(port) in fx.get("copy", ""), (port, fx))
check("puertos: la lista copiada tiene pid", "pid " in fx.get("copy", ""), fx)
srv.close()

# ---- contexto-para-agentes
p, fx = run("contexto-para-agentes", "copiar.sh"); texto = fx.get("copy", "")
check("contexto: rama, commits y estructura", "rama: main" in texto and "## últimos commits" in texto and "## estructura" in texto and "src/: 1 archivos" in texto, texto)
check("contexto: nunca contenido de archivos ni secretos", "SECRETO_XYZ" not in p.stdout and "print('hola')" not in texto, texto)
check("contexto: acotado a 3000 bytes", len(texto.encode()) <= 3000)
check("contexto: sobrevive al nombre con comillas", "mi \"proyecto\"" in texto, texto)
p, fx = run("contexto-para-agentes", "copiar.sh", project=plain); check("contexto: sin git avisa", "no es un repositorio" in fx.get("toast", ""), fx)

# ---- abrir-en (no se lanzan apps: solo los caminos de rechazo)
p, fx = run("abrir-en", "editor.sh", project=None); check("abrir-en: sin proyecto", "no hay un proyecto" in fx.get("toast", ""), fx)
for malo in ["Cursor; touch /tmp/pwn-abrir-en", "$(touch /tmp/pwn-abrir-en)", "../../Applications/Calculator", "", "cursor"]:
    p, fx = run("abrir-en", "editor.sh", settings={"editor": malo} if malo else None, extra_env={} if malo else {"CLAUDE_PET_SETTING_EDITOR": "Inexistente"})
    check(f"abrir-en: el ajuste {malo!r} no se ejecuta", "no reconocido" in fx.get("toast", "") or (malo == "" and "no reconocido" in fx.get("toast", "")), fx)
check("abrir-en: no se ejecuto nada del ajuste hostil", not os.path.exists("/tmp/pwn-abrir-en"))

# ---- todos-del-proyecto
p, fx = run("todos-del-proyecto", "buscar.sh")
check("todos: cuenta pendientes y archivos", fx.get("toast") == "3 pendientes en 2 archivos", fx)
check("todos: copia archivo y linea", "app.py:1:" in fx.get("copy", "") and "src/a.js:1:" in fx["copy"] and "SECRETO" not in fx["copy"], fx)
check("todos: barras y comillas escapadas", 'comillas' in fx.get("copy", "") and "\\" in fx.get("copy", ""), fx)
p, fx = run("todos-del-proyecto", "buscar.sh", project=empty); check("todos: repo sin TODO", "ningún TODO" in fx.get("toast", ""), fx)

# ---- ninguno devuelve basura por stderr ni tarda
shutil.rmtree(tmp, ignore_errors=True)
print("PLUGINS UTILES OK" if fails == 0 else f"PLUGINS UTILES {fails} FALLOS")
sys.exit(0 if fails == 0 else 1)
