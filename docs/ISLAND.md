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
3. aprobar o denegar permisos desde la mascota. hoy el hook solo informa y sale con 0; hace falta un hook `PermissionRequest` que espere la respuesta de la app por el socket y devuelva allow, deny o siempre permitir.
4. responder preguntas de `AskUserQuestion` desde la isla.
5. animación de personaje: respiración, parpadeo, ojos que siguen el cursor, reacción al toque (molestia y mareo), salto al terminar. **hecho: `PetAnimator`** (falta el saludo al asomar). con movimiento reducido solo queda la mirada.
6. pestaña por agente (claude y codex) con su línea de pasos recientes.
7. saltar a la terminal de la sesión.
8. vestuario y sonidos propios.

## orden de trabajo

1. máquina de estados de la isla (hecho).
2. ventana de la isla y geometría del notch, sin cambiar las mascotas flotantes: ajuste en el menú para elegir entre flotante e isla (hecho).
3. animación de personaje en la isla (hecho).
4. permisos bloqueantes con protocolo del socket documentado y prueba de que, si la app no responde, claude code sigue con su flujo normal.
5. preguntas y saltar a la terminal.
6. vistas de contexto, diff, mission control y relevo dentro de la isla.

## reglas de seguridad para los permisos

- el hook bloqueante solo espera mientras la app responde; si el socket no existe o se agota el plazo, no devuelve decisión y claude code pregunta en la terminal como siempre.
- la decisión solo se acepta de la sesión que la pidió; el socket sigue siendo 0600 y solo del mismo usuario.
- «siempre permitir» solo se ofrece cuando claude code envía sugerencias de permiso.

## modos

![modos de la isla](img/island-modos.png)

de arriba abajo: oculta (invisible, es el propio notch), asoma, compacta y abierta. la imagen sale de `ClaudePet --snapshot-island <ruta.png>`; en uso real la isla se anima con un resorte al cambiar de modo.

## limites actuales

- la isla muestra a claude y un punto para codex; codex todavía no tiene animación propia en la isla.
- los permisos y preguntas aún no se responden desde la isla.
- verificado: las reglas y la geometría con `--selftest-island` y el dibujo de los cuatro modos con la imagen anterior. no se comprobó en una pantalla real el paso por encima del notch ni los clics traversantes; hay que probarlo con `ClaudePet -layout island`.

## animación del personaje

![poses](img/island-poses.png)

de izquierda a derecha: reposo, mirando a la derecha, mirando arriba, parpadeo, molesta (un toque), mareada (tres toques en 2 s), salto al terminar y caída. imagen generada con `ClaudePet --snapshot-poses <ruta.png>`.

- respiración: el cuerpo se estira un 4 % desde los pies cada 4 s.
- parpadeo: cada 2 a 5 s, con un parpadeo doble ocasional.
- mirada: las pupilas se desplazan una celda hacia el cursor.
- un toque sacude y entrecierra los ojos; tres seguidos marean 1,8 s.
- al terminar una tarea salta 3 celdas y cae con un pequeño aplastamiento.
- con «reducir movimiento» o con animaciones apagadas solo queda la mirada.
