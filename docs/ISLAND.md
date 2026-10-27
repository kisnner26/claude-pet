# isla de claude pet

plan para que claude pet viva en el notch (o en la barra superior en pantallas sin notch) y se comporte como un compañero integrado, al estilo de coucou. se reimplementa con las mascotas pixel-art de claude y codex; no se copia código ni assets de coucou.

## que ya existe y se reutiliza

| pieza de claude pet | papel en la isla |
| --- | --- |
| estados de `PetState` y burbuja de tarea | línea de actividad de la vista abierta |
| aro de contexto (`ContextMeter`) | indicador en la mascota compacta y en la vista abierta |
| mapa de archivos y diff (`FileOrbitView`, `GitPulse`) | tarjeta de diff con `+N −M` |
| mission control y relevo de sesión | pestañas de la vista abierta |
| claudwler y web scout | acciones desde la vista abierta |
| pet bus y `EventServer` | canal de eventos de las dos mascotas |

## que falta frente a coucou

1. isla anclada al notch con cuatro modos: oculta, asoma, compacta y abierta. **hecho: `IslandMachine`** (reglas, tiempos y autoprueba `--selftest-island`).
2. ventana sin bordes que se coloca en el notch real, o en una barra de 80 pt si no hay notch, con clics traversantes fuera de la forma. **hecho: `NotchGeometry` e `IslandController`**; el menú tiene el selector `modo` (flotante o isla en el notch) y la pantalla se recalcula al conectar o desconectar monitores.
3. aprobar o denegar permisos desde la mascota. **hecho: `PermissionServer` y `hooks/pet-permission.sh`** (ver abajo). es opt-in.
4. responder preguntas de `AskUserQuestion` desde la isla. **hecho: `pet-question.sh`, `QuestionServer` y tarjeta de opciones**, con selección única y múltiple en el protocolo.
5. animación de personaje: respiración, parpadeo, ojos que siguen el cursor, reacción al toque (molestia y mareo), salto al terminar y saludo al asomar. **hecho: `PetAnimator`**. con movimiento reducido solo queda la mirada.
6. pestaña por agente (claude y codex) con su línea de pasos recientes. **hecho: selector claude/codex**; codex solo muestra el estado y la línea que ya publica su adaptador.
7. aro de contexto y mapa de archivos dentro de la isla. **hecho: reutiliza `ContextRingView` y `FileOrbitView`** con los mismos estados normal, caution y critical.
8. mission control y relevo de sesión accesibles desde la isla. **hecho: botones directos en la vista abierta**.
9. limpieza al recibir `SIGTERM` o `SIGINT`. **hecho: detiene sockets y borra la bandera opt-in**.
10. atajos globales opcionales. **hecho: ctrl+option+a permite, ctrl+option+d deniega y ctrl+option+i abre la isla**; requieren activar el interruptor y el permiso de accesibilidad de macos.
11. varias pantallas. **hecho: menú con `pantalla del notch` o `seguir al ratón`**, probado con `ScreenMetrics` simuladas en `--selftest-island`.
12. resistencia del socket. **hecho: `--selftest-resistance` inyecta 500 preguntas/permisos, cierra hooks a mitad y comprueba que no quedan tarjetas pendientes**.
7. saltar a la terminal de la sesión. **hecho: `TerminalTargetResolver`**, con no-op seguro si no hay coincidencia única.
8. ticker de pasos, pestañas de agentes, contexto, mapa, mission control y relevo. **hecho en la vista abierta**.

## orden de trabajo

1. máquina de estados de la isla (hecho).
2. ventana de la isla y geometría del notch, sin cambiar las mascotas flotantes: ajuste en el menú para elegir entre flotante e isla (hecho).
3. animación de personaje en la isla (hecho).
4. permisos bloqueantes con protocolo del socket documentado y prueba de que, si la app no responde, claude code sigue con su flujo normal (hecho).
5. preguntas y saltar a la terminal. **hecho: `QuestionServer` y `TerminalTargetResolver`**.
6. vistas de contexto, diff, mission control y relevo dentro de la isla.

## permisos desde la isla

activación (todo opt-in):

1. `./install-hooks.sh` copia `pet-permission.sh` y añade un segundo hook de `PermissionRequest` con plazo de 120 s. pide confirmación antes de tocar `~/.claude/settings.json`.
2. en el menú, modo `isla en el notch` y el interruptor `responder permisos desde la isla`.

entonces, cuando claude code pide un permiso, la isla se abre sola con la herramienta, el proyecto y el comando o archivo, y tres botones: denegar, siempre (solo si claude code sugirió una regla) y permitir. si hay varios, se responden en orden de llegada.

protocolo: el hook abre `~/.claude-pet/ask.sock`, envía una línea `perm<TAB>sesión<TAB>herramienta<TAB>proyecto<TAB>siempre<TAB>detalle` y espera una línea `allow`, `always` o `deny`. la app mantiene la conexión abierta; si el hook muere (por ejemplo porque respondiste en la terminal) la conexión se cierra y la tarjeta desaparece. el hook imprime la decisión en el formato de `PermissionRequest` de claude code.

