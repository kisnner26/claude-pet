# claude pet

windows: [instalación y detalles](windows/README.md). tiene la burbuja con la tarea, mission control, avisos de cambio y atasco, diff y el traspaso entre claude y codex. todavía no tiene el fútbol, el abrazo ni el panel de aspectos de codex, que son solo de macos.

dos mascotas pixel-art para macos, una por herramienta: claude code y codex. cada una es una ventana independiente que aparece cuando usas su herramienta y muestra en tiempo real lo que hace. swiftui puro, sin dependencias, todo local.

pagina: https://kisnner26.github.io/claude-pet/

![claude pet](docs/img/hero.png)

## que hace

- una mascota por herramienta: la de claude aparece si usas claude code (la app abierta o una sesion con hooks) y la de codex si usas codex (la app abierta o su adaptador en el pet bus). si usas una, sale una; si usas las dos, salen las dos. se desactiva desde el menu.
- son entidades separadas: cada una se arrastra por su cuenta, recuerda su posicion y su clic abre su app.
- el visor de codex muestra su estado real: reposo, pensando (puntos), herramienta (teclea), permiso (`!` naranja), listo (`^ ^`) y error (`x x`). al arrastrarlo alterna los pies; reaccionan entre si, se saludan, se aplauden y juegan al futbol aunque esten en lados distintos de la pantalla.
- codex tiene su propio panel: tres aspectos, gestos automáticos y acciones manuales (saludar, saludo formal, celebrar, curiosidad y patrullar). cuando claude no está en uso, el panel pasa a modo solo; cuando ambos trabajan cerca, activa modo dúo con paquetes visuales entre las ventanas.
- refleja el estado real de claude code: inactivo, iniciando, pensando, ejecutando herramienta, esperando tu aprobacion, listo y error.
- la burbuja de actividad sirve a las dos: cada una muestra estado y tarea desde su sesión local. el pet bus sigue llevando únicamente presencia; la tarea de codex se lee en esta mac y nunca se publica.
- una burbuja sobre la mascota dice la tarea exacta: "editando PetStore.swift", la descripcion del comando que corre, la tarea en curso.
- dos aspectos (bloque y clasico). el icono de la barra de menu cambia segun lo que usas: la silueta de claude, la de codex o las dos juntas.
- abrazo automatico: si las dos mascotas estan juntas (menos de 56 px entre ventanas), a la misma altura y ambas tranquilas (en reposo o recien terminadas), se abrazan: comparten suelo y cada una rodea con un brazo el cuerpo de la otra. se corta si una trabaja, pide permiso o falla, para no esconder su estado, y respeta "reducir movimiento".
- clic abre la app de claude. se arrastra por toda la pantalla.
- aviso de contexto: si el proyecto cambia mientras claude piensa, la burbuja avisa para que revises el diff. opcional (apagado por defecto): bloquear la siguiente herramienta hasta tu proximo mensaje.
- detector de atasco: avisa si claude o codex llevan 5 min pensando o 15 min en una herramienta sin ninguna actividad.
- cuando codex termina en un proyecto donde claude sigue trabajando, el menu ofrece abrir el diff.
- un aro alrededor de claude estima cuánto contexto queda antes de la compactación: azul con margen, ámbar al acercarse y rojo en zona crítica. al pulsarlo abre el relevo de sesión.
- hasta doce bloques rodean la mascota con los archivos que están cambiando. su tamaño refleja líneas tocadas; azul es modificado, verde staged, crema nuevo y coral conflicto. al pulsar abre el diff o el archivo nuevo.

## ocho sistemas visuales

en macos, ambas mascotas convierten señales reales de su propio proyecto y sesión en ocho capas compactas. nunca reutilizan los datos de la otra para aparentar paridad:

1. **medidor de contexto**: aro azul, ámbar o rojo según los tokens que quedan antes del umbral de compactación; clic abre el relevo.
2. **mapa vivo de archivos**: bloques por archivo, tamaño por líneas tocadas y estado por color.
3. **patas de evidencia**: la extensión web conecta la mascota con el texto que seleccionaste en la página.
4. **cazador visual**: la misma extensión marca controles sin nombre, imágenes sin `alt`, objetivos diminutos y contrastes probablemente bajos.
5. **telaraña de ramas**: mission control dibuja los worktrees reales; línea gruesa significa cambios, coral significa conflicto y línea discontinua significa worktree bloqueado.
6. **diff físico**: el primer clic sobre un archivo hace que la mascota tire de líneas reales del diff; el segundo abre el diff completo.
7. **capullo de contexto**: al entrar en presión ámbar o roja, varios hilos rodean la mascota y el aro permite preparar el relevo existente.
8. **radar entre aplicaciones**: una antena indica si una aprobación o error espera en claude o en la terminal; clic lleva a la aplicación correspondiente.

![sistemas visuales](docs/img/sistemas-visuales.png)

`web scout` funciona en chrome y edge sin servidor ni cuenta. desde el menú usa `mostrar web scout`, carga esa carpeta como extensión descomprimida, elige claude o codex y después pulsa `marcar selección` o `cazar problemas`. no guarda ni transmite el contenido de la página. las marcas siguen al contenido al desplazarte; usa los controles flotantes o las flechas para recorrer problemas y `esc` para cerrar.

## mission control

cinco funciones locales convierten la mascota en un tablero operativo:

