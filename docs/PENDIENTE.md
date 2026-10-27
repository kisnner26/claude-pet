# pendiente

## hecho en la consolidación

fase 1 casi completa; fase 2, 3 y 4 en parte. el detalle está en `docs/CHANGELOG-ISLAND.md`.

## no hecho todavía

- fase 1: variante lateral e inferior con contenido girado (hoy solo cambia la geometría y las esquinas); arrastre de la isla flotante.
- fase 2: vista previa real de diffs de Edit/Write (el hook solo envía la ruta); teclado directo en tarjetas (Enter y Esc) porque exige que la ventana sea clave y robaría el foco de la terminal; resultado de pruebas desde PostToolUse (no se verificó que Claude Code envíe el código de salida); presupuesto de tokens; mapa de sesiones y línea de tiempo con deslizador; paleta de comandos.
- fase 3: estiramiento escalonado del contenido, tarjetas con salida direccional, medidores interpolados, cola de animaciones con prioridades, silencio con No Molestar y durante llamadas, háptica.
- fase 4: modo companion y enviar al escritorio, pastillas configurables y barra de herramientas al hover, recap del lunes dentro de la isla, pausa activa, atajos configurables, onboarding, lectura en voz alta, demo guionizada ampliada, cadenas localizables.
- fase 5: ventana de ajustes, motor de temas, editor de sprites y mascotas personalizadas, reglas declarativas, perfiles, respaldos, paquetes importables. `ConfigStore` existe pero no está conectado a los ajustes de la app (que viven en UserDefaults).

## sin verificar en pantalla real

- altura efectiva de la barra con distintas escalas, autoocultar, pantalla completa, monitor externo, stage manager, dock y dos espacios.
- audio real, volumen y que `AVAudioEngine` arranque en la máquina del usuario.
- clic derecho y menús, y que Claude Code entregue ExitPlanMode por el hook de permisos.
- una medición a 60 fps de las transiciones.

- soltar archivos sobre la isla (arrastre detectado por el botón del ratón y el portapapeles de arrastre), el baile con música (permiso de automatización) y el brillo de color no se han visto en pantalla real.
