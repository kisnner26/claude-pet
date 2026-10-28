# taller de plugins

Catálogo público de plugins de claude-pet. Se ve y se instala desde Ajustes → plugins → taller.

## publicar un plugin

1. haz un fork de este repositorio.
2. crea `workshop/plugins/<id>/` con tu `plugin.json` y tus scripts (guía: [docs/PLUGINS.md](../docs/PLUGINS.md)). el `id` es el nombre de la carpeta: minúsculas, números y guiones.
3. ejecuta `python3 workshop/build.py`. valida tu plugin y genera `workshop/packages/<id>-<versión>.zip` y `workshop/index.json`.
4. abre un pull request con la carpeta, el zip y el índice. la CI ejecuta `python3 workshop/build.py --check`.

para publicar una versión nueva sube la `version` (x.y.z) del manifiesto y repite.

## reglas

- permisos mínimos: pide solo lo que usas. quien instale verá la lista antes de activar.
- sin enlaces simbólicos, sin binarios opacos, máximo 2 MB y 200 archivos.
- los scripts deben ser legibles: se revisan a mano antes de aceptar el pull request.
- nada que envíe datos del usuario a servidores propios, que descargue y ejecute código remoto ni que toque archivos fuera de su carpeta de datos (`$CLAUDE_PET_DATA_DIR`).

## cómo se protege quien instala

- el paquete se descarga solo por https desde hosts de GitHub y se instala si su huella sha256 coincide con la del índice.
- el id, la versión y los permisos del `plugin.json` deben ser los mismos que anuncia el índice.
- se instala siempre desactivado. al activarlo, claude-pet muestra los permisos y espera tu aprobación.
- los plugins no corren en una caja de arena: tienen los privilegios de tu usuario. por eso existe la revisión previa y por eso conviene activar solo los de autores de confianza.

## pruebas

```sh
sh tests/workshop.sh
```

comprueba que el catálogo está al día, que cada plugin se instala y que los paquetes manipulados (huella, permisos, id, host, enlaces, rutas con `..`) se rechazan.