- radar de colision: marca una posible colision cuando ambos llevan 10 s pensando o usando herramientas en un proyecto compartido. compara solo el nombre de la carpeta, ignora nombres genericos y tarda 5 s en apagarse; no pretende detectar ramas ni worktrees distintos con el mismo nombre.
- pulso git: muestra archivos afectados, staged, nuevos y conflictos sin leer su contenido. escanea al cambiar de proyecto, terminar, fallar, quedar inactivo o cada 15 s mientras trabaja; nunca ejecuta mas de un `git status` y conserva como maximo una solicitud pendiente.
- linea de tiempo: conserva en memoria los ultimos 16 cambios de estado de ambos agentes, con su hora.
- presupuesto de atencion: mide duracion, cantidad de herramientas usadas y las tres mas frecuentes. el ultimo resumen permanece visible al terminar.
- capsula de recuperacion: si el estado agregado permanece en error al menos 3 s, conserva la salud git del proyecto que fallo y ofrece abrir su diff. claude pet no distingue por si solo un `StopFailure` de otros errores agregados.

el pulso git usa `--no-optional-locks`, no permite prompts y corta cada proceso a los 10 s. limita la salida a 4 mb; ante ese limite o mas de 20 000 registros repite el estado sin archivos no rastreados y lo indica en el menu.

ninguno de estos datos cruza el pet bus ni se persiste entre ejecuciones.

![estados](docs/img/estados.png)

## traspaso entre claude y codex

la mascota reúne los flujos de ambos agentes en el menú `traspaso claude y codex`. las revisiones y los relevos se inician a pedido tuyo.

- **segunda opinion**: `pedir a codex que revise lo de claude` (y al reves). arma el diff sin commitear del proyecto, lista los archivos nuevos sin seguimiento y lo manda al otro agente en modo solo lectura: `codex exec --sandbox read-only` o `claude -p` con solo `Read`, `Grep` y `Glob`. el resultado queda en `~/.claude-pet/review/` (0600) y se abre solo. se puede cancelar y tiene tope de 10 minutos.
- **confirmacion antes de enviar**: antes de lanzar, un dialogo te dice que proyecto, cuantos KB y a que proveedor se manda el diff. si cancelas, no sale nada. el diff viaja por stdin, nunca por argumentos.
- **relevo de sesión**: abre `continuar en otro agente…`, elige la dirección y un chat local de codex o claude code. la app detecta la carpeta del proyecto y extrae los mensajes visibles del usuario y del asistente (no lee razonamiento ni salidas de herramientas). si la carpeta detectada no es la del código, puedes cambiarla. revisa el contexto y pulsa `guardar, copiar y abrir` para pegarlo en el otro agente. si no aparece el chat, usa el modo manual. añade rama, commit, archivos modificados y commits recientes; el archivo se guarda en `~/.claude-pet/handoff/` (`0700`, archivos `0600`) y vence a las 24 h. no reabre la sesión nativa en el otro proveedor: transfiere un extracto revisable del diálogo.
- **colision resuelta**: cuando el radar marca que los dos trabajan en el mismo proyecto, el menu ofrece `pausar a claude hasta mi proximo mensaje` (el hook deniega su siguiente herramienta; tu siguiente mensaje lo levanta) y `worktree aislado` para claude o codex (una carpeta hermana `proyecto-pet-<agente>` en una rama nueva `pet/...`; no borra ni mueve nada y deja la ruta en el portapapeles).
- las revisiones lanzadas por la mascota no cuentan como una sesion tuya: el hook las ignora (`CLAUDE_PET_REVIEW=1`).
- necesita tener instalado el CLI del agente que revisa; el menu lo deshabilita si no lo encuentra.

## pet bus y futbol

las mascotas se descubren entre si por sockets unix locales (`~/.claude-pet/bus/`, protocolo json v1). cada mascota es una ventana propia. si se ven las dos, estan a menos de 640 px y llevan unos segundos inactivas, juegan un partido breve: una capa transparente une a las dos y la pelota viaja de la ventana de codex a la de claude, sin mover ninguna. si ambas trabajan, la misma capa cambia a modo dúo y muestra paquetes azul/terracota, sin enviar datos nuevos. se cancela al instante si alguna trabaja, respeta "reducir movimiento" y se puede disparar a mano.

![futbol](docs/img/futbol.png)

![reacciones entre las dos mascotas](docs/img/companero.png)

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
- mission control mantiene rutas, rama, contadores, linea de tiempo y capsulas solo en memoria. ninguno se serializa en el pet bus.
- cada medidor de contexto lee únicamente los contadores de tokens de su transcript local activo. no conserva el contenido; claude permite ajustar el umbral con `CLAUDE_PET_COMPACTION_TOKENS` y codex usa la ventana registrada por su propia sesión.
- el hook no bloquea nada salvo que actives "bloquear herramientas si el proyecto cambia" o pidas "pausar a claude" ante una colision. la marca caduca a los 10 min y se borra con tu siguiente mensaje o al cerrar la sesion.
- el traspaso es la unica funcion que envia contenido a un tercero (el diff, al proveedor del agente que elijas), y solo despues de que lo confirmes en un dialogo.
- web scout se ejecuta dentro de la pestaña activa únicamente cuando pulsas una acción. no usa red, almacenamiento ni permisos sobre el historial.
- las cápsulas de relevo permanecen en esta mac hasta que vencen. crear una cápsula no la manda a ningún proveedor; solo se transmite cuando confirmas y pegas el contexto en el agente destino.

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
build/ClaudePet.app/Contents/MacOS/ClaudePet --selftest-mission  # radar, git, timeline, presupuesto, recuperacion
build/ClaudePet.app/Contents/MacOS/ClaudePet --selftest-handoff  # comandos de solo lectura, prompt, revision con agentes simulados, worktree
build/ClaudePet.app/Contents/MacOS/ClaudePet --selftest-relay    # cápsulas portables, prompt y permisos locales
build/ClaudePet.app/Contents/MacOS/ClaudePet --snapshot-systems docs/img/sistemas-visuales.png
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

## licencia

[MIT](LICENSE)
