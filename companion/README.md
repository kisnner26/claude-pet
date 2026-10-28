# Visto

App de iPhone y Apple Watch para aprobar los permisos de Claude Code desde claude pet, y ver cuánto queda de tu plan.

- claude pet escucha en tu red local y se anuncia por Bonjour (`_claudepet-visto._tcp`). No hay servidores ni cuentas.
- el canal va cifrado y autenticado (ChaCha20-Poly1305). La clave sale de un código de 12 caracteres que se muestra en claude pet (Ajustes → seguridad) y se escribe una vez en el móvil. Cambiar el código desconecta a todos los dispositivos.
- desde fuera solo se puede permitir o denegar esta vez, nunca «siempre»; lo de riesgo alto solo se puede denegar. El perímetro y las reglas ya se aplicaron antes de que un permiso llegue al móvil.
- además de los permisos, Visto sincroniza: estado en vivo de Claude y Codex (pensando, ejecutando, esperando) con su contexto restante, las últimas acciones, las preguntas de Claude con opciones (se responden con un toque; solo viajan los índices elegidos), avisos de «terminó» y «falló» con vibración distinta, el consumo del plan y el modo foco, que también se puede activar desde el móvil o el reloj. El iPhone guarda un historial corto de tus decisiones (herramienta, proyecto y resultado; nunca el comando).
- el iPhone avisa con botones Permitir y Denegar en la notificación y retransmite al reloj. Sin servidor de notificaciones, los avisos llegan mientras la app está activa o iOS la despierta por la red local.

## compilar

```sh
cd companion
xcodegen generate
xcodebuild -project Visto.xcodeproj -scheme Visto -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Visto.xcodeproj -scheme VistoWatch -destination 'generic/platform=watchOS' CODE_SIGNING_ALLOWED=NO build
```

Para instalar en tus dispositivos define `VISTO_TEAM_ID` y firma con tu equipo. `VistoCore` se prueba con `swift test` dentro de `companion/VistoCore`.
