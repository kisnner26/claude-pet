# configuración local

claude pet guarda la configuración en `~/.claude-pet/config.json` con permisos `0600`. el archivo es datos, no código: no se ejecutan scripts, bibliotecas ni rutas importadas.

versión actual: `1`.

```json
{
  "layout": "flotante",
  "reduceMotion": false,
  "soundEnabled": true,
  "textScale": 1,
  "theme": "oscuro",
  "version": 1
}
```

valores permitidos: `layout` es `flotante` o `isla`; `theme` es `oscuro`, `grafito`, `crema` o `coral`; `textScale` va de `0.75` a `2`. los campos desconocidos, versiones incompatibles, json truncado y archivos mayores de 2 mb se rechazan conservando la última configuración válida.

```sh
.build/debug/ClaudePet --print-config
.build/debug/ClaudePet --validate-config /ruta/config.json
```
