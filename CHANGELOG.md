# historial de versiones

Formato basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/). Las versiones anteriores a la 2.0 se etiquetaron a posteriori sobre los commits donde cada hito quedó completo.

## [2.4.0] - 2026-10-27

### añadido
- **el dock cambia según la app en primer plano**, como la Touch Bar: editores (Xcode, VS Code, Cursor, JetBrains, Zed, Sublime, Nova), terminales, navegadores, música, mensajes y correo, notas y documentos, diseño y Finder tienen cada uno sus herramientas, que se enseñan primero y se completan con tus acciones. Un icono de la app aparece junto al dock. Se puede apagar. Solo se lee el nombre de la app al frente.
- seis acciones nuevas: abrir el proyecto en el editor activo (Xcode prefiere el workspace, luego el paquete), abrir el repo en la web (GitHub, GitLab, Bitbucket y Codeberg; nunca con credenciales), copiar `cd` al proyecto (entre comillas seguras), copiar la ruta, anterior y siguiente de la música.
- tabla de perfiles en Ajustes → comportamiento.

## [2.3.0] - 2026-10-27

### añadido
- **acceso rápido en la isla**: la fila de pastillas de texto pasa a ser un dock de iconos que se adapta al contexto (hasta cinco a la vez, con insignias de cambios) y se expande con su nombre al pasar el cursor. El resto, y las acciones de plugins, van en un menú +.
- trece acciones: commitear, terminal, cambios, reproducir o pausar la música, mission control, copiar resumen, abrir la carpeta, punto de restauración, pomodoro, silenciar avisos, relevo de sesión, perímetro y ajustes. Se activan y ordenan en Ajustes → comportamiento.
- `--selftest-quick` y `--snapshot-dock`.

### cambiado
- sin proyecto ni cambios, la isla en reposo enseña un icono en vez de dos pastillas de texto.

## [2.2.0] - 2026-10-27

### añadido
- **seguir el ritmo de verdad** (opt-in): la mascota oye el audio del Mac con ScreenCaptureKit, calcula graves, medios, agudos, pulsos y tempo, y salta con el bombo, cabecea al compás y enseña un ecualizador y un aro en cada pulso. La captura solo corre mientras suena algo. Ver `docs/MUSICA.md`.
- **Codex también baila** (antes solo bailaba Claude), con la misma lógica de compás.
- reacciones sin permisos extra: salta al empezar la música, suspira al pausar y la fuerza del baile sigue al volumen de la app.
- **colores de la portada**: el acento de cada canción sale de su portada y tiñe el progreso, el volumen, el ecualizador, las notas y un resplandor que late con el bombo.
- **vinilo** con la portada de etiqueta que gira junto a la mascota, con brazo de tocadiscos que baja al sonar y sube al pausar.
- `--selftest-audio`, `--snapshot-dance` y `--snapshot-vinyl`.

### cambiado
- el baile ya no es un balanceo fijo de 2 Hz: sin escucha sigue el volumen; con ella, el compás.
- los corazones de la caricia no salen mientras baila.

## [2.1.0] - 2026-10-27

### añadido
- **plugins**: carpetas con un `plugin.json` que añaden acciones al menú y a la isla, ajustes propios y reaccionan a eventos (sesión terminada, permisos, canción nueva). Permisos aprobados por el usuario antes de activar, ejecutables que no pueden salirse de su carpeta, entorno mínimo sin tus variables, plazo de 15 s y 64 KB de salida. Incluye tres ejemplos, entre ellos commitero. Ver `docs/PLUGINS.md`.
- **identidad de Claude y Codex** en ajustes: vidrio real del sistema con el dúo naranja del bloque de Claude y azul de la nube de Codex, las dos mascotas en la barra lateral y una tarjeta por agente con previsualización de sus aspectos. Interruptores, deslizadores y segmentos propios de cristal.
- **portadas indexadas**: caché en disco (192 px, hasta 80 archivos y 24 MB) para que salgan al instante, historial de recientes con repetición y portada de respaldo con la inicial de la canción.
- el guardarropa en **Codex**: los seis atuendos también para su avatar, y en el modo flotante.
- `tests/plugins.sh`, `--selftest-plugins`, `--selftest-plugin-examples`, `--snapshot-outfits`.

### cambiado
- AppleScript de la música corre en una cola propia, de una consulta en una, con `with timeout of 3 seconds`: si Spotify o Music no responden, la app no se cuelga.
- al cerrar la ventana de ajustes se libera su contenido, así una ventana oculta no se redibuja cuando cambia algo.
- los skins de las mascotas pasan de apariencia a la tarjeta de cada agente.
- la barra lateral de ajustes se desplaza sola hasta la página activa.

### corregido
- los atuendos solo se veían en Claude, en la isla y con el aspecto bloque; ahora se aplican en ambas mascotas y en los dos modos.
- un plugin cuya carpeta no coincide con su `id` podía tapar a otro; ahora se registra siempre con el nombre de su carpeta.

## [2.0.0] - 2026-10-27

