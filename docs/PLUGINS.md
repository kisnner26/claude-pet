# plugins

Un plugin es una carpeta con un `plugin.json` y los scripts que declara. Añade **acciones** al menú de la barra y a la isla, **ajustes** propios en la ventana de ajustes y puede **reaccionar a eventos** (una sesión que termina, un permiso, una canción nueva). Un plugin puede ser un script de shell de cinco líneas.

[commitero](https://github.com/kisnner26/commitero) ya funciona así: `examples/plugins/commitero` es el plugin que lo lanza para el proyecto activo.

## en un minuto

```
mi-plugin/
├── plugin.json
└── saludar.sh        # chmod 755
```

```json
{
  "id": "mi-plugin",
  "name": "Mi plugin",
  "version": "1.0.0",
  "author": "tu nombre",
  "description": "Saluda desde la isla.",
  "permissions": ["notify"],
  "actions": [{ "id": "saludar", "title": "saludar", "run": "saludar.sh" }]
}
```

```sh
#!/bin/sh
printf '{"toast":"hola desde mi plugin"}\n'
```

Instálalo desde Ajustes → plugins → "instalar desde carpeta…" (o copia la carpeta a `~/.claude-pet/plugins/`). claude-pet te enseña lo que pide y no lo activa hasta que aceptas.

## manifiesto

| campo | obligatorio | descripción |
|---|---|---|
| `id` | sí | minúsculas, números y guiones, 2 a 40. **La carpeta debe llamarse igual** |
| `name`, `author`, `description` | sí | texto corto (40, 60 y 240 caracteres) |
| `version` | sí | `x.y.z` |
| `homepage` | no | enlace `https` |
| `minApp` | no | versión mínima de claude-pet, `x.y.z` |
| `permissions` | no | ver abajo |
| `actions` | no | hasta 12 |
| `settings` | no | hasta 20 |
| `events` | no | evento → script |

El esquema completo está en [plugin.schema.json](plugin.schema.json).

### permisos

Los permisos deciden lo que claude-pet **entrega** al plugin y los efectos que acepta **de vuelta**. El usuario los ve y los aprueba antes de activarlo, y si una versión nueva pide más, el plugin se para hasta que se aceptan.

| permiso | qué da |
|---|---|
| `project` | `CLAUDE_PET_PROJECT` (ruta) y `CLAUDE_PET_PROJECT_NAME` del proyecto activo |
| `events` | recibir eventos |
| `notify` | `{"toast": "..."}`: un aviso en la isla |
| `clipboard` | `{"copy": "..."}`: copiar texto |
| `open-url` | `{"open": "https://..."}`: abrir un enlace https |
| `music` | los eventos `music.track` (título y artista de la canción que suena) |

### acciones

```json
{ "id": "commitear", "title": "commitear este proyecto", "symbol": "arrow.triangle.branch",
  "run": "commitear.sh", "args": ["--rapido"], "needs": "project", "places": ["menu", "island"] }
```

`run` es una ruta **relativa** dentro del plugin. `needs: "project"` exige un proyecto activo (y el permiso `project`). `places` por defecto es solo `menu`. `symbol` es un nombre de SF Symbols.

### ajustes

```json
{ "key": "nombre", "type": "text", "title": "a quién saludar", "default": "mundo" }
{ "key": "grito", "type": "toggle", "title": "en mayúsculas" }
{ "key": "modo", "type": "choice", "title": "modo", "options": ["rápido", "lento"], "default": "rápido" }
```

Aparecen en la tarjeta del plugin y llegan al script como `CLAUDE_PET_SETTING_<CLAVE>` en mayúsculas (`CLAUDE_PET_SETTING_NOMBRE`). Los toggles valen `true` o `false`.

### eventos

```json
"permissions": ["events"],
"events": { "session.done": "anotar.sh" }
```

El evento llega por la entrada estándar como JSON y en `CLAUDE_PET_EVENT`.

| evento | campos |
|---|---|
| `session.done` | `agent` (claude o codex), `seconds` |
| `permission.asked` | `tool`, `project` |
| `permission.decided` | `tool`, `project`, `decision`, `source` |
| `music.track` | `title`, `artist`, `album`, `app` (exige el permiso `music`) |

Nunca llevan la ruta de un archivo ni el comando de un permiso. Todos incluyen `event`, `time`, `app` y `version`, y `project_path` y `project_name` solo con el permiso `project`. A un plugin se le avisa como mucho una vez cada 2 s por evento y de uno en uno.

## qué recibe un script

- Entorno **mínimo**: `PATH`, `HOME`, `LANG`, `TMPDIR` y las variables `CLAUDE_PET_*`. No hereda tus variables (claves, tokens).
- `CLAUDE_PET_PLUGIN_DIR`: su carpeta, que es de solo lectura para los demás.
- `CLAUDE_PET_DATA_DIR`: `~/.claude-pet/plugin-data/<id>`, donde guardar lo suyo.
- Directorio de trabajo: la carpeta del plugin.
- Plazo de **15 s** (luego se detiene) y **64 KB** de salida.

## qué puede devolver

La **última línea** de la salida, si es un objeto JSON, con las claves que el permiso permita:

```json
{"toast": "listo", "copy": "texto", "open": "https://example.com"}
```

Los avisos se recortan a 160 caracteres y solo se aceptan enlaces `https`. Si el script falla o se pasa de tiempo, la isla avisa.

**Escapa lo que no controlas** antes de meterlo en el JSON (nombres de proyecto, ajustes del usuario). Mira `examples/plugins/hola-mundo/saludar.sh`.

## seguridad: qué garantiza claude-pet y qué no

Garantiza:

- el plugin **no se activa solo** y el usuario aprueba sus permisos con una confirmación explícita;
- un ejecutable solo se lanza si, ya resueltos los enlaces simbólicos, está **dentro de la carpeta del plugin**, es un archivo normal, es del propio usuario, tiene permiso de ejecución y **nadie más puede escribirlo**;
- al instalar se rechazan enlaces simbólicos, más de 200 archivos o más de 5 MB, y se quitan los permisos de escritura de grupo y otros;
- el manifiesto se valida de forma estricta (rutas con `..` o absolutas, permisos o eventos desconocidos, acciones que piden más de lo declarado…);
- un plugin se registra siempre con el nombre de su carpeta, así que no puede hacerse pasar por otro;
- cada evento solo lleva los campos de la tabla y los efectos que pide el plugin se ignoran si no tiene el permiso.

**No** es una caja de arena. Un plugin es un proceso con **tus mismos privilegios**: si es malicioso, puede leer tus archivos o usar la red aunque no pida ningún permiso, porque los permisos controlan lo que claude-pet le da y acepta de vuelta, no lo que el sistema le deja hacer. Activa solo plugins de gente en la que confíes y léelos antes: son scripts.

## taller

Desde Ajustes → plugins → taller puedes instalar plugins de otros con un clic, y publicar el tuyo con un pull request: [workshop/README.md](../workshop/README.md). Cada paquete se verifica con sha256 y se instala desactivado.

## plugins incluidos

En `examples/plugins/` hay once plugins listos para copiar a `~/.claude-pet/plugins/`. Ninguno se activa solo: al activarlos desde Ajustes → plugins la app muestra los permisos y tú decides.

| plugin | qué hace | permisos |
|---|---|---|
| `git-estado` | rama, cambios y adelanto/atraso del proyecto; copiar rama; commit rápido | project, notify, clipboard |
| `github-rapido` | abre PR, pulls, issues o acciones del remoto (solo GitHub, sin credenciales en la URL) | project, notify, open-url |
| `diario-de-sesiones` | anota cada sesión terminada y resume el día | events, project, notify, clipboard |
| `puertos` | lista los puertos TCP en escucha con su proceso | notify, clipboard |
| `contexto-para-agentes` | copia un resumen en markdown del proyecto (sin contenido de archivos) | project, notify, clipboard |
| `abrir-en` | abre el proyecto en tu editor o en Terminal | project, notify |
| `todos-del-proyecto` | cuenta y copia los TODO/FIXME | project, notify, clipboard |

Se prueban con `sh tests/plugins-utiles.sh` (repos con nombres hostiles, remotos con token, rotación del diario).

## probar tu plugin

```bash
HOME=$(mktemp -d) ClaudePet --selftest-plugin-examples examples/plugins   # los ejemplos del repositorio
tests/plugins.sh                                                           # seguridad y ciclo de vida
```

Para depurar, ejecuta el script a mano con las variables que recibiría:

```bash
CLAUDE_PET_PROJECT=$PWD CLAUDE_PET_PROJECT_NAME=$(basename $PWD) CLAUDE_PET_SETTING_NOMBRE=Ana ./saludar.sh
```
