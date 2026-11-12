# recuperación inteligente del cerebro

el cerebro (`~/.claude-pet/brain/`) guarda notas cortas por proyecto. hasta ahora, al abrir una sesión se inyectaban las 12 más recientes, vinieran o no al caso. la recuperación inteligente inyecta solo lo relevante, en un formato más corto, dentro de un presupuesto de tokens. todo es local, sin dependencias y sin modelo de lenguaje.

está **apagada por defecto**: con el interruptor apagado el cerebro se comporta exactamente como antes.

```sh
ClaudePet --brain config smart on          # enciende
ClaudePet --brain config budget 500        # tokens estimados por mensaje (100 a 2000, defecto 400)
ClaudePet --brain config smart off         # apaga
ClaudePet --brain config                   # muestra el estado
```

los ajustes viven en `~/.claude-pet/brain-settings.json` (0600), a propósito fuera de `config.json`: los lee el comando `--brain` en otro proceso y la app en marcha reescribe `config.json` con su copia en memoria, así que un ajuste puesto desde la terminal se perdería. no hay control en la ventana de ajustes todavía; la lectura y escritura están en `BrainSettings` para cuando se añada. `CLAUDE_PET_BRAIN_SMART=1|0` manda sobre el archivo.

## cómo funciona

```
mensaje del usuario
   │  hook UserPromptSubmit → pet-brain.sh recall → ClaudePet --brain recall --hook
   ▼
notas vivas del proyecto + globales (sin archivadas, sin las de trato)
   │  padre-hijo: cada nota se parte en frases (hijas)
   ▼
etapa 1, sobre las hijas
   ├─ BM25 (sin tildes ni mayúsculas, plurales simples, español e inglés)
   └─ semántica local de NaturalLanguage: consulta ampliada con vecinos de significado
      + coseno del vector medio de palabras (solo parecidos fuertes)
   │  reciprocal rank fusion (k = 60) → 30 candidatas
   ▼
etapa 2, re-ranker heurístico sobre las candidatas (las hijas vuelven a su padre)
   │  + proximidad de los términos de la consulta, frescura por tipo, tipo de nota,
   │    coincidencia de proyecto, penalización si BrainDream la marcó obsoleta
   ▼
las K mejores (--max, defecto 5) dentro del presupuesto (--budget) → la nota entera
```

### recuperación híbrida
- **BM25** (k1 = 1,2, b = 0,75) sobre frases. el texto se pasa a minúsculas y sin tildes; se quitan palabras vacías en español e inglés; un stemming mínimo junta `hook`/`hooks` y `nota`/`notas`.
- **semántica**: `NLEmbedding.wordEmbedding` (fuera de línea). si el idioma no está en el equipo, o el modelo no conoce las palabras, se usa solo BM25 y no falla (`CLAUDE_PET_BRAIN_NOSEM=1` lo fuerza). se eligió el modelo de **palabras** y no el de **frases** porque medido en esta Mac el de frases tarda unos 280 ms en cargar y 5 a 12 ms por frase, inviable para un hook en cada mensaje; el de palabras carga en unos 10 ms.
- **resultado honesto de la medición**: el coseno del vector medio de palabras separa mal (pares relevantes 0,35 a 0,81, irrelevantes 0,37 a 0,63), así que su umbral es alto (0,70) y casi solo deja pasar parecidos fuertes. lo que aporta de verdad es la **expansión de la consulta con vecinos** (`coche` encuentra `vehículo`, `servidor` encuentra `ordenador`). es un recuerdo semántico flojo comparado con un modelo de embeddings de frases: ayuda con sinónimos de nombres concretos, no con paráfrasis.
- **fusión**: reciprocal rank fusion, `suma de 1 / (60 + posición)` sobre las listas (léxica, expansión, coseno). no compara puntuaciones de escalas distintas.

### re-ranking en dos etapas
la primera etapa recupera 30 candidatas rápido. la segunda las reordena con señales baratas: puntuación fusionada normalizada, proximidad de los términos, frescura (vida media: hecho 45 días, pendiente 30, decisión 240, cuidado y trato 365), peso por tipo (cuidado 0,25 > decisión y trato 0,15 > pendiente 0,12 > hecho 0,03), +0,08 si es del proyecto y −0,40 si está marcada como obsoleta. **es un re-ranker heurístico, no un cross-encoder**: un cross-encoder lee consulta y nota juntas con un modelo, y aquí no hay ninguno.

### padre-hijo
las notas se buscan por frases (hijas, precisión) y se entregan enteras (padre, contexto). si la nota entera no cabe en el presupuesto, se recorta empezando en la frase que coincidió, con `…` delante.

