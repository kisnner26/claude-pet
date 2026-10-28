# Visto

App de iPhone y Apple Watch para aprobar los permisos de Claude Code desde claude pet, y ver cuánto queda de tu plan.

- claude pet escucha en tu red local y se anuncia por Bonjour (`_claudepet-visto._tcp`). No hay servidores ni cuentas.
- el canal va cifrado y autenticado (ChaCha20-Poly1305). La clave sale de un código de 12 caracteres que se muestra en claude pet (Ajustes → seguridad) y se escribe una vez en el móvil. Cambiar el código desconecta a todos los dispositivos.
- desde fuera solo se puede permitir o denegar esta vez, nunca «siempre»; lo de riesgo alto solo se puede denegar. El perímetro y las reglas ya se aplicaron antes de que un permiso llegue al móvil.
- el iPhone avisa con botones Permitir y Denegar en la notificación y retransmite al reloj. Sin servidor de notificaciones, los avisos llegan mientras la app está activa o iOS la despierta por la red local.

## compilar

```sh
cd companion
xcodegen generate
xcodebuild -project Visto.xcodeproj -scheme Visto -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Visto.xcodeproj -scheme VistoWatch -destination 'generic/platform=watchOS' CODE_SIGNING_ALLOWED=NO build
```

Para instalar en tus dispositivos define `VISTO_TEAM_ID` y firma con tu equipo. `VistoCore` se prueba con `swift test` dentro de `companion/VistoCore`.
