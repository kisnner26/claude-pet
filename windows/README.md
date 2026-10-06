# claude-pet para windows

frontend inicial para windows 10/11 con python y tkinter: mascota de claude, siete estados, ventana transparente siempre visible, arrastre, posición guardada, pausa de animaciones y hooks de claude code. no requiere paquetes de pip.

## ejecutar

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

## pruebas

```powershell
$env:PYTHONPATH = 'windows'
py -3 -m unittest discover -s windows/tests -v
```

github actions comprueba la tubería y el renderizado en windows. la experiencia visual en un escritorio real requiere validación manual.

## codex

codex tiene una ventana independiente con el avatar nube azul, sus siete estados y posición propia. aparece al recibir presencia y desaparece después de 25 segundos sin latidos. un adaptador puede enviar estados por el protocolo pet-bus v1 usando `windows/pet_ipc.py`.

```powershell
py -3 windows/bus_send.py thinking
py -3 windows/bus_send.py --hold idle
```

estos comandos sirven para probar la presencia; el repositorio no lee conversaciones ni detecta automáticamente la actividad de codex.

## alcance actual

todavía no incluye fútbol, mission control ni bloqueo por cambios del workspace. esas funciones siguen disponibles en macos. el transporte de windows usa una tubería autenticada; los clientes de sockets unix de macos necesitan un adaptador y no se conectan directamente.