### formato
```
<notas-del-proyecto proyecto="claude-pet" mostradas="2" de="40">
[cuidado 3d tu] no usar la cámara en las apps
[hecho 12d claude global] las pruebas se corren con tests/selftests.sh
</notas-del-proyecto>
```
una línea por nota: `[tipo edad autor]` y, si aplica, `global`, `obsoleta?` o `resume N`. sin prosa de relleno. el texto de la nota se escapa (`<`, `>`, `&`) para que no pueda cerrar la etiqueta ni abrir otra. al abrir la sesión, `show` usa este formato con las notas de trato primero, la línea de personalidad de siempre y una línea para guardar notas.

### presupuesto
tokens estimados = caracteres / 3,5 (sobrestima un poco). se cuenta cabecera y cierre. si ni la primera nota cabe entera se recorta; si ni recortada cabe, no se inyecta nada. un mensaje sin términos útiles (`ok gracias`) no inyecta nada.

### hook
`hooks/pet-brain.sh recall` lee el JSON del hook `UserPromptSubmit` con `jq` (hasta 1 MiB, solo `cwd` y `prompt` de primer nivel, primeros 800 caracteres del mensaje), ejecuta `ClaudePet --brain recall --hook -- "<mensaje>"` y envuelve el resultado como indica la documentación de hooks de Claude Code:

```json
{"hookSpecificOutput": {"hookEventName": "UserPromptSubmit", "additionalContext": "<notas-del-proyecto ...>"}}
```

claude code limita ese texto a 10 000 caracteres; el presupuesto máximo (2000 tokens ≈ 7000 caracteres) cabe. falla abierto: sin `jq`, sin mensaje, con el interruptor apagado o ante cualquier error no imprime nada y sale con 0. el timeout del hook es de 3 s. `./install-brain.sh` lo añade de forma idempotente junto al de `SessionStart` y `--uninstall` lo quita.

### memoria episódica
con el interruptor encendido, el repaso nocturno (`BrainDream`, o `ClaudePet --brain dream`) condensa los **hechos y decisiones de más de 30 días** que hablan de lo mismo (al menos 3, parecido de vocabulario ≥ 0,25) en una nota-resumen **extractiva**: se queda con las frases que más términos del tema comparten, sin generar texto, hasta 240 caracteres. el resumen guarda en `sources` los ids de las originales y conserva la fecha más reciente y a `tu` si alguna era tuya. las originales pasan a `archived`: siguen en el archivo json, no cuentan para el tope de 60 notas ni se muestran ni se buscan. los cuidados, tratos y pendientes no se condensan. tope de 300 archivadas por proyecto (el archivo se lee con un límite de tamaño): pasado eso, las más viejas salen del archivo, y el resumen conserva las frases que mejor las representaban.

## privacidad
todo ocurre en el proceso local. el texto de las notas no se registra con `os.Logger`/`Diag`, no entra en el pet bus, no llega a plugins ni a Visto. no hay índice en disco: BM25 y los vectores se calculan en memoria en cada llamada (con 200 notas es más barato que mantener una caché).

## medidas
en el proyecto de muestra de `--selftest-brain-recall` (15 notas + 1 global), tokens estimados: resumen antiguo 438, resumen compacto 363, recall de una consulta 47. tiempos del recall dentro del proceso con 200 notas: bm25 mediana unos 15 ms; bm25 más embeddings del sistema unos 80 ms. los números del hook completo (con el arranque del proceso) están en el informe de la rama y dependen de la carga de la Mac.

## qué no se hace aquí, y por qué
- **HyDE**: necesita generar un texto hipotético con un modelo. lo más cercano y honesto que hay es la expansión con vecinos de palabras, que no es lo mismo.
- **cross-encoder real**: exige un modelo que puntúe consulta y nota juntas. el re-ranker es heurístico y así se llama.
- **few-shot dinámico y chain-of-note**: son parte del prompt de la aplicación que llama al modelo, no del cerebro.
- **MemGPT y RAG agéntico**: los hace el agente con herramientas (decide cuándo leer y escribir memoria). el cerebro ofrece `recall` y `add`, pero no decide por el agente.
- **caché de contexto**: lo hace la API de Anthropic; el cerebro solo podría ayudar siendo estable (mismo prefijo), y el recall cambia con cada mensaje a propósito.
- **resumen abstractivo**: la condensación es extractiva; reescribir en otras palabras exige un modelo.
- **embeddings de frases por defecto**: disponibles en el sistema pero demasiado lentos para un hook por mensaje (ver arriba).

## límites
- el stemming es mínimo y solo cubre plurales; `compilar` no encuentra `compilación`.
- la semántica depende de que el modelo de palabras del sistema conozca el término; las palabras sin tilde (`camara`) pueden no estar en su vocabulario. el idioma se elige por mensaje (español o inglés); una consulta en un idioma contra notas en otro solo aprovecha BM25.
- no hay memoria de lo ya inyectado en la sesión: si dos mensajes seguidos tratan lo mismo, la misma nota puede repetirse.
- no se ha comprobado cómo se ve el contexto adicional dentro de una sesión real de Claude Code.
