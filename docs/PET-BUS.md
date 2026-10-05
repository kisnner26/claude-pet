# Pet bus v1

Bus local de presencia entre mascotas de escritorio. Solo sockets Unix del mismo usuario:
sin red externa, sin credenciales, sin telemetria. Nunca lleva conversaciones, prompts ni rutas.

## Topologia

Sin servidor central. Cada mascota **escucha** en su propio socket y **publica** en los de las demas.

```
~/.claude-pet/            (0700)
  pet.sock                privado: hooks de Claude Code -> app (no es parte del bus)
  bus/                    (0700)
    claude.sock           (0600) lo crea ClaudePet.app
    codex.sock            (0600) lo crea el adaptador de Codex
```

Descubrimiento: listar `bus/*.sock` y excluir el propio. Un socket sin oyente (`ECONNREFUSED`)
se ignora sin error; si el otro no existe no pasa nada. Nadie borra sockets ajenos.

## Mensaje

Una linea de JSON terminada en `\n`, **maximo 512 bytes**, una conexion por mensaje (conectar,
escribir, cerrar). Campos desconocidos se ignoran.

```json
{"v":1,"id":"claude","state":"thinking","project":"pc-acceso","ts":1791191284,"event":"working"}
```

| Campo | Tipo | Notas |
|---|---|---|
| `v` | entero | version del protocolo; obligatorio. Los mensajes con `v` distinta de 1 se ignoran |
| `id` | texto | `claude` o `codex` (regex `^[a-z0-9-]{1,16}$`). Un receptor ignora su propio id |
| `state` | texto | `idle starting thinking tool waiting done error`. Valor desconocido = presencia sin estado (se trata como `idle`) |
| `project` | texto, opcional | solo el nombre de la carpeta, nunca la ruta; max 40 caracteres. Claude lo omite salvo que actives "Compartir nombre del proyecto" |
| `ts` | numero | segundos Unix del emisor. Se descartan mensajes mas viejos que el ultimo de ese id |
| `event` | texto, opcional | `appeared`, `working`, `waiting`, `finished`, `error`, `left` |

Equivalencias de evento: `appeared` (arranque o primer contacto), `working` (entra en
starting/thinking/tool), `waiting` (espera aprobacion), `finished` (termino bien), `error`,
`left` (cierre ordenado). El latido no lleva `event`.

## Presencia y latido

- Al arrancar: publicar `appeared`. Al cambiar de estado: publicar con el `event` que corresponda.
- Latido: reenviar el estado actual cada **10 s**.
- Un par se considera ausente si no hay mensajes en **25 s** o si manda `left`.
  Asi se tolera que el otro proceso muera sin avisar.

## Que hace Claude Pet con un par

- Aparece un mini companero en la esquina superior izquierda; un pixel encima refleja su estado
  (pensando: se desplaza, herramienta: alterna, aprobacion: parpadea terracota, listo: fijo claro, error: oscuro).
- `appeared` o primer contacto: Claude saluda levantando el brazo izquierdo 3 s.
- `finished`: destellos de celebracion 2.5 s. `error`: marca de preocupacion 3 s.
- El menu muestra "Pet bus: codex presente" o "sin otras mascotas".

## Partido de futbol (visual, local, sin cambios de protocolo)

Claude Pet representa a Codex con su mini avatar y, solo con la presencia y el estado que ya
llegan por el bus v1, monta un partido breve y silencioso. No hay mensajes nuevos ni campos
nuevos: si el otro lado no lo conoce, no pasa nada.

| Regla | Detalle |
|---|---|
| Inicio | Claude y el par presentes, ambos en `idle`, durante 8 s seguidos |
| Frecuencia | como maximo un inicio cada 5 minutos (un partido cancelado tambien cuenta) |
| Cancelacion | al instante si cualquiera sale de `idle` (starting, thinking, tool, waiting, error; tambien done), si el par desaparece o si su estado es desconocido |
| Duracion | 12 s: el avatar de Codex entra caminando, patea a Claude, Claude cabecea y devuelve, otra vuelta, celebracion con confeti |
| Reducir movimiento | si el sistema lo pide, el avatar y la pelota aparecen con un fundido y quedan fijos, y el confeti es fijo; nada se desplaza |
| Escenario | una ventana transparente que no capta el raton, pegada a la mascota (a la izquierda; si no hay sitio, se refleja a la derecha). No cambia el tamano de la mascota ni su arrastre |

