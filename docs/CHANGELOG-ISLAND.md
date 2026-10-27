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
