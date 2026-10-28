import SwiftUI
import RealityKit
import ARKit
import Combine
import VistoCore

/// Realidad aumentada: las mascotas de claude pet como figuras de píxeles en 3D sobre tu mesa, con su estado en vivo.
/// Se puede jugar con ellas: tocarlas, acariciarlas, arrastrarlas, llamarlas, lanzarles una pelota, darles un premio y cambiarlas de tamaño.
/// Los permisos aparecen como tarjetas flotantes con sus botones; tocar «Permitir» o «Denegar» responde igual que en la pantalla.
struct ARScreen: View {
    @ObservedObject var model: PhoneModel
    @ObservedObject var client: VistoClient
    @Environment(\.dismiss) private var dismiss
    @State private var reset = 0
    @State private var placed = false
    @State private var command: ARCommand?

    var body: some View {
        ZStack(alignment: .top) {
            ARStage(client: client, reset: reset, command: $command, answer: { ask, allow in model.answer(ask, allow: allow) }, onPlaced: { placed = $0 }).ignoresSafeArea()
            HStack {
                Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).frame(width: 40, height: 40) }.buttonStyle(.glass).accessibilityLabel("Cerrar")
                Spacer()
                if placed { Button { reset += 1 } label: { Label("Reubicar", systemImage: "arrow.triangle.2.circlepath").font(.system(size: 14, weight: .semibold)).padding(.horizontal, 6) }.buttonStyle(.glass) }
            }.padding(.horizontal, 16).padding(.top, 8)
            VStack {
                Spacer()
                if placed {
                    HStack(spacing: 10) {
                        action("Llamar", "hand.wave.fill") { command = .call }
                        action("Premio", "gift.fill") { command = .treat }
                        action("Pelota", "soccerball") { command = .ball }
                        action("Saltar", "figure.jumprope") { command = .hop }
                    }.padding(10).glassEffect(.regular, in: .capsule).padding(.bottom, 26)
                    Text("Toca una mascota, mantén para acariciarla, arrástrala o pellizca para cambiar el tamaño.").font(.system(size: 11)).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center).padding(.horizontal, 32).padding(.bottom, 8)
                } else {
                    Text("Apunta a una mesa o al suelo y toca para colocar las mascotas.").font(.system(size: 14, weight: .medium)).multilineTextAlignment(.center).padding(14).glassEffect(.regular, in: .rect(cornerRadius: 18)).padding(.bottom, 40).padding(.horizontal, 24)
                }
            }
        }
        .background(Color.black)
    }

    private func action(_ title: String, _ symbol: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            VStack(spacing: 3) { Image(systemName: symbol).font(.system(size: 17, weight: .semibold)); Text(title).font(.system(size: 10, weight: .medium)) }.frame(width: 62, height: 46)
        }.buttonStyle(.plain)
    }
}

enum ARCommand: Equatable { case call, treat, ball, hop }

struct ARStage: UIViewRepresentable {
    @ObservedObject var client: VistoClient
    var reset: Int
    @Binding var command: ARCommand?
    var answer: (Ask, Bool) -> Void
    var onPlaced: (Bool) -> Void

