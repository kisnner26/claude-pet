# ahorro de tokens

Medir cuánto se gasta, ver dónde se va y tener herramientas para gastar menos. Todo local. **No hay forma de ahorrar tokens tocando la API ni la caché del modelo desde claude pet**: lo que hace es medir, aconsejar, generar buen contexto de proyecto, acortar lo que Claude escribe (opt-in) y comprimir logs que tú le pasas. No promete porcentajes de ahorro.

Página: ajustes, **ahorro** (`ClaudePet --open-settings ahorro`).

## qué mide

Lee los transcripts de `~/.claude/projects/**.jsonl` (respeta `CLAUDE_CONFIG_DIR`), solo el bloque `usage` de cada mensaje:

| contador | significado |
|---|---|
| entrada nueva | `input_tokens`: se paga entero |
| caché leída | `cache_read_input_tokens` |
| caché creada | `cache_creation_input_tokens` |
| salida | `output_tokens` |
| aciertos de caché | caché leída ÷ (entrada nueva + leída + creada) |

Por sesión y por proyecto (el proyecto es el último componente de la carpeta de trabajo). Un mensaje que Claude escribe en varias líneas se cuenta una vez. **Sin precios**: cambian; se enseñan tokens y porcentajes.

Límites: solo los 40 transcripts más recientes de los últimos 14 días; de un transcript de más de 48 MB se lee la parte final y la sesión se marca «parcial». La lectura es incremental (recuerda hasta dónde leyó cada archivo), ocurre fuera del hilo principal y solo al abrir la página o pulsar «actualizar»: no hay temporizador. No se escribe nada a disco, no se guarda contenido de mensajes y el diagnóstico solo registra códigos de error.

## auditoría de CLAUDE.md

Por proyecto con carpeta existente: si **falta**, si es **largo** (≈2000 tokens) o **muy largo** (≈4000; se estima a 3,5 caracteres por token, es una aproximación) y si tiene **secciones que envejecen** (pendientes, estado actual, WIP, changelog…) o fechas de hace más de 90 días.

## borrador de CLAUDE.md

```
ClaudePet --project-summary [carpeta]            # a stdout
ClaudePet --project-summary [carpeta] --write    # a CLAUDE.md.borrador
```

Local y extractivo, sin modelo: lenguajes por número de archivos, estructura de carpetas, comandos de `Package.swift`, `package.json`, `Makefile`, `Cargo.toml`, `go.mod`, `pytest` y `tests/*.sh`, convenciones visibles (lint, CI, prefijos de commit del `git log`) y documentación existente. Cabe en unos 1500 tokens. **Nunca toca un `CLAUDE.md`**: el borrador va a un archivo nuevo (`CLAUDE.md.borrador`, luego `.2`, `.3`…). En la página, el botón pide confirmación. Es un borrador: no sabe de arquitectura ni de lo que no se vea en los archivos.

## modo conciso (opt-in, apagado)

Una instrucción corta, editable (texto por defecto en español e inglés), que `hooks/pet-brain.sh start` antepone al contexto de arranque. Contrato con el hook: `~/.claude-pet/conciso.txt`, UTF-8, permisos 0600, máximo 1200 bytes; si existe y no está vacío, su contenido se imprime tal cual y una línea en blanco; si no existe, nada. La app lo escribe al activar y lo borra al apagar. Vale desde la sesión siguiente. Si cambias `pet-brain.sh`, conserva la función `pet_concise` y su llamada en `start`.

## filtro de salida

```
comando 2>&1 | ClaudePet --squeeze
```

Quita colores y secuencias ANSI, barras de progreso y spinners, junta líneas repetidas («×34»; si solo cambia una cifra también), recorta trazas largas (más de 8 líneas: deja las 2 primeras y las 3 últimas, y la cabecera y la causa son líneas normales que se conservan), resume las pruebas que pasan y los pasos de compilación, y trunca líneas de más de 600 bytes. **Conserva siempre** cualquier línea con error, fallo, pánico, excepción, aserción, advertencia, «not found», `npm ERR!`… y los resúmenes de `swift test`, `pytest`, `vitest`, `jest`, `xcodebuild`, `cargo` y `npm`. La última línea dice los tokens estimados antes y después. Determinista y sin red.

Medido aquí (compilación `-O` del mismo código, proceso completo):

| entrada | tokens antes → después | tiempo |
|---|---|---|
| salida real de `swift build -v` (103 líneas, 28 KB) | ~8099 → ~4068 (−50 %) | ≈270 ms (arranque del proceso incluido) |
| log sintético de 50 000 líneas (mezcla de errores, compilación, pruebas, trazas y progreso) | ~363 451 → ~287 134 (−21 %) | ≈90 ms |

El porcentaje depende del log: uno de ruido puro se comprime mucho; uno lleno de errores casi nada, a propósito. En la compilación de depuración la prueba de 50 000 líneas tarda unos 0,7 s de CPU.

Límite: **claude pet no puede cambiar lo que devuelven las herramientas de Claude Code** (sus hooks no modifican esa salida). Es un filtro que aplicas tú o un alias a tus propios comandos.

## consejos

Reglas puras sobre las mediciones y el estado: rotar la sesión cuando el contexto restante baja del 30 % (ofrece llevarse las notas con el relevo), sesión de más de 3 h (medida desde que la app ve su primer evento), caché por debajo del 50 % con muestra suficiente, un PDF/docx/pptx/xlsx leído (basta la extensión; el Markdown o el texto plano gastan menos) y un prompt muy general. Como mucho uno a la vez: 5 min entre consejos y 30 min antes de repetir el mismo. La página los lista siempre; en la isla aparecen como una línea (y se quitan a los 25 s) solo con «consejos de ahorro» activado, apagado de serie. Los dos últimos tipos solo salen en el momento. El texto del prompt se reduce a «cuántas palabras y si es general» al instante y no se guarda.

## pruebas

`--selftest-usage`, `--selftest-claudemd`, `--selftest-squeeze`, `--selftest-advice`, `--selftest-concise` (todas en `tests/selftests.sh`). `--snapshot-settings <carpeta>` dibuja la página con datos de ejemplo.
