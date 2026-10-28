# ciudad

Cada repo de una carpeta es un edificio. La altura sale de sus commits, el ancho de sus archivos, las ventanas encendidas de la actividad de los últimos 30 días, la baliza roja de los cambios sin commit, las paredes del lenguaje y el techo del estado (activo, tranquilo, abandonado).

![ciudad](docs/img/ciudad.jpg)

## Uso

```bash
node bin/ciudad.js /ruta/a/tus/proyectos
```

Pasa el cursor sobre un edificio para ver el detalle. Arrastra, rueda y doble clic para moverte.

- Sin dependencias, Node 20 o superior.
- Solo lee git de los hijos directos de la carpeta; servidor de solo lectura en 127.0.0.1 con token.

```bash
node --test test/
```

MIT.