### añadido
- **ventana de ajustes** con barra lateral agrupada, buscador sin acentos y catorce páginas: resumen, apariencia, comportamiento, agentes, permisos, perímetro, privacidad, guardarropa, sonidos, música, foco y pomodoro, atajos, copia y restauración, acerca de. Vista previa de la isla que se mueve al cambiar los ajustes.
- **perímetro por proyecto**: carpetas permitidas y archivos protegidos que se comprueban en el permiso antes de que el archivo cambie; avisar (rojo, nunca se aprueba solo) o bloquear (se deniega sin preguntar). Ver `docs/PERIMETRO.md`.
- **reproductor de Spotify y Apple Music** en la isla: portada, progreso arrastrable, anterior, pausa, siguiente y volumen. La mascota se pone auriculares, baila y suelta notas según el volumen, con un destello al cambiar de tema. Opt-in. Ver `docs/MUSICA.md`.
- volumen por categoría de sonido (interfaz, alertas, mascota) y prueba de cada sonido.
- atajos globales con letra configurable y control de duplicados.
- copia de seguridad de ajustes: exportar, importar (validado por tipo y rango) y restablecer.
- `ClaudePet --open-settings [página]`, `--snapshot-settings`, `--snapshot-music`, `--snapshot-permission` y los selftests `--selftest-settings`, `--selftest-music` y `--selftest-perimeter`.

### cambiado
- el menú de la barra pasa de unos treinta elementos sueltos a estado en vivo, cuatro acciones y cuatro submenús; el resto vive en ajustes.
- las reglas de aprobación ya no aprueban solas un archivo que rompe el perímetro.

### corregido
- los scripts de AppleScript de Music se rompían con una variable llamada `st`; ahora hay una prueba que los compila contra el diccionario real de cada app.

## [1.2.0] - 2026-10-27

### añadido
- integración con [commitero](https://github.com/kisnner26/commitero): el botón "commitear" de la isla abre el proyecto con sus cambios agrupados.
- la mascota tiene vida propia en reposo (respira, mira alrededor, se estira, bosteza), entra con un rebote al abrir la isla, asiente al permitir, niega al denegar y se impacienta si un permiso espera.
- caricia: si dejas el cursor sobre la mascota se pone contenta con corazones; de día y en calma, una mariposa que sigue con los ojos.
- onda de actividad con cada herramienta del agente.

### corregido
- consumo de CPU con la isla cerrada y abierta bajo una sesión en vivo.

## [1.1.0] - 2026-10-27

### añadido
- isla sin notch con la altura real de la barra de menús; ubicación arriba, abajo, lateral o flotante; zona de activación y retraso ajustables; selector de pantalla.
- cierre rápido de la isla al salir el cursor.
- escena de la mascota en el panel abierto, con su mundo por estado y frases que se escriben solas.
- efectos visuales: pulso de alerta con cuenta atrás, reloj de arena del pomodoro, contexto como líquido, aurora, lluvia de líneas al editar, tráiler al terminar, choque de manos entre agentes y gotas líquidas.
- trece sonidos sintetizados con límite por categoría y reemplazo por archivo propio.
- guardarropa de seis atuendos que se desbloquean por nivel, con atuendos de temporada.
- resumen semanal con racha y nivel, e imagen para compartir.
- puntos de restauración con git, reglas de aprobación con caducidad, lecturas por lotes y detector de bucles.
- soltar archivos sobre la isla, modo foco, pomodoro y exportación de la auditoría.

## [1.0.0] - 2026-10-26

### añadido
- **isla en el notch**: la mascota sale del notch y muestra lo que hace cada agente.
- permisos y preguntas de Claude Code respondidos desde la isla (permitir, denegar, siempre), con hook bloqueante que falla abierto.
- mission control, traspaso entre Claude y Codex, contexto de ambos agentes y registro local de decisiones.

## [0.3.0] - 2026-10-19

### añadido
- web scout nativo: marcar la selección, auditar controles y un rastreador de enlaces con informe, con mascota a elegir.

## [0.2.0] - 2026-10-05

### añadido
- aviso de contexto, detector de atasco y apertura del diff de lo que cambió el agente.

## [0.1.0] - 2026-10-05

### añadido
- primera versión: una mascota pixel-art en la barra de menú que refleja el estado de Claude Code.

[2.4.0]: https://github.com/kisnner26/claude-pet/compare/v2.3.0...v2.4.0
[2.3.0]: https://github.com/kisnner26/claude-pet/compare/v2.2.0...v2.3.0
[2.2.0]: https://github.com/kisnner26/claude-pet/compare/v2.1.0...v2.2.0
[2.1.0]: https://github.com/kisnner26/claude-pet/compare/v2.0.0...v2.1.0
[2.0.0]: https://github.com/kisnner26/claude-pet/compare/v1.2.0...v2.0.0
[1.2.0]: https://github.com/kisnner26/claude-pet/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/kisnner26/claude-pet/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/kisnner26/claude-pet/compare/v0.3.0...v1.0.0
[0.3.0]: https://github.com/kisnner26/claude-pet/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/kisnner26/claude-pet/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/kisnner26/claude-pet/commits/v0.1.0