    func makeCoordinator() -> ARCoordinator { ARCoordinator() }

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero)
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        config.environmentTexturing = .automatic
        view.session.run(config)
        let coaching = ARCoachingOverlayView()
        coaching.session = view.session; coaching.goal = .horizontalPlane; coaching.activatesAutomatically = true
        coaching.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(coaching)
        let c = context.coordinator
        let tap = UITapGestureRecognizer(target: c, action: #selector(ARCoordinator.tapped(_:)))
        let pan = UIPanGestureRecognizer(target: c, action: #selector(ARCoordinator.panned(_:))); pan.maximumNumberOfTouches = 1
        let pinch = UIPinchGestureRecognizer(target: c, action: #selector(ARCoordinator.pinched(_:)))
        let press = UILongPressGestureRecognizer(target: c, action: #selector(ARCoordinator.pressed(_:))); press.minimumPressDuration = 0.35
        for g in [tap, pan, pinch, press] as [UIGestureRecognizer] { g.delegate = c; view.addGestureRecognizer(g) }
        c.attach(view)
        return view
    }

    func updateUIView(_ view: ARView, context: Context) {
        let c = context.coordinator
        c.answer = answer; c.onPlaced = onPlaced
        if c.lastReset != reset { c.lastReset = reset; c.clear() }
        c.sync(agents: client.agents, asks: client.asks, plan: client.plan, feed: client.feed)
        if let cmd = command { c.run(cmd); DispatchQueue.main.async { command = nil } }
    }

    static func dismantleUIView(_ view: ARView, coordinator: ARCoordinator) { view.session.pause(); coordinator.stop() }
}

/// Una mascota en la escena: su figura, lo que hace y adonde va.
private struct ARPet {
    var entity: Entity
    var state = "idle"
    var home = SIMD3<Float>(0, 0, 0)
    var pos = SIMD3<Float>(0, 0, 0)
    var target: SIMD3<Float>?
    var yaw: Float = 0
    var reaction: Float = 0       // segundos que le quedan de reaccion (salto, giro)
    var spin: Float = 0
    var lastState = "idle"
}

private struct ARParticle { var e: Entity; var v: SIMD3<Float>; var age: Float = 0; var life: Float; var gravity: Bool; var shrink: Bool }

@MainActor
final class ARCoordinator: NSObject, UIGestureRecognizerDelegate {
    weak var view: ARView?
    var answer: (Ask, Bool) -> Void = { _, _ in }
    var onPlaced: (Bool) -> Void = { _ in }
    var lastReset = 0
    private var anchor: AnchorEntity?
    private var stage = Entity()
    private var cardRoot = Entity()
    private var labels = Entity()
    private var props = Entity()
    private var pets: [String: ARPet] = [:]
    private var particles: [ARParticle] = []
    private var ball: Entity?
    private var ballKicks = 0
    private var signature = ""
    private var asks: [String: Ask] = [:]
    private var feed: [Step] = []
    private var time: Float = 0
    private var updates: Cancellable?
    private var materials: [UInt32: SimpleMaterial] = [:]
    private var dragging: String?
    private var petting: String?
    private var pettingTimer: Float = 0
    private var pinchStart: Float = 1
    private var tapTimes: [String: [Float]] = [:]

    func attach(_ v: ARView) {
        view = v
        updates = v.scene.subscribe(to: SceneEvents.Update.self) { [weak self] e in self?.tick(Float(e.deltaTime)) }
    }

    func stop() { updates?.cancel(); updates = nil }

    func clear() {
        anchor?.removeFromParent(); anchor = nil; pets = [:]; signature = ""; particles = []; ball = nil
        stage = Entity(); cardRoot = Entity(); labels = Entity(); props = Entity()
        onPlaced(false)
    }

    func gestureRecognizer(_ a: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith b: UIGestureRecognizer) -> Bool { true }

    // MARK: encontrar cosas

    private func petName(at point: CGPoint) -> String? {
        var e: Entity? = view?.entity(at: point)
        while let cur = e { if cur.name.hasPrefix("pet:") { return String(cur.name.dropFirst(4)) }; e = cur.parent }
        return nil
    }

    private func floorPoint(_ p: CGPoint) -> SIMD3<Float>? {
        guard let view, let hit = view.raycast(from: p, allowing: .estimatedPlane, alignment: .horizontal).first else { return nil }
        let w = hit.worldTransform.columns.3
        let local = stage.convert(position: SIMD3(w.x, w.y, w.z), from: nil)
        return SIMD3(local.x, 0, local.z)
    }

    // MARK: gestos

    @objc func tapped(_ g: UITapGestureRecognizer) {
        guard let view else { return }
        let p = g.location(in: view)
        if anchor == nil {
            guard let hit = view.raycast(from: p, allowing: .estimatedPlane, alignment: .horizontal).first else { return }
            let a = AnchorEntity(raycastResult: hit)
            a.addChild(stage); stage.addChild(labels); stage.addChild(cardRoot); stage.addChild(props)
            view.scene.addAnchor(a)
            anchor = a; signature = ""
            onPlaced(true)
            return
        }
        // botones de los permisos
        var e: Entity? = view.entity(at: p)
        while let cur = e {
            if cur.name.hasPrefix("allow:") || cur.name.hasPrefix("deny:") {
                let allow = cur.name.hasPrefix("allow:"), id = String(cur.name.drop(while: { $0 != ":" }).dropFirst())
                if let ask = asks[id] { answer(ask, allow) }
                return
            }
            e = cur.parent
        }
        // una mascota: da un saltito y suelta corazones; muchos toques seguidos la marean
        if let name = petName(at: p) { boop(name); return }
        // el suelo: lanza una pelota y las mascotas van a por ella
        if let spot = floorPoint(p) { throwBall(at: spot) }
    }

    @objc func panned(_ g: UIPanGestureRecognizer) {
        guard let view else { return }
        let p = g.location(in: view)
        switch g.state {
        case .began: dragging = petName(at: p); if dragging != nil { Feel.shared.threshold() }
        case .changed:
            guard let n = dragging, var pet = pets[n], let spot = floorPoint(p) else { return }
            let clamped = clampToStage(spot)
            pet.home = clamped; pet.pos = clamped; pet.target = nil
            pets[n] = pet
        default: if let n = dragging { react(n, 0.6); Feel.shared.boop() }; dragging = nil
        }
    }

    @objc func pinched(_ g: UIPinchGestureRecognizer) {
        guard anchor != nil else { return }
        if g.state == .began { pinchStart = stage.scale.x }
        let s = max(0.5, min(3, pinchStart * Float(g.scale)))
        stage.scale = SIMD3(repeating: s)
    }

    @objc func pressed(_ g: UILongPressGestureRecognizer) {
        guard let view else { return }
        switch g.state {
        case .began: petting = petName(at: g.location(in: view)); pettingTimer = 0; if petting != nil { Feel.shared.cuddle() }
        case .ended, .cancelled, .failed: petting = nil
        default: break
        }
    }

    // MARK: acciones

    func run(_ c: ARCommand) {
        guard anchor != nil else { return }
        switch c {
        case .call:
            guard let cam = view?.cameraTransform.translation else { return }
            let local = stage.convert(position: cam, from: nil)
            let dir = SIMD3(local.x, 0, local.z)
            let len = max(0.001, simd_length(dir))
            let spot = dir / len * min(len - 0.25, 0.9)
            for (i, k) in pets.keys.sorted().enumerated() { pets[k]?.target = clampToStage(spot + SIMD3(Float(i) * 0.14 - 0.07, 0, 0)) }
            Feel.shared.boop()
        case .treat:
            for k in pets.keys.sorted() { react(k, 1.2); hearts(for: k, count: 6); confetti(at: pets[k]?.pos ?? .zero, count: 10) }
            Feel.shared.cheer()
        case .ball:
            throwBall(at: SIMD3(Float.random(in: -0.35...0.35), 0, Float.random(in: -0.1...0.35)))
        case .hop:
            for k in pets.keys { react(k, 0.7) }
            Feel.shared.boop()
        }
    }

    private func react(_ name: String, _ seconds: Float) { pets[name]?.reaction = seconds; pets[name]?.spin = 0 }

    private func boop(_ name: String) {
        react(name, 0.7); hearts(for: name, count: 2); Feel.shared.boop()
        var ts = (tapTimes[name] ?? []).filter { time - $0 < 2 }; ts.append(time); tapTimes[name] = ts
        if ts.count >= 4 { tapTimes[name] = []; pets[name]?.reaction = 1.6; pets[name]?.spin = 1; Feel.shared.denied() }   // demasiados toques: se marea
    }

    private func throwBall(at spot: SIMD3<Float>) {
        ball?.removeFromParent()
        let b = ModelEntity(mesh: .generateSphere(radius: 0.022), materials: [SimpleMaterial(color: UIColor(red: 0.91, green: 0.71, blue: 0.36, alpha: 1), roughness: 0.4, isMetallic: false)])
        let s = clampToStage(spot)
        b.position = [s.x, 0.25, s.z]; props.addChild(b); ball = b; ballKicks = 0
        for k in pets.keys { pets[k]?.target = s }
        Feel.shared.boop()
    }

    private func clampToStage(_ p: SIMD3<Float>) -> SIMD3<Float> {
        let r = simd_length(SIMD2(p.x, p.z)), maxR: Float = 0.9
        return r > maxR ? SIMD3(p.x / r * maxR, 0, p.z / r * maxR) : SIMD3(p.x, 0, p.z)
    }

    // MARK: contenido

    private func material(_ color: Color) -> SimpleMaterial {
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        let key = UInt32(r * 255) << 16 | UInt32(g * 255) << 8 | UInt32(b * 255)
        if let m = materials[key] { return m }
        let m = SimpleMaterial(color: ui, roughness: 0.55, isMetallic: false)
        materials[key] = m
        return m
    }

    private func voxelPet(_ art: PixelArt, name: String, cell: Float = 0.0072) -> Entity {
        let root = Entity()
        let mesh = MeshResource.generateBox(size: [cell, cell, cell * 1.7])
        let body = Entity()
        for (y, row) in art.rows.enumerated() {
            for (x, ch) in row.enumerated() {
                guard let color = art.palette[ch] else { continue }
                let m = ModelEntity(mesh: mesh, materials: [material(color)])
                m.position = [(Float(x) - Float(art.width) / 2) * cell, Float(art.height - 1 - y) * cell, 0]
                body.addChild(m)
            }
        }
        root.addChild(body)
        // una caja de colision para poder tocarla, acariciarla y arrastrarla
        let w = Float(art.width) * cell, h = Float(art.height) * cell
        root.name = "pet:" + name
        root.components.set(CollisionComponent(shapes: [ShapeResource.generateBox(size: [w, h, cell * 3]).offsetBy(translation: [0, h / 2, 0])]))
        return root
    }

    private func text(_ s: String, size: Float, color: UIColor = .white) -> ModelEntity {
        let mesh = MeshResource.generateText(s, extrusionDepth: 0.0008, font: .systemFont(ofSize: CGFloat(size), weight: .semibold), containerFrame: .zero, alignment: .center, lineBreakMode: .byTruncatingTail)
        let e = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: color)])
        let b = e.visualBounds(relativeTo: nil)
        e.position.x = -(b.max.x - b.min.x) / 2 - b.min.x
        return e
    }

    private func button(_ title: String, name: String, color: UIColor, x: Float) -> Entity {
        let b = ModelEntity(mesh: .generateBox(width: 0.07, height: 0.028, depth: 0.006, cornerRadius: 0.008), materials: [SimpleMaterial(color: color, isMetallic: false)])
        b.name = name; b.position = [x, 0, 0.004]
        b.generateCollisionShapes(recursive: false)
        let t = text(title, size: 0.014)
        t.position.z = 0.0045; t.position.y = -0.005; t.name = name
        b.addChild(t)
        return b
    }

    private func headline(for agent: String) -> String {
        guard let s = feed.last(where: { $0.agent == agent }) else { return "" }
        let target = (s.target as NSString).lastPathComponent
        return target.isEmpty ? s.tool : "\(s.tool) · \(target)"
    }

    func sync(agents: [AgentInfo], asks list: [Ask], plan: PlanSnapshot?, feed steps: [Step]) {
        feed = steps
        guard anchor != nil else { return }
        let sig = agents.map { "\($0.agent)\($0.state)\($0.project)\($0.contextRemaining ?? -1)" }.joined() + list.map(\.id).joined() + "\(plan?.five?.remaining() ?? -1)" + (steps.last?.id ?? "")
        guard sig != signature else { return }
        signature = sig
        asks = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })

        labels.children.forEach { $0.removeFromParent() }
        cardRoot.children.forEach { $0.removeFromParent() }
        let shown = agents.isEmpty ? [AgentInfo(agent: "claude", state: "idle", project: "", since: Date(), contextRemaining: nil)] : agents
        let gap: Float = 0.17
        for (i, a) in shown.enumerated() {
            let x = (Float(i) - Float(shown.count - 1) / 2) * gap
            if pets[a.agent] == nil {
                let e = voxelPet(a.agent == "codex" ? PixelArt.codex : PixelArt.claude, name: a.agent)
                var p = ARPet(entity: e); p.home = [x, 0, 0]; p.pos = p.home
                pets[a.agent] = p; stage.addChild(e)
            }
            // reacciones a lo que le pasa al agente: celebra al terminar, se sacude si falla
            if let prev = pets[a.agent]?.lastState, prev != a.state {
                if a.state == "done" { react(a.agent, 1.4); confetti(at: pets[a.agent]?.pos ?? .zero, count: 16); Feel.shared.cheer() }
                if a.state == "error" { react(a.agent, 1.0); sparks(at: pets[a.agent]?.pos ?? .zero) }
                if a.state == "waiting" { react(a.agent, 0.8) }
            }
            pets[a.agent]?.state = a.state; pets[a.agent]?.lastState = a.state
            let l = Entity(); l.name = "label:" + a.agent
            let title = text(VTFormat.agentName(a.agent) + " · " + VTFormat.state(a.state), size: 0.016, color: UIColor(VTFormat.stateColor(a.state)))
            l.addChild(title)
            var sub = headline(for: a.agent)
            if sub.isEmpty { sub = a.project }
            if let c = a.contextRemaining { sub += (sub.isEmpty ? "" : " · ") + "ctx \(c)%" }
            if !sub.isEmpty { let t = text(String(sub.prefix(38)), size: 0.011, color: UIColor.white.withAlphaComponent(0.72)); t.position.y = -0.02; l.addChild(t) }
            labels.addChild(l)
        }
        for key in Array(pets.keys) where !shown.contains(where: { $0.agent == key }) { pets[key]?.entity.removeFromParent(); pets[key] = nil }
        if let five = plan?.five {
            let l = Entity(); l.position = [0, 0.005, 0.13]; l.name = "label"
            l.addChild(text(L.t("Plan 5 h: queda \(five.remaining())%", "Plan 5 h: \(five.remaining())% left"), size: 0.012, color: UIColor(VT.blue)))
            labels.addChild(l)
        }
        for (i, ask) in list.prefix(2).enumerated() {
            let card = Entity(); card.position = [Float(i) * 0.19 - (list.count > 1 ? 0.095 : 0), 0.29, 0]; card.name = "label"
            let tint = UIColor(VT.riskColor(ask.risk))
            let bg = ModelEntity(mesh: .generateBox(width: 0.17, height: 0.085, depth: 0.004, cornerRadius: 0.01), materials: [SimpleMaterial(color: UIColor(white: 0.08, alpha: 1), isMetallic: false)])
            let edge = ModelEntity(mesh: .generateBox(width: 0.17, height: 0.003, depth: 0.005), materials: [UnlitMaterial(color: tint)]); edge.position = [0, 0.041, 0.0005]
            let title = text(L.t("Permiso: \(ask.tool)", "Permission: \(ask.tool)"), size: 0.014); title.position = [0, 0.018, 0.003]
            let sub = text(String(ask.project.prefix(26)), size: 0.01, color: UIColor.white.withAlphaComponent(0.65)); sub.position = [0, 0.004, 0.003]
            card.addChild(bg); card.addChild(edge); card.addChild(title); card.addChild(sub)
            let deny = button(L.tr("Denegar"), name: "deny:" + ask.id, color: UIColor(white: 0.25, alpha: 1), x: ask.canAllow ? -0.04 : 0)
            deny.position.y = -0.026; card.addChild(deny)
            if ask.canAllow {
                let allow = button(L.tr("Permitir"), name: "allow:" + ask.id, color: UIColor(VT.blue), x: 0.04)
                allow.position.y = -0.026; card.addChild(allow)
            }
            cardRoot.addChild(card)
        }
    }

    // MARK: particulas

    private func hearts(for name: String, count: Int) {
        guard let p = pets[name] else { return }
        let pink = UIColor(red: 0.95, green: 0.45, blue: 0.62, alpha: 1)
        let mesh = MeshResource.generateBox(size: [0.005, 0.005, 0.005])
        let pattern = [".X.X.", "XXXXX", "XXXXX", ".XXX.", "..X.."]
        for _ in 0..<count {
            let h = Entity()
            for (y, row) in pattern.enumerated() { for (x, ch) in row.enumerated() where ch == "X" {
                let m = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: pink)]); m.position = [(Float(x) - 2) * 0.005, Float(4 - y) * 0.005, 0]; h.addChild(m)
            } }
            h.position = p.pos + [Float.random(in: -0.04...0.04), 0.12 + Float.random(in: 0...0.03), 0.02]
            stage.addChild(h)
            particles.append(ARParticle(e: h, v: [Float.random(in: -0.02...0.02), 0.09, 0], life: 1.3, gravity: false, shrink: true))
        }
    }

    private func confetti(at pos: SIMD3<Float>, count: Int) {
        let colors: [UIColor] = [.systemOrange, .systemBlue, .systemGreen, .systemYellow, .systemPink]
        let mesh = MeshResource.generateBox(size: [0.006, 0.006, 0.002])
        for i in 0..<count {
            let e = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: colors[i % colors.count])])
            e.position = pos + [0, 0.14, 0]
            stage.addChild(e)
            particles.append(ARParticle(e: e, v: [Float.random(in: -0.15...0.15), Float.random(in: 0.18...0.34), Float.random(in: -0.15...0.15)], life: 1.5, gravity: true, shrink: true))
        }
    }

    private func sparks(at pos: SIMD3<Float>) {
        let mesh = MeshResource.generateBox(size: [0.004, 0.004, 0.004])
        for _ in 0..<10 {
            let e = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: UIColor(red: 0.85, green: 0.36, blue: 0.36, alpha: 1))])
            e.position = pos + [0, 0.1, 0]
            stage.addChild(e)
            particles.append(ARParticle(e: e, v: [Float.random(in: -0.2...0.2), Float.random(in: 0.1...0.25), Float.random(in: -0.2...0.2)], life: 0.9, gravity: true, shrink: true))
        }
    }

    // MARK: animacion

    private func turn(_ from: Float, toward to: Float, _ rate: Float) -> Float {
        var d = to - from
        while d > .pi { d -= 2 * .pi }; while d < -.pi { d += 2 * .pi }
        return from + d * min(1, rate)
    }

    private func tick(_ dt: Float) {
        time += dt
        guard anchor != nil else { return }
        let cam = view.map { stage.convert(position: $0.cameraTransform.translation, from: nil) }

        for name in Array(pets.keys) {
            guard var p = pets[name] else { continue }
            var y: Float = 0, sway: Float = 0, sy: Float = 1
            var heading: Float?
            // caminar hacia lo que quiere: la pelota, tu posicion o donde la dejaste
            if let t = p.target, dragging != name {
                let d = t - p.pos, dist = simd_length(SIMD2(d.x, d.z))
                if dist < 0.05 {
                    p.target = nil
                    if let b = ball, simd_length(SIMD2(b.position.x - t.x, b.position.z - t.z)) < 0.05 { kickBall(by: name) }
                } else {
                    let step = min(dist, 0.3 * dt)
                    p.pos += SIMD3(d.x, 0, d.z) / dist * step
                    heading = atan2(d.x, d.z)
                    y += abs(sin(time * 12)) * 0.012
                }
            } else if p.target == nil, dragging != name, simd_length(p.pos - p.home) > 0.02, ball == nil { p.target = p.home }
            // mirar al usuario cuando esta tranquila
            if heading == nil, let c = cam {
                let d = SIMD2(c.x - p.pos.x, c.z - p.pos.z)
                if simd_length(d) > 0.05 { heading = atan2(d.x, d.y) }
            }
            if let h = heading { p.yaw = turn(p.yaw, toward: h, 6 * dt) }

            switch p.state {
            case "thinking", "starting": sway = sin(time * 1.4) * 0.35
            case "tool": y += abs(sin(time * 6)) * 0.012
            case "waiting": y += abs(sin(time * 4)) * 0.03
            case "done": sway = sin(time * 3) * 0.25
            case "error": sway = sin(time * 40) * 0.05
            default: sy = 1 + 0.025 * sin(time * 1.6)
            }
            if p.reaction > 0 {
                p.reaction = max(0, p.reaction - dt)
                if p.spin > 0 { sway += time * 14; y += 0.01 }                       // mareada: gira sobre si misma
                else { y += abs(sin(p.reaction * 9)) * 0.05 }                        // contenta: saltitos
            }
            if petting == name {
                sy = 1 - 0.05 * abs(sin(time * 9))                                   // se aprieta de gusto
                pettingTimer += dt
                if pettingTimer > 0.45 { pettingTimer = 0; hearts(for: name, count: 1); Feel.shared.purr() }
            }
            let lift: Float = dragging == name ? 0.05 : 0
            p.entity.position = p.pos + SIMD3(0, 0.01 + y + lift, 0)
            p.entity.transform.rotation = simd_quatf(angle: p.yaw + sway, axis: [0, 1, 0])
            p.entity.scale = [1, sy, 1]
            pets[name] = p
        }

        // la pelota rebota donde esta
        if let b = ball { b.position.y = 0.022 + abs(sin(time * 5)) * 0.03 * (ballKicks < 99 ? 1 : 0) }

        // particulas
        var alive: [ARParticle] = []
        for var q in particles {
            q.age += dt
            if q.age >= q.life { q.e.removeFromParent(); continue }
            if q.gravity { q.v.y -= 0.9 * dt }
            q.e.position += q.v * dt
            if q.shrink { let k = max(0.05, 1 - q.age / q.life); q.e.scale = SIMD3(repeating: k) }
            alive.append(q)
        }
        particles = alive

        // etiquetas y tarjetas: encima de su mascota, mirando al usuario
        guard let camW = view?.cameraTransform.translation else { return }
        for node in Array(labels.children) {
            if node.name.hasPrefix("label:"), let p = pets[String(node.name.dropFirst(6))] { node.position = p.pos + [0, 0.19, 0] }
            else if node.position == .zero { node.position = [0, 0.005, 0.13] }
            face(node, camW)
        }
        for node in Array(cardRoot.children) { face(node, camW) }
    }

    private func face(_ node: Entity, _ cam: SIMD3<Float>) {
        let p = node.position(relativeTo: nil)
        node.look(at: SIMD3(cam.x, p.y, cam.z), from: p, relativeTo: nil)
        node.transform.rotation *= simd_quatf(angle: .pi, axis: [0, 1, 0])
    }

    /// Una mascota llega a la pelota y la empuja: sale rodando a otro sitio y las dos van tras ella.
    private func kickBall(by name: String) {
        guard let b = ball else { return }
        ballKicks += 1
        react(name, 0.8); Feel.shared.boop()
        if ballKicks >= 4 {
            for k in pets.keys { react(k, 1.2); hearts(for: k, count: 3) }
            confetti(at: SIMD3(b.position.x, 0, b.position.z), count: 12)
            b.removeFromParent(); ball = nil; Feel.shared.cheer()
            for k in Array(pets.keys) { let h = pets[k]?.home; pets[k]?.target = h }
            return
        }
        let a = Float.random(in: 0..<(2 * .pi))
        let next = clampToStage(SIMD3(b.position.x + cos(a) * 0.3, 0, b.position.z + sin(a) * 0.3))
        b.position.x = next.x; b.position.z = next.z
        for k in pets.keys { pets[k]?.target = next }
    }
}
