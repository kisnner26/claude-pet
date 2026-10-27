# changelog de la isla

## 2026-10-27

- endurecimiento de atajos: máscara exacta de modificadores, sin repetición y limpieza explícita al cerrar.
- hooks con salida abierta: entrada acotada, respuesta de preguntas validada con `jq` y json escapado por el serializador.
- sockets: uid del peer, modo 0600, máximo de ocho pendientes y rechazo de líneas sin salto o sobredimensionadas.
- fuzz determinista para basura, nulos, utf-8 inválido y tamaños límite en permisos y preguntas.
- cierre probado: desaparecen `ask.sock`, preguntas pendientes y `island-permissions`.
- sondeo adaptativo: 60 hz activo, 1 hz oculto en reposo.
- ticker filtrado por agente; codex no muestra pasos de claude.
- tendencia de contexto en memoria, alerta de descenso rápido y copia de resumen sin transcript.
- alerta compacta para sesiones bloqueadas, separada de decisiones pendientes.
- extracción de `IslandModel`, `IslandPetViews` e `IslandCards` desde `IslandController.swift`, sin cambiar el protocolo ni el flujo de respuestas.
- snapshots de modos y poses regenerados con `ImageRenderer` y revisados visualmente.

## capacidades existentes

- máquina de estados hidden, peek, compact y expanded.
- geometría de notch, pantallas múltiples y preferencia de pantalla.
- permisos y preguntas desde socket local con fallback de terminal.
- animación de claude y codex, saludo, reducir movimiento y snapshots.
- contexto con presión, modelo, tokens y aro visual.
- mapa de archivos, cambios staged, conflictos, diff y rama git.
- ticker de herramientas, objetivos, deltas, antigüedad y copia.
- tabs claude/codex, mission control, relevo y salto seguro a terminal.
- atajos opcionales, demo, telemetría, limpieza y prueba de resistencia.
# cambios recientes

- prueba de cpu en reposo.

- seguimiento de pantalla seleccionado.

- margen conservador de la barra.

- geometría sin notch a 2x.

- geometría sin notch a 1x.

- validación de uid del socket.

- límite de línea de 4096 bytes.

- límite de ocho pendientes.

- fallback abierto del socket.

- bloqueo de escrituras concurrentes.

- botón de apertura del registro.

- exportador markdown sin contenido sensible.

- retención local de noventa días.

- directorio de auditoría con permisos 0700.

- registro con permisos 0600.

- vista previa limitada a cuarenta líneas.

- siempre bloqueado para riesgo alto.

- alcance por proyecto con ventana de treinta minutos.

- alcance por sesión con ventana de ocho horas.

- alcance una vez y su caducidad.

- registro local de decisiones de permisos, con riesgo, resultado y origen; retención de 90 días y permisos 0600.
- acceso directo desde el menú al registro local de decisiones.

- reacción de hover: los ojos crecen una celda mientras el cursor permanece sobre la isla.
- clic con aplastamiento y gesto de molestia durante 0,6 s; se conserva el mareo de tres clics en 2 s.
- autopruebas nuevas en `--selftest-island` para ambas reacciones.
- clasificador local de riesgo en permisos: bajo, medio y alto con explicación visible y casos de evasión básicos.
- detector local de posibles secretos en comandos y rutas, mostrando solo una etiqueta y cuatro caracteres de prefijo.
- transición compartida con resorte amortiguado y variante corta para reducir movimiento; al cambiar de dirección SwiftUI invierte desde el tamaño actual.
- botones de decisión con realce de hover, hundimiento de un píxel y respuesta inmediata.
- configuración local versionada con validación estricta y comandos de inspección.


- ubicaciones de la isla (arriba, abajo, lateral, flotante), zona de activación de 120 a 400 pt con retraso y barra de menús oculta.
- apariencia sin notch: borde interior, sombra hacia dentro y alto contraste; contenido compacto mínimo, normal o completo y reloj opcional.
- selector de pantalla fija y seguimiento del ratón con histéresis de 0,6 s.
- galería de capturas por ubicación y escala; la escala 1x ya no sale siempre a 2x.
- reglas de aprobación (esta sesión, este proyecto 30 min, siempre) con caducidad y revocación; riesgo alto y comandos compuestos nunca se recuerdan.
- aprobación de planes (ExitPlanMode) desde la isla.
- puntos de restauración con `git stash create` en `refs/claude-pet/`, con confirmación y tope de 20 por proyecto.
- detector de bucles de errores, búsquedas y ediciones repetidas.
- banco de 13 sonidos sintetizados en escala pentatónica, motor con límite por categoría y reemplazo por archivo validado.
- guardarropa de seis atuendos pixel-art con temporada automática.
- resumen semanal local con racha y nivel, e imagen compartible sin nombres de proyecto.
- sonidos con timbre propio: campana FM, marimba, clic de papel, pad suave y golpe grave, con reverberación corta, nivel de pico por categoría y sin clics al empezar ni al terminar; WAVs de muestra en `docs/sonidos/` (`ClaudePet --export-sounds <carpeta>`).
- efectos visuales: pulso de alerta con cuenta atrás, reloj de arena del pomodoro, contexto como líquido, aurora con MeshGradient, escenarios pixel-art por estado (lluvia, sol, chispas, estrellas), lluvia de líneas al editar, halo y estrellas por nivel, tráiler de 3 s al terminar, choque de manos entre claude y codex y gotas de metal líquido al abrir la isla.
- los atuendos se desbloquean por nivel real de actividad.
- rendimiento: el transcript se lee desde la cola, la mirada se publica solo si cambia, la búsqueda de terminal se recuerda 5 s y el contexto se escanea cada 5 s (15 s en reposo).
- la mascota se inclina hacia el cursor con todo el cuerpo; cada herramienta del agente lanza una onda desde ella; al cambiar de agente la escena entra con un resorte y las cifras del resumen ruedan; la mascota de codex respira, se estira, bosteza, saluda con la mano y salta al terminar, igual que la de claude.
- la mascota entra con un rebote al abrirse la isla, asiente al permitir un permiso y niega al denegarlo, se impacienta (golpetea y se balancea) si un permiso lleva 15 s esperando y muestra una exclamación a los 40 s; la de codex reacciona a sus propios toques.
- caricia: si dejas el cursor sobre la mascota más de 0,8 s se pone contenta (ojos ^ ^, ronroneo y corazones); de día y tranquila, una mariposa revolotea sobre ella y la sigue con los ojos.
