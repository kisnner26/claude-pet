# relay de Visto

Une la Mac y el móvil cuando no están en la misma red. Cero dependencias, un solo archivo de node (20 o superior).

```sh
node relay.js --port 7777                                 # en claro: lo que viaja ya va cifrado de extremo a extremo
node relay.js --port 443 --cert cert.pem --key key.pem    # con tls propio
```

Luego, en claude pet: Ajustes → permisos → «acceso remoto (relay)» con la dirección del servidor (`mi.servidor.com:7777`, y TLS si usas certificado). El QR de emparejamiento ya trae la dirección: al escanearlo, Visto la guarda. En Visto también se puede escribir a mano (Ajustes → Relay).

## cómo funciona

- la Mac abre dos conexiones al relay y las deja en espera: `HOST <sala>`. el móvil abre una: `JOIN <sala>`. el relay las empareja y, desde ahí, solo copia bytes de un lado al otro.
- sobre esa conexión corre el mismo canal cifrado de siempre (ChaCha20-Poly1305). La clave sale del código de emparejamiento, que el relay no conoce.
- la sala es un hash de una clave derivada del código con PBKDF2 (120 000 vueltas): quien ve la sala no puede sacar el código sin repetir esa derivación lenta.
- si no hay una Mac esperando, el móvil recibe `RELAYNOH` y se cierra. si la Mac se cae, vuelve a registrarse sola con esperas crecientes.

## lo que el relay puede y no puede ver

- **no puede** leer permisos, comandos, proyectos ni nada del contenido, ni hacerse pasar por la Mac: sin el código no completa el apretón de manos.
- **sí ve** que existe una sala, las IP que se conectan, cuándo y cuántos bytes. Por eso conviene que el servidor sea tuyo.
- el código tiene unos 58 bits: un relay que grabara tráfico podría intentar adivinarlo a fuerza bruta; la derivación lenta lo encarece mucho, pero no es imposible con medios enormes. Cambia el código desde claude pet si sospechas de un servidor.

## límites de serie

6 esperas por sala · 2 000 salas · 40 conexiones por IP · 30 intentos de unirse por minuto y por IP · el saludo debe llegar en 10 s · una Mac en espera caduca a los 15 min (se renueva sola) · una sesión sin tráfico caduca a la hora.

## desplegarlo

- **en casa**: abre el puerto de tu router hacia la máquina que lo ejecute, o usa una VPN como Tailscale y escribe su dirección.
- **en un servidor**: `docker run -d --restart unless-stopped -p 7777:7777 -v "$PWD":/app -w /app node:22-alpine node relay.js` o un servicio de systemd con `ExecStart=/usr/bin/node /opt/visto-relay/relay.js --port 7777`.
- **con tls**: detrás de Caddy o nginx (`reverse_proxy` de TCP, o el propio `--cert/--key`). Un TCP crudo con TLS delante basta.

## pruebas

```sh
node --test test/
```