el comando que se va a aprobar se muestra en la isla; viaja solo por el socket local y no se guarda ni se publica en el pet bus.

## reglas de seguridad para los permisos

- el hook no hace nada si falta la bandera `~/.claude-pet/island-permissions` (la app la crea solo en modo isla con el interruptor y la borra al salir), el socket, `jq` o `perl`; si se agota el plazo o la app se cierra, no devuelve decisión y claude code pregunta en la terminal como siempre.
- un máximo de 8 permisos pendientes; el noveno se rechaza y se pregunta en la terminal.
- el socket es 0600 y solo acepta conexiones del mismo usuario; cada permiso se responde una sola vez.
- «siempre permitir» solo se ofrece cuando claude code envía sugerencias de permiso.

## modos

![modos de la isla](img/island-modos.png)

de arriba abajo: oculta (invisible, es el propio notch), asoma, compacta y abierta. la imagen sale de `ClaudePet --snapshot-island <ruta.png>`; en uso real la isla se anima con un resorte al cambiar de modo.

## limites actuales

- la isla muestra a claude y un codex pixel-art animado por estado; claude saluda durante 1,4 s al asomar. con reducir movimiento no se animan ni codex ni el saludo.
- `AskUserQuestion` ya llega por `ask.sock`, conserva hasta cuatro preguntas y devuelve el formato documentado; falta validarlo con una sesión real de Claude Code.
- el salto a terminal solo se activa cuando hay una única ventana visible de terminal, iterm, ghostty, warp o vs code cuyo título contiene el proyecto; con ambigüedad muestra `terminal no identificada` y no enfoca nada.
- la vista abierta conserva hasta ocho pasos recientes de claude en memoria; muestra herramienta, objetivo recortado y `+N -M` cuando el objetivo coincide con un archivo cambiado. pulsar un paso reutiliza `GitPulse`/`DiffPullReader`; no se escriben comandos ni rutas completas.
- verificado: todos los autochequeos de permisos, preguntas, isla, terminal, pasos, pestañas, telemetría, acciones, limpieza, atajos, pantallas y resistencia; también `swift build` y las imágenes `--snapshot-island` y `--snapshot-poses`. no se comprobó en una pantalla real el paso por encima del notch, los clics traversantes, el foco de terminal ni la autorización de accesibilidad; hay que probarlo con `ClaudePet -layout island`.
- el menú incluye `ver demo de la isla`: carga datos sintéticos solo en memoria durante 30 s para enseñar permisos, preguntas, contexto, pasos y los dos agentes sin hooks ni sesiones reales. `--selftest-demo` comprueba que carga y limpia todo.

## animación del personaje

![poses](img/island-poses.png)

de izquierda a derecha: reposo, mirando a la derecha, mirando arriba, parpadeo, molesta (un toque), mareada (tres toques en 2 s), salto al terminar y caída. imagen generada con `ClaudePet --snapshot-poses <ruta.png>`.

- respiración: el cuerpo se estira un 4 % desde los pies cada 4 s.
- parpadeo: cada 2 a 5 s, con un parpadeo doble ocasional.
- mirada: las pupilas se desplazan una celda hacia el cursor.
- un toque sacude y entrecierra los ojos; tres seguidos marean 1,8 s.
- al terminar una tarea salta 3 celdas y cae con un pequeño aplastamiento.
- con «reducir movimiento» o con animaciones apagadas solo queda la mirada.

## preguntas desde la isla

el hook `hooks/pet-question.sh` solo actúa para `PreToolUse` con `tool_name=AskUserQuestion`, exige la bandera opt-in y envía `ask<TAB>sesión<TAB>proyecto<TAB>base64(json de questions)` por el mismo socket local. la tarjeta muestra la primera pregunta de cada entrada y sus opciones. la respuesta vuelve como `updatedInput.answers`; si falla el socket, falta una herramienta o vence el plazo, el hook sale sin imprimir y claude code conserva su flujo normal en la terminal.

