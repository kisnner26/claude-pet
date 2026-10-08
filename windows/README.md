# claude-pet para windows

frontend para windows 10/11 con python y tkinter: mascota de claude, siete estados, ventana transparente siempre visible, arrastre, posición guardada, pausa de animaciones y hooks de claude code. no requiere paquetes de pip.

## qué incluye

- burbuja con la tarea exacta ("Editando store.py", "Ejecutando pruebas (pytest)"), con el mismo texto que en macos. del comando solo se conserva el programa, nunca los argumentos; de una url, solo el host.
- mission control (menú, clic derecho): salud git, línea de tiempo de los últimos 16 cambios, presupuesto de atención, radar de colisión entre claude y codex y cápsula de recuperación si una sesión falla.
- avisos en la burbuja si el proyecto cambia mientras claude piensa o si algo lleva 5 o 15 minutos sin actividad. el bloqueo de herramientas es opcional y está apagado por defecto.
- abrir el diff del proyecto desde el menú.
- traspaso entre claude y codex: revisión cruzada en solo lectura (con confirmación antes de enviar el diff), pausar a claude y worktree aislado ante una colisión.

todavía no tiene el fútbol, el abrazo, el modo dúo ni el panel de aspectos de codex.

## ejecutar

el workflow [windows](https://github.com/kisnner26/claude-pet/actions/workflows/windows.yml) genera el artefacto `claude-pet-windows`. extrae el zip completo y abre `claude-pet/claude-pet.exe`. este paquete incluye python y tkinter; no requiere instalarlos. conserva todas las carpetas del paquete juntas.

para conectar claude code desde el paquete:

```powershell
.\install-hooks\install-hooks.exe
.\install-hooks\install-hooks.exe --apply
```

para retirarlo usa `--uninstall --apply`. los ejecutables todavía no tienen firma digital. la compilación verifica el arranque de ambas mascotas, el hook empaquetado y la instalación y retirada en un archivo temporal.

## ejecutar desde el código

instala python 3.12 o posterior desde python.org con tkinter y el lanzador `py`. clona o descarga este repositorio en una carpeta permanente y abre `windows/start.cmd`.

clic derecho abre el menú; escape cierra la mascota. la transparencia se activa solo en windows. en macos se puede probar con fondo visible.

## conectar claude code

desde la carpeta del repositorio:

```powershell
py -3 windows/install_hooks.py
py -3 windows/install_hooks.py --apply
```

el primer comando muestra los cambios; el segundo crea una copia de `~/.claude/settings.json` e instala los hooks sin duplicarlos ni borrar otros hooks. usa una versión actual de claude code con [hooks en formato ejecutable y argumentos](https://code.claude.com/docs/en/hooks#exec-form-and-shell-form), para que las rutas con espacios no dependan de bash o powershell. reinicia claude code. conserva la ruta del repositorio; para moverlo, desinstala primero y vuelve a instalar.

```powershell
py -3 windows/install_hooks.py --uninstall --apply
```

los eventos viajan por una tubería local autenticada, sin puertos tcp. la clave y preferencias están en `~/.claude-pet`, con permisos restringidos al usuario. el hook limita la conexión a un segundo y no bloquea herramientas si la mascota está cerrada. no guarda prompts ni argumentos de comandos.

## traspaso

`pedir a codex que revise lo de claude` (y al revés) necesita tener instalado el CLI del agente que revisa. el menú lo busca en el `PATH` y en las carpetas habituales (`%APPDATA%\npm`, `~/.local/bin`). antes de enviar, un diálogo indica el proyecto, el tamaño y el proveedor; si cancelas no sale nada. el resultado queda en `~/.claude-pet/review/` y se abre solo.

## pruebas

```powershell
$env:PYTHONPATH = 'windows'
py -3 -m unittest discover -s windows/tests -v
```

github actions comprueba la tubería y el renderizado en windows. la experiencia visual en un escritorio real requiere validación manual.

para generar el paquete en windows, instala `pyinstaller==6.22.3` y ejecuta `py -3 windows/build.py`. el resultado queda en `build/windows/claude-pet-windows.zip`.

## codex

codex tiene una ventana independiente con el avatar nube azul, sus siete estados y posición propia. aparece al recibir presencia y desaparece después de 25 segundos sin latidos. un adaptador puede enviar estados por el protocolo pet-bus v1 usando `windows/pet_ipc.py`.

```powershell
py -3 windows/bus_send.py thinking
py -3 windows/bus_send.py --hold idle
```

estos comandos sirven para probar la presencia; el repositorio no lee conversaciones ni detecta automáticamente la actividad de codex. con `--project <carpeta>` se publica solo el nombre de la carpeta (nunca la ruta), lo que permite al radar detectar que claude y codex trabajan en el mismo proyecto.

el paquete también incluye el cliente ejecutable, para conectar un adaptador sin instalar python:

```powershell
.\pet-bus\pet-bus.exe thinking
.\pet-bus\pet-bus.exe --hold idle
```

un adaptador puede invocarlo cuando cambie el estado de codex. `--hold` envía latidos cada diez segundos hasta pulsar ctrl+c; sin latidos, la presencia dura hasta 25 segundos.

## alcance actual

todavía no incluye fútbol, mission control ni bloqueo por cambios del workspace. esas funciones siguen disponibles en macos. el transporte de windows usa una tubería autenticada; los clientes de sockets unix de macos necesitan un adaptador y no se conectan directamente.
