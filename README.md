# claude pet

mascota pixel-art para macos que vive en la barra de menu y muestra en tiempo real lo que hace claude code: en desktop y en terminal. swiftui puro, sin dependencias, todo local.

![claude pet](docs/img/hero.png)

## que hace

- refleja el estado real de claude code: inactivo, iniciando, pensando, ejecutando herramienta, esperando tu aprobacion, listo y error.
- una burbuja sobre la mascota dice la tarea exacta: "editando PetStore.swift", la descripcion del comando que corre, la tarea en curso.
- dos aspectos (bloque y clasico) y un icono propio en la barra de menu.
- clic abre la app de claude. se arrastra por toda la pantalla.
- aviso de contexto: si el proyecto cambia mientras claude piensa, la burbuja avisa para que revises el diff. opcional (apagado por defecto): bloquear la siguiente herramienta hasta tu proximo mensaje.
- detector de atasco: avisa si claude o codex llevan 5 min pensando o 15 min en una herramienta sin ninguna actividad.
- cuando codex termina en un proyecto donde claude sigue trabajando, el menu ofrece abrir el diff.

![estados](docs/img/estados.png)

## pet bus y futbol

las mascotas se descubren entre si por sockets unix locales (`~/.claude-pet/bus/`, protocolo json v1). si la de codex esta presente, claude pet muestra su avatar y, si ambos llevan unos segundos inactivos, juegan un partido breve. se cancela al instante si alguno trabaja, respeta "reducir movimiento" y se puede disparar a mano.

![futbol](docs/img/futbol.png)

protocolo y guia para el adaptador de codex en [docs/PET-BUS.md](docs/PET-BUS.md).

## como funciona

```
claude code --hook--> hooks/pet-hook.sh --socket unix 0600--> ClaudePet.app
```

el script traduce 10 eventos de hook a un estado y lo manda por un socket local. no hay red, ni credenciales, ni telemetria.

## privacidad

- solo sockets unix del mismo usuario (carpeta 0700, socket 0600).
- el detalle de la burbuja es local y nunca sale por el pet bus: descripcion del comando, nombre del archivo (no la ruta), programa de un comando (nunca sus argumentos), host de una url y tu ultimo mensaje.
- se apaga desde el menu. el nombre del proyecto no se comparte con otras mascotas salvo que lo actives.
- el detector de contexto solo calcula una huella local de nombres, fechas y tamanos de archivos; no lee contenido. ignora `.git`, dependencias, builds y logs.
- la ruta del proyecto llega a la app por el socket local (para la huella y el diff). no se muestra, no se escribe a disco y no cruza el pet bus: ahi solo va el nombre de la carpeta, y solo si lo activas.
- el hook no bloquea nada salvo que actives "bloquear herramientas si el proyecto cambia". la marca caduca a los 10 min y se borra con tu siguiente mensaje o al cerrar la sesion.

## instalacion

requiere macos 13+, command line tools y `jq`.

```sh
./build.sh                     # compila build/ClaudePet.app (firma ad-hoc)
open build/ClaudePet.app
./install-hooks.sh --dry-run   # muestra el diff exacto de ~/.claude/settings.json
./install-hooks.sh             # lo aplica tras pedir confirmacion, con copia de respaldo
```

abre una sesion nueva de claude code para que cargue los hooks. no pide permisos del sistema: escribe solo en `~/.claude-pet/` y, al instalar, fusiona sus hooks en `~/.claude/settings.json` sin tocar los tuyos. si macos bloquea la app (firma ad-hoc): clic derecho, abrir.

## pruebas

```sh
tests/manual.sh              # recorre cada estado
tests/bridge-capture.sh      # comprueba que el hook no filtra contenido
tests/hook-guard.sh          # el hook no bloquea por defecto; bloqueo opt-in, caducidad, clasificacion de pruebas
build/ClaudePet.app/Contents/MacOS/ClaudePet --selftest-safety   # huella, monitor, diff grande, parseo
tests/bus.sh                 # pet bus con un codex simulado
tests/football.sh            # reglas del partido y escenarios visuales
build/ClaudePet.app/Contents/MacOS/ClaudePet --trigger football   # greet | cheer | concern
```

las imagenes de este readme se generan con el propio codigo de dibujo de la app (`ClaudePet --snapshot-hero docs/img`); no son capturas de pantalla.

## desinstalar

```sh
./install-hooks.sh --uninstall   # quita solo estos hooks
pkill -x ClaudePet
rm -rf build ~/.claude-pet
```

## inspiracion

la idea de una mascota flotante conectada a claude code viene de [ClaudeHub](https://github.com/NormanSMA/ClaudeHub) de NormanSMA, un monitor local de tokens con una mascota llamada chispa. claude pet no usa su codigo: es otro proyecto, en swift, centrado en el estado y la tarea en curso.
