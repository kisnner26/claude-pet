import SwiftUI

private func fxColor(_ hex: UInt32, _ alpha: Double = 1) -> Color { Color(hex: hex).opacity(alpha) }

/// Dibuja puntos de un efecto en una caja. Cada punto es un cuadrado de `size * unit` (pixel-art).
struct FxCanvas: View {
    let pixels: [FxPixel]
    var unit: CGFloat = 3
    var body: some View {
        Canvas { gc, size in
            for p in pixels {
                let s = CGFloat(p.size) * unit
                gc.fill(Path(CGRect(x: CGFloat(p.x) * size.width - s / 2, y: CGFloat(p.y) * size.height - s / 2, width: s, height: s)), with: .color(fxColor(p.color, p.alpha)))
            }
        }
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// Ondas que salen de la mascota cuando hay un permiso o una pregunta esperando, del color del riesgo.
/// Con un anillo que se vacia: lo que queda para que Claude Code pregunte en la terminal.
struct AlertPulseView: View {
    let color: UInt32
    /// Cuando llego la peticion; nil = sin cuenta atras (el anillo queda lleno).
    var askedAt: Date?
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let remaining = askedAt.map { AlertPulse.remaining(since: $0, now: ctx.date) } ?? 1
            Canvas { gc, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2), base = min(size.width, size.height) / 2
                for ring in AlertPulse.rings(at: t) {
                    let r = base * (0.55 + 0.45 * CGFloat(ring.progress))
                    gc.stroke(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)), with: .color(fxColor(color, ring.alpha)), lineWidth: 2)
                }
                var arc = Path()
                arc.addArc(center: center, radius: base * 0.52, startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * remaining), clockwise: false)
                gc.stroke(arc, with: .color(fxColor(color, 0.9)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }
        }
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// Reloj de arena del pomodoro.
struct HourglassView: View {
    let top: Double
    var body: some View {
        FxCanvas(pixels: Hourglass.pixels(top: top).map { FxPixel(x: ($0.x + 0.5) / 9, y: ($0.y + 0.5) / 13, size: 1, color: $0.color, alpha: $0.alpha) }, unit: 3)
            .frame(width: 27, height: 39)
            .accessibilityElement().accessibilityLabel("reloj de arena del temporizador")
    }
}

/// El nivel de contexto como un liquido que llena la isla desde abajo, con olas.
struct LiquidView: View {
    let level: Double
    let color: UInt32
    let amplitude: Double
    var animated = true
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15.0, paused: !animated)) { ctx in
            let t = animated ? ctx.date.timeIntervalSinceReferenceDate : 0
            Canvas { gc, size in
                let line = LiquidModel.surface(at: t, level: level, amplitude: amplitude, width: size.width, height: size.height)
                var path = Path()
                path.move(to: CGPoint(x: 0, y: size.height))
                for p in line { path.addLine(to: p) }
                path.addLine(to: CGPoint(x: size.width, y: size.height))
                path.closeSubpath()
                gc.fill(path, with: .linearGradient(Gradient(colors: [fxColor(color, 0.30), fxColor(color, 0.06)]), startPoint: CGPoint(x: 0, y: size.height * (1 - level)), endPoint: CGPoint(x: 0, y: size.height)))
                // la cresta brilla un poco
                var crest = Path(); crest.addLines(line)
                gc.stroke(crest, with: .color(fxColor(color, 0.45)), lineWidth: 1)
            }
        }
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// Aurora: fondo de luz que ondula con el color del estado. MeshGradient (GPU) donde existe; si no, nada.
struct AuroraView: View {
    let color: UInt32
    var animated = true
    var body: some View {
        if #available(macOS 15.0, *) {
            TimelineView(.animation(minimumInterval: 1.0 / 15.0, paused: !animated)) { ctx in
                let t = animated ? ctx.date.timeIntervalSinceReferenceDate : 0
                let w = Float(sin(t * 0.5)) * 0.08, v = Float(cos(t * 0.42)) * 0.08
                MeshGradient(width: 3, height: 3, points: [
                    [0, 0], [0.5 + w, 0], [1, 0],
                    [0, 0.5 + v], [0.5 - v, 0.5 + w], [1, 0.5 - v],
                    [0, 1], [0.5 - w, 1], [1, 1],
                ], colors: [
                    .clear, fxColor(color, 0.30), .clear,
                    fxColor(color, 0.12), .clear, fxColor(color, 0.22),
                    .clear, fxColor(color, 0.14), .clear,
                ])
                .blur(radius: 8)
            }
            .allowsHitTesting(false).accessibilityHidden(true)
        }
    }
}

/// El mundo de la mascota: clima y detalles segun el estado, detras de ella.
struct StageSceneView: View {
    let state: PetState
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12.0)) { ctx in
            let hour = Calendar.current.component(.hour, from: ctx.date)
            FxCanvas(pixels: StageScene.particles(at: ctx.date.timeIntervalSinceReferenceDate, state: state, hour: hour), unit: 3)
        }
    }
}

