# auditoría funcional

esta lista separa capacidades verificables de commits de documentación. cada bloque se considera funcional solo si tiene código ejecutable y una prueba o snapshot asociado.

## capacidades verificadas

- modos de isla, geometría del notch, selección de pantalla y tiempos de apertura (`--selftest-island`)
- animación de claude: respiración, mirada, parpadeo, toque, mareo, salto y reducir movimiento (`--selftest-island`, `--snapshot-poses`)
- mascota codex: caras, saludo, celebración, patrulla y estados del adaptador (`--selftest-companion`)
- permisos: permitir, denegar, siempre, cola, timeout, hook muerto y limpieza (`--selftest-permission`)
- preguntas: única, múltiple, cuatro preguntas, otra respuesta, recorte, controles y fallback (`--selftest-question`)
- terminal: resolución única, ambigüedad y rechazo de ventanas no compatibles (`--selftest-terminal`)
- ticker: herramienta, objetivo, deltas, antigüedad, copia y diff (`--selftest-steps`)
- contexto: porcentaje, presión, modelo, tokens usados, tokens disponibles, resumen y alerta crítica (`--selftest-safety`)
- mapa de archivos: peso, colores, staged, nuevos, conflicto y apertura de diff (`--selftest-mission`)
- mission control: filtros, orden, proyectos, exportación, resumen y salud git (`--selftest-mission-filter`, `--selftest-mission`)
- relevo, revisión, acciones, atajos, telemetría, limpieza, resistencia y demo (`--selftest-relay`, `--selftest-handoff`, `--selftest-actions`, `--selftest-shortcuts`, `--selftest-telemetry`, `--selftest-cleanup`, `--selftest-resistance`, `--selftest-demo`)
- accesibilidad y diagnóstico: etiquetas voiceover, tooltips, menús contextuales y copias de estado sin persistencia

## evidencia visual

- `--snapshot-island` inspeccionado después de cada bloque visual.
- `--snapshot-poses` inspeccionado para claude y codex.

## límites pendientes

- no se ha probado sobre el notch físico ni con voiceover real.
- no se ha probado el foco real de terminal, finder o mission control.
- el número de commits `feat:` no se usa como sustituto de capacidades independientes.
