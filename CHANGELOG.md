# historial de versiones

Formato basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/). Las versiones anteriores a la 2.0 se etiquetaron a posteriori sobre los commits donde cada hito quedó completo.

## [Sin publicar]

### cambiado
- El genio no se enfada con el modo foco ni en mitad de un pomodoro de trabajo (el botón de probar sigue funcionando).
- La isla abierta deja los colores saturados: sin los pulsos naranjas ni el borde de color; ahora es cristal líquido oscuro (carbón con un velo azul tenue, reflejo especular y un hilo de luz blanca en el borde), con una sola luz neutra en todas las páginas. El brillo y la aurora de estado se reducen a la mitad o menos.

### rendimiento
- La isla abierta gasta alrededor de un 25 % menos de CPU en la medición (de ~28 % a ~21 % con la demo animada): las hebras de fibra de vidrio se dibujan una sola vez y solo los pulsos y un trazo del borde se animan (se quitó el degradado cónico giratorio y la mezcla aditiva), los efectos decorativos pasan de 20-30 a 15 cuadros por segundo y la mascota en reposo respira a 6.
- La consulta de música (un AppleScript) pasa de cada 3 s a cada 10 s cuando no suena nada.
- Vestir a la mascota ya no convierte colores píxel a píxel en cada cuadro.
- La isla compacta en reposo, sin trabajo ni avisos y con el cursor lejos, sondea a 10 Hz en lugar de 30.
- Ahorro automático: con el modo de bajo consumo de macOS o con poca batería, la isla deja los brillos y las hebras animadas (Ajustes → comportamiento → energía).
- Nuevos modos de medición `--cpu-island-expanded` y `--cpu-island-idle`.

### añadido
- Los avisos al teléfono (ntfy) incluyen ahora los del plan: al cruzar el 80 % y el 95 % del límite de 5 horas o semanal llega el mismo aviso que ves en la isla, sin nombre de proyecto.
- El clima recuerda la última lectura entre arranques: si es de hace menos de tres horas, las mascotas ya salen vestidas para el tiempo sin esperar a la red.
- Meta Quest: como mucho cuatro visores a la vez; el quinto recibe un 429 en lugar de agotar la app.
- Realidad aumentada interactiva: tocar una mascota la hace saltar y soltar corazones (cuatro toques seguidos la marean); mantener el dedo la acaricia con vibración y corazones; se arrastran por la mesa y se cambian de tamaño pellizcando. Te miran y giran hacia ti, y tocar el suelo lanza una pelota que persiguen y se pasan. Botones para llamarlas, darles un premio, lanzar la pelota y hacerlas saltar. Celebran con confeti cuando un agente termina, se sacuden con chispas si falla y muestran lo que están haciendo (herramienta y archivo).
- Menús dentro de la propia píldora: un riel de iconos a la derecha de la isla abierta cambia entre inicio, cambios, música, plan y datos, herramientas (todas las acciones disponibles) y ajustes rápidos, sin abrir ventanas. La isla estrena un estilo de fibra de vidrio: hebras finas al trasluz, pulsos de luz que las recorren y un borde con destello especular que toma el color de la página.
- Realidad aumentada en Visto (iPhone): las mascotas en 3D sobre tu mesa con su estado en vivo y los permisos como tarjetas flotantes con «Permitir» y «Denegar».
- Meta Quest 2 y 3 (opt-in): la Mac sirve una página WebXR por HTTPS con certificado propio; el navegador del visor la abre con el código de Visto y muestra el panel, las mascotas y los permisos con paso de cámara (Quest 3 a color, Quest 2 en blanco y negro) o en realidad virtual. Solo permite o deniega esta vez, nunca riesgo alto, y frena tras cinco códigos erróneos. Probado el servidor y la página en el navegador; sin probar en un visor real.
- Permitir «siempre» desde Visto: botón con confirmación (y Face ID si está activo) que guarda la regla en la Mac. Nunca con riesgo alto ni fuera del perímetro; la Mac lo vuelve a comprobar. Una Mac anterior no lo ofrece.
- Mascota en el escritorio: se arrastra fuera de la isla y se queda donde la sueltas, vuelve a su sitio al abrir la app y, si quieres, camina hacia el cursor. Doble toque o soltarla sobre la isla la devuelve. Cada agente por separado, con su armario.
- Avisos al teléfono con ntfy (apagado de serie): permisos, preguntas y fin de tarea llegan aunque Visto esté cerrada, sin cuenta de pago de Apple. Tema largo y aleatorio con QR, solo si no estás en el Mac, sin el comando salvo que lo pidas y nunca con secretos.
- Genio: a veces, al segundo golpe seguido, la mascota (claude o codex) se enfada, se hace gigante, camina hasta una ventana de otra app y la patea. La ventana solo se minimiza, nunca se cierra, y hace falta el permiso de accesibilidad (sin él solo ve la animación). Se calma durante un minuto y se apaga en Ajustes → comportamiento.

### corregido
- Al cambiar el código de emparejamiento también se cortan los visores de Meta Quest conectados: antes seguían recibiendo el estado con el código viejo.
- La tarjeta de «demasiados toques» enseña a codex cuando es codex quien se marea, y su texto sigue el idioma elegido.

## [2.10.0] - 2026-10-28

