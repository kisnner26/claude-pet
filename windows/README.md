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

el primer comando muestra los cambios; el segundo crea una copia de `~/.claude/settings.json` e instala los hooks sin duplicarlos ni borrar otros hooks. reinicia claude code. conserva la ruta del repositorio; para moverlo, desinstala primero y vuelve a instalar.

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

## alcance actual

todavía no incluye codex, pet-bus, fútbol, mission control ni bloqueo por cambios del workspace. esas funciones siguen disponibles en macos.
