# historial de versiones

Formato basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/). Las versiones anteriores a la 2.0 se etiquetaron a posteriori sobre los commits donde cada hito quedó completo.

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

[2.0.0]: https://github.com/kisnner26/claude-pet/compare/v1.2.0...v2.0.0
[1.2.0]: https://github.com/kisnner26/claude-pet/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/kisnner26/claude-pet/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/kisnner26/claude-pet/compare/v0.3.0...v1.0.0
[0.3.0]: https://github.com/kisnner26/claude-pet/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/kisnner26/claude-pet/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/kisnner26/claude-pet/commits/v0.1.0
