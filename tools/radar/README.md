# radar

Vigila tus servicios (github, npm, icloud...) y te dice qué falla y cómo arreglarlo. Compara el DNS de tu equipo con Cloudflare y Google: si el sistema no resuelve pero los públicos sí, te da los comandos exactos.

![radar](docs/img/radar.jpg)

## Uso

```bash
node bin/radar.js                 # vigila los hosts por defecto
node bin/radar.js gitlab.com --port 4848
```

Cada 30 s sondea DNS del sistema, 1.1.1.1, 8.8.8.8 y conexión TCP al 443. El diagnóstico distingue: todo bien, lento, DNS local roto, sin red y puerto cerrado.

- Sin dependencias, Node 20 o superior.
- Solo escucha en 127.0.0.1, con token por proceso y validación de Host y Origin.
- Los nombres de host se validan; los comandos sugeridos nunca incluyen texto sin comprobar.

```bash
node --test test/
```

MIT.
