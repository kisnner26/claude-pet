# isla de claude pet

## qué hace

claude pet muestra claude y codex como mascotas pixel-art flotantes o como una isla anclada al notch. la isla puede asomar, compactarse y abrirse para enseñar permisos, preguntas, contexto, cambios de git, actividad, mission control y relevo de sesión.

## instalación

desde el repositorio:

```sh
./install-hooks.sh
```

activa `isla en el notch` en el menú. responder permisos y preguntas desde la isla es opt-in. el instalador es idempotente y las pruebas usan `HOME` temporal; no se debe editar `~/.claude/settings.json` a mano.

pruebas principales:

```sh
swift build
.build/debug/ClaudePet --selftest-island
.build/debug/ClaudePet --selftest-permission hooks/pet-permission.sh
.build/debug/ClaudePet --selftest-question hooks/pet-question.sh
```

## protocolo local

los hooks usan `~/.claude-pet/ask.sock`, un socket unix 0600 que solo acepta el mismo uid. `pet-permission.sh` envía `perm<TAB>sesión<TAB>herramienta<TAB>proyecto<TAB>siempre<TAB>detalle`; `pet-question.sh` envía `ask<TAB>sesión<TAB>proyecto<TAB>base64(json de questions)`.

las líneas tienen límite de 4096 bytes y deben terminar en salto de línea. hay un máximo de ocho pendientes por tipo. cualquier entrada inválida, socket ausente, hook muerto o plazo agotado produce salida vacía: claude code continúa en la terminal.

las respuestas de preguntas se validan como json antes de envolverse en `updatedInput`; las decisiones de permisos solo pueden ser `allow`, `always` o `deny`. no se ejecuta shell con rutas, nombres o detalles recibidos del hook.

## rendimiento y seguridad

la isla usa 60 hz mientras está activa y 1 hz cuando está oculta, sin tareas ni atención pendiente. `--selftest-polling` verifica la política; no sustituye un perfil de cpu en pantalla real.

los atajos globales son opt-in, aceptan únicamente ctrl+option+a/d/i/s/p, ignoran repeticiones y se desregistran al cerrar. requieren permiso de accesibilidad de macos.

## límites conocidos

- no se ha verificado sobre el notch físico ni el clic atravesante en una pantalla real.
- no se ha verificado el foco real de terminal, finder o mission control.
- no se ha verificado voiceover real ni el permiso de accesibilidad.
- falta validar el ciclo completo con una sesión real de claude code y codex.
- las capturas son snapshots de `ImageRenderer`, no sustituyen una ejecución en pantalla real.

## checklist manual

- [ ] notch real: activa `isla en el notch`, mueve el cursor sobre el notch y confirma que asoma y se abre centrada, sin tapar la barra de menús.
- [ ] clic traversante: con la isla oculta, haz clic fuera de su forma y confirma que la app bajo ella recibe el clic; repite dentro y confirma que abre el detalle.
- [ ] permiso real: activa `responder permisos desde la isla`, ejecuta una herramienta que pida permiso y pulsa `permitir` y después `denegar`; claude code debe recibir cada decisión.
- [ ] pregunta real: ejecuta una llamada a `AskUserQuestion`, responde una opción desde la tarjeta y confirma que la sesión continúa con esa respuesta.
- [ ] voiceover: activa voiceover, enfoca la isla y confirma que anuncia agente, estado, porcentaje y alerta sin leer comandos completos.

el detalle de capacidades y cambios pequeños está en [CHANGELOG-ISLAND.md](CHANGELOG-ISLAND.md).