### añadido
- Paridad entre agentes: codex ahora se marea con tres toques, se enfada, parpadea, se duerme, se sorprende y se preocupa con las mismas expresiones que claude (en el visor), lleva las mismas partículas, y el aviso de mareo de la isla salta con cualquiera de los dos.
- Guardarropa por agente: cada mascota tiene su armario; quien ya tenía atuendos los conserva en ambas hasta cambiarlos. Clic derecho en la mascota de la isla para vestirla.
- Clima local (opt-in, apagado de serie): open-meteo con la ubicación del Mac o una ciudad. Las mascotas se visten solas: gafas de sol y sombrero con calor, bufanda, gorro y orejeras con frío, paraguas con lluvia. Cuatro atuendos nuevos: gafas de sol, sombrero, paraguas y orejeras.
- Sentir el entorno: sudan con calor, tiritan con frío, ven llover o nevar y se preocupan con poca batería.
- Acceso rápido: seis familias de apps nuevas (herramientas de desarrollo, videollamadas, vídeo y fotos, juegos), unas 150 apps reconocidas y, para las desconocidas, clasificación por la categoría que declara la app. Acciones nuevas: copiar rama y modo foco.

### corregido
- El goteo al abrir la isla se adapta al ancho: queda entre las esquinas redondeadas, con más gotas y más gruesas en islas grandes y menos y finas en pequeñas.

## [2.9.0] - 2026-10-28

### añadido
- Idioma español o inglés: selector en Ajustes → comportamiento (por defecto sigue el idioma del sistema) y se aplica al momento. Todo `Text`, `Button` y `Label` pasa por un traductor central, así que cada frase nueva solo necesita su entrada en `L10nEN.swift`.
- Visto: selector de idioma en el iPhone; el reloj lo hereda del teléfono. Voz, avisos y estados siguen el idioma elegido.

### pendiente
- Frases armadas con nombres propios (proyectos, agentes) y los textos de los widgets, Siri y Atajos siguen en español.

## [2.8.0] - 2026-10-28

### añadido
- Visto: Isla Dinámica y pantalla bloqueada con el agente que trabaja y botones para permitir o denegar; Face ID opcional para permitir; atajos para Siri, el botón de acción y Atajos; emparejar escaneando un QR que claude pet muestra en Ajustes → permisos; sonidos, háptica, voz, linterna y giroscopio en el iPhone; en el reloj, gesto de girar la muñeca para denegar y pantalla siempre encendida tenue.

## [2.7.1] - 2026-10-28

### corregido
- el estado de los agentes y la actividad no llegaban a Visto: un debounce nunca disparaba porque la mascota publica cambios sin parar.

### añadido
- Visto muestra la mascota de cada agente animada según lo que hace, con tres anillos (límite de 5 horas, semanal y contexto) y una línea de latido. En el iPhone las decisiones se toman deslizando la tarjeta; en el reloj, Double Tap permite.

## [2.7.0] - 2026-10-27

### añadido
- Visto sincroniza con claude pet el estado de Claude y Codex, las últimas acciones, las preguntas de Claude (con respuesta desde el móvil y, si es de una sola elección, desde el reloj), avisos de terminado y fallo, y el modo foco en los dos sentidos.

## [2.6.0] - 2026-10-27

### añadido
- consumo del plan en la isla: barras del límite de 5 horas y del semanal, con aviso al 80 y al 95 por ciento. Usa los datos que Claude Code entrega a su statusline; `install-hooks.sh` lo instala y encadena el statusline que ya tuvieras.
- Visto, app propia de iPhone y Apple Watch (`companion/`) para aprobar permisos con un toque y ver el plan. Canal cifrado con código de emparejamiento; solo permitir o denegar esta vez, y el riesgo alto solo se puede denegar.
- ajuste «enviar permisos a Visto» con el código de emparejamiento.

## [2.5.0] - 2026-10-27

### añadido
- taller de plugins: catálogo en `workshop/` que se ve e instala desde Ajustes → plugins, con paquetes verificados por sha256 y publicación por pull request (`workshop/build.py`, CI y `tests/workshop.sh`).
- siete plugins de ejemplo útiles: `git-estado`, `github-rapido`, `diario-de-sesiones`, `puertos`, `contexto-para-agentes`, `abrir-en` y `todos-del-proyecto`.
- `tests/plugins-utiles.sh` los ejecuta con datos hostiles y comprueba que cada uno devuelva JSON válido y respete sus permisos.

## [2.4.2] - 2026-10-27

### cambiado
- los seis atuendos se redibujan con sombreado, tanto para Claude como para las tres variantes de Codex: gorro de punto con pompón y vuelta, corona con joyas, gafas de verdad (marco fino, cristal con tinte, puente y patillas hasta las orejas; en Codex, montura clara alrededor del visor con puente y patillas), bufanda de rayas con cabo y flecos, audífonos con banda, copas y piloto, y lazo con dos lazadas y nudo.
- los atuendos ahora se definen como pixel-art en ASCII, más fácil de afinar y de revisar.
- `--dump-grids` imprime las rejillas de las mascotas para dibujar encima con exactitud.

### añadido
- pruebas del ancho de cada fila de los dibujos, de que cada letra tenga color y de que ninguna montura pise los ojos.

## [2.4.1] - 2026-10-27

### corregido
- la escucha del audio se quedaba «en espera» aunque sonara algo: el aviso de «empezó a sonar» se enviaba antes de guardar ese estado, así que la escucha seguía viendo «no suena nada»; al pausar pasaba lo contrario y no se apagaba. Ahora el aviso llega con el estado ya guardado, con una prueba que cubre empezar, pausar, reanudar y parar.

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

[2.4.2]: https://github.com/kisnner26/claude-pet/compare/v2.4.1...v2.4.2
[2.4.1]: https://github.com/kisnner26/claude-pet/compare/v2.4.0...v2.4.1
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