Menu de la barra > **Animaciones**: "Activar animaciones" (apagado, la mascota queda quieta y no hay partidos),
"Partido automatico con Codex", y disparadores inmediatos: "Partido de futbol ahora", "Saludo", "Celebracion del
par" y "Preocupacion". Un disparo manual ignora la espera, el cooldown, el estado de Claude y la presencia de Codex
(muestra un companero de demostracion) y dura entero; el partido manual cuenta para el cooldown automatico.
Desde la terminal, con la app abierta:

```sh
build/ClaudePet.app/Contents/MacOS/ClaudePet --trigger football   # greet | cheer | concern
```

Usa una notificacion local del sistema (`local.claudepet.trigger`) que solo acepta esos cuatro nombres.

Tras acabar, vuelve a exigir 8 s de inactividad compartida y el cooldown antes de otro partido.
Un estado desconocido del par cuenta como presencia, pero no como inactivo.

Codigo: `FootballGame.swift` (reglas, sin UI ni reloj propio), `FootballChoreography.swift`
(tiempo -> fotograma, funcion pura), `StageView.swift` (escenario: avatar grande, pelota con estela y sombra, polvo, destello, confeti) y las reacciones de Claude en `Sprite.swift`. Pruebas: `tests/football.sh`
(reglas con reloj falso en `ClaudePet --selftest-football`, y escenarios visuales).

## Adaptador de Codex (para otro proceso)

Este repo no controla ni lee Codex. Un adaptador es cualquier proceso tuyo que sepa en que estado
esta Codex por un medio publico (un hook o `notify` si su configuracion lo ofrece, un wrapper del
comando, etc.; revisa su documentacion, aqui no se asume ninguno) y lo publique al bus.

Contrato minimo para quien lo escriba:

1. Crear `~/.claude-pet/bus/codex.sock` (stream, modo 0600, carpeta 0700) y leer lineas JSON
   para recibir a Claude. Si no necesita recibir, puede no crearlo; entonces Claude no le publicara.
2. Enviar `appeared` al arrancar, estados con su `event`, latido cada 10 s y `left` al salir.
3. Verificar el uid del par en cada conexion (`getpeereid`/`SO_PEERCRED`) y limitar a 512 bytes.

Cliente de referencia en shell, ya usable:

```sh
bus/pet-bus-send.sh codex thinking working        # un mensaje
bus/pet-bus-send.sh codex waiting waiting
bus/pet-bus-send.sh codex done finished
bus/pet-bus-send.sh --hold codex idle             # presencia continua con latido y "left" al salir
echo thinking > ~/.claude-pet/bus/codex.state     # cambia el estado que reenvia --hold
```

Ejemplo de adaptador en Python (sin dependencias) para quien prefiera escribirlo asi:

```python
import json, os, socket, time, glob
BUS = os.path.expanduser("~/.claude-pet/bus")
def publish(state, event=None, project=None, me="codex"):
    m = {"v": 1, "id": me, "state": state, "ts": int(time.time())}
    if event: m["event"] = event
    if project: m["project"] = project
    data = (json.dumps(m, separators=(",", ":")) + "\n").encode()
    assert len(data) <= 512
    for p in glob.glob(f"{BUS}/*.sock"):
        if p.endswith(f"/{me}.sock"): continue
        try:
            s = socket.socket(socket.AF_UNIX); s.settimeout(0.3)
            s.connect(p); s.sendall(data)
        except OSError:
            pass          # el par no existe o murio: se ignora
        finally:
            s.close()
```

Pruebas: `tests/bus.sh` (con la app abierta) simula a Codex, manda mensajes invalidos y comprueba
que Claude publica a un par que escucha.