formato verificado contra la documentación oficial de hooks de claude code: [hooks reference](https://code.claude.com/docs/en/hooks), sección `AskUserQuestion`. `PreToolUse` debe devolver `hookSpecificOutput.permissionDecision = "allow"` y `updatedInput` con las `questions` originales más `answers` como objeto que asigna el texto de cada pregunta a su respuesta; en selección múltiple las etiquetas se unen con comas.

prueba automática: `ClaudePet --selftest-question hooks/pet-question.sh` ejecuta el hook real con home temporal y cubre opción única, múltiple, cuatro preguntas, texto libre, muerte del hook, app cerrada, plazo, entradas inválidas, recorte, controles y límite de pendientes. falta probar el ciclo completo con una sesión real de claude code.

prueba automática adicional: `ClaudePet --selftest-terminal` cubre coincidencia única, ambigüedad y aplicación no terminal. no se probó el foco de una ventana real.

la tarjeta de permisos incluye `copiar detalle` y `copiar permiso completo`; este último conserva herramienta, proyecto y detalle en texto plano sin escribirlos en disco. `PermissionSelfTest` valida ambos formatos.

en modo compacto, la isla muestra una insignia ámbar con el número de permisos o preguntas pendientes (hasta `9+`) y una etiqueta accesible con el texto completo. `DemoModeSelfTest` comprueba que aparece y desaparece al entrar y salir del demo.

cuando el adaptador de codex publica contexto, el modo compacto muestra también su porcentaje y reutiliza los mismos colores de presión; si no hay lectura, no se inventa ningún valor.

el porcentaje compacto incluye una barra horizontal proporcional al contexto restante para claude y codex; la barra mantiene el estado azul, ámbar o rojo y su etiqueta accesible indica el agente correspondiente.

la vista abierta añade acciones directas para copiar el resumen de contexto y abrir el diff más reciente desde el mapa de archivos.

la pestaña abierta de cada agente muestra cuánto tiempo lleva activa la actividad actual, usando el mismo contador que el menú de la aplicación.

la vista abierta permite copiar un resumen corto de sesión con proyecto, agente y estado; no incluye rutas completas ni comandos.

el botón `actualizar` fuerza una lectura inmediata de telemetría, contexto y cambios sin cerrar la isla.

si existe un workspace publicado, la vista abierta ofrece `abrir carpeta del proyecto` y lo entrega a finder mediante `NSWorkspace`, sin copiar ni persistir rutas.

cada paso reciente del ticker incluye una acción `copiar` que conserva solo su etiqueta y delta (`+N -M`) en el portapapeles.

cuando git está disponible, la vista abierta muestra la rama activa y permite copiarla con un clic; si no hay repositorio, no aparece ninguna rama inventada.

debajo de la rama se resumen cambios, staged y conflictos; los conflictos se colorean en rojo para detectarlos antes de continuar.

el resumen de salud git es interactivo: al pulsarlo abre mission control para revisar el detalle completo.

su menú contextual copia las cifras de cambios, staged y conflictos sin alterar la acción principal de abrir mission control.

los indicadores de contexto y git tienen ayudas contextuales al pasar el cursor, con la leyenda de colores y la acción disponible.

la insignia de decisiones pendientes es interactiva: pulsarla activa la misma respuesta de la mascota y abre el detalle cuando la isla está compacta.

los medidores compactos de contexto también son interactivos: tocar porcentaje o barra abre el detalle correspondiente.

el resumen abierto muestra el modelo detectado junto al anillo y permite copiar su nombre; si falta, indica que no está disponible.

la pestaña codex replica ese resumen solo cuando su adaptador publica una lectura propia: anillo, porcentaje, modelo y copia del nombre, sin inferir paridad.

cuando existe esa lectura, codex también ofrece `copiar contexto codex` con el resumen completo de modelo, porcentaje y tokens restantes.

el ticker de pasos muestra antigüedad relativa (`ahora`, segundos o minutos) calculada en memoria para distinguir actividad reciente de líneas antiguas.

la vista abierta ofrece `copiar actividad reciente`, que reúne hasta tres líneas con objetivo, delta y antigüedad sin persistirlas.

los títulos de estado de claude y codex tienen menú contextual para copiar solo agente, estado y duración.

la insignia de pendientes muestra una ayuda contextual con el total y recuerda que al pulsarla se abre el detalle.

`copiar contexto` usa un resumen completo con modelo, porcentaje restante y tokens disponibles; `SafetySelfTest` valida el formato sin guardar el transcript.

el resumen también indica tokens usados, para comparar consumo y capacidad restante en una sola línea.

el anillo abierto acompaña el color con una etiqueta textual `normal`, `cuidado` o `crítico` para claude y codex.

la etiqueta sale de `ContextReading.pressureLabel`, compartida por ambos agentes y cubierta por `SafetySelfTest`.

el texto copiado conserva también esa presión textual, así el diagnóstico sigue siendo legible aunque se comparta fuera de la interfaz.

la etiqueta accesible del medidor compacto anuncia porcentaje y presión textual en una sola lectura.

el cálculo vive en `IslandStep.ageLabel(now:)` y `IslandStepsSelfTest` lo valida con reloj determinista.

la duración del estado activo cambia de color: blanco antes de un minuto, ámbar desde un minuto y rojo desde cinco; se aplica por separado a claude y codex.

la mascota de claude expone a voiceover su estado y duración, además de una indicación para pulsar y abrir el detalle.

el avatar compacto de codex expone el mismo tipo de etiqueta, pero aclara que su estado proviene del adaptador.

el modo compacto añade un icono semántico para el estado de claude: puntos al pensar, herramienta, mano de aprobación, alerta, check al terminar.

codex muestra su propio icono con la misma semántica, usando únicamente el estado recibido de su adaptador.

ambos iconos compactos tienen ayuda contextual con el estado textual actual.

los medidores compactos admiten clic secundario para copiar el resumen de contexto; el clic principal conserva la apertura del detalle.

los anillos abiertos muestran el mismo resumen completo como ayuda contextual al pasar el cursor.
