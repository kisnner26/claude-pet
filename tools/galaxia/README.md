# galaxia

Cada archivo de tu repo es una estrella. El tamaño sale de sus commits, el brillo de lo reciente que es, las nebulosas son las carpetas y las líneas unen archivos que cambian juntos.

![galaxia](docs/img/galaxia.jpg)

## Uso

```bash
node bin/galaxia.js /ruta/al/repo
```

Arrastra para moverte, rueda para acercar, doble clic para recentrar. El botón Reproducir muestra cómo nació el repo, estrella a estrella.

- Sin dependencias, Node 20 o superior.
- Solo lee el historial de git; el servidor es de solo lectura, en 127.0.0.1 y con token.

```bash
node --test test/
```

MIT.