/// Lineas añadidas y quitadas que caen hacia la mascota tras una edicion, con sus contadores.
struct LineRainView: View {
    let since: TimeInterval
    let added: Int
    let deleted: Int
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { ctx in
            let now = ProcessInfo.processInfo.systemUptime
            if now - since < LineRain.duration {
                ZStack(alignment: .top) {
                    FxCanvas(pixels: LineRain.drops(at: now, since: since, added: added, deleted: deleted), unit: 3)
                    let c = LineRain.counters(age: now - since, added: added, deleted: deleted)
                    HStack(spacing: 6) {
                        Text("+\(c.added)").foregroundColor(fxColor(0x6CCB8A))
                        Text("−\(c.deleted)").foregroundColor(fxColor(0xD85C5C))
                    }
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(Color.black.opacity(0.55)))
                    .opacity(min(1, (LineRain.duration - (now - since)) * 2))
                }
            }
        }
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// Halo y estrellitas que orbitan segun el nivel real de actividad.
struct EvolutionView: View {
    let level: Int
    var body: some View {
        let tier = Evolution.tier(level: level)
        if tier > 0 {
            ZStack {
                Circle().fill(RadialGradient(colors: [Color(hex: 0xFFE9A8).opacity(Evolution.auraAlpha(tier: tier)), .clear], center: .center, startRadius: 0, endRadius: 56))
                TimelineView(.animation(minimumInterval: 1.0 / 15.0)) { ctx in
                    FxCanvas(pixels: Evolution.orbit(at: ctx.date.timeIntervalSinceReferenceDate, tier: tier), unit: 3)
                }
            }
            .allowsHitTesting(false).accessibilityHidden(true)
        }
    }
}

/// Los tres segundos de cine al terminar una tarea: los archivos con mas cambios pasan con zoom y el total sube.
struct TrailerView: View {
    let files: [Trailer.File]
    let start: Date
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { ctx in
            let f = Trailer.frame(at: ctx.date.timeIntervalSince(start), files: files)
            VStack(alignment: .leading, spacing: 6) {
                Text(f.caption.isEmpty ? " " : f.caption)
                    .font(.system(size: 20, weight: .bold)).foregroundColor(.white).lineLimit(1)
                    .scaleEffect(f.zoom, anchor: .leading)
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("+\(f.added)").foregroundColor(Color(hex: 0x6CCB8A))
                    Text("−\(f.deleted)").foregroundColor(Color(hex: 0xD85C5C))
                }
                .font(.system(size: 32, weight: .heavy, design: .rounded)).monospacedDigit()
                ProgressView(value: min(1, ctx.date.timeIntervalSince(start) / Trailer.duration)).progressViewStyle(.linear).tint(Color(hex: 0x6CCB8A)).frame(width: 220)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement().accessibilityLabel("resumen de la tarea")
    }
}

/// Gotas negras que cuelgan del borde de la isla al abrirse. Con desenfoque y umbral alfa se funden con el borde como metal liquido.
struct GooeyDripsView: View {
    let width: CGFloat
    let start: TimeInterval
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { ctx in
            let age = ProcessInfo.processInfo.systemUptime - start
            let blobs = Gooey.blobs(age: age)
            if !blobs.isEmpty {
                Canvas { gc, size in
                    gc.addFilter(.alphaThreshold(min: 0.5, color: .black))
                    gc.addFilter(.blur(radius: 6))
                    gc.drawLayer { layer in
                        // una franja en el borde de la isla, para que las gotas cuelguen de algo
                        layer.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: size.width, height: 8), cornerRadius: 4), with: .color(.black))
                        for b in blobs {
                            let cx = CGFloat(b.x) * size.width, cy = 6 + CGFloat(b.drop), r = CGFloat(b.radius)
                            layer.fill(Path(ellipseIn: CGRect(x: cx - r, y: cy - r * 1.15, width: r * 2, height: r * 2.3)), with: .color(.black))
                        }
                    }
                }
                .frame(width: width, height: 44)
            }
        }
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// Llama que arde junto al contador de racha y crece con los dias seguidos.
struct StreakFireView: View {
    let streak: Int
    var body: some View {
        if StreakFire.tier(streak: streak) > 0 {
            TimelineView(.animation(minimumInterval: 1.0 / 12.0)) { ctx in
                FxCanvas(pixels: StreakFire.pixels(at: ctx.date.timeIntervalSinceReferenceDate, streak: streak), unit: 2.6)
            }
            .frame(width: 24, height: 32)
            .accessibilityHidden(true)
        }
    }
}

/// Onda azul que sale de la mascota con cada herramienta que usa el agente.
struct ActivityPingView: View {
    let since: TimeInterval
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { _ in
            if let ring = ActivityPing.ring(age: ProcessInfo.processInfo.systemUptime - since) {
                Canvas { gc, size in
                    let base = min(size.width, size.height) / 2, r = base * (0.5 + 0.5 * CGFloat(ring.progress))
                    gc.stroke(Path(ellipseIn: CGRect(x: size.width / 2 - r, y: size.height / 2 - r, width: r * 2, height: r * 2)), with: .color(Color(hex: 0x7C93F0).opacity(ring.alpha)), lineWidth: 1.5)
                }
            }
        }
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}
