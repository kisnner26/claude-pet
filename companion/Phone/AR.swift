import SwiftUI
import RealityKit
import ARKit
import Combine
import VistoCore

/// Realidad aumentada: las mascotas de claude pet como figuras de píxeles en 3D sobre tu mesa, con su estado en vivo.
/// Los permisos aparecen como tarjetas flotantes con sus botones; tocar «Permitir» o «Denegar» responde igual que en la pantalla.
struct ARScreen: View {
    @ObservedObject var model: PhoneModel
    @ObservedObject var client: VistoClient
    @Environment(\.dismiss) private var dismiss
    @State private var reset = 0
    @State private var placed = false

    var body: some View {
        ZStack(alignment: .top) {
            ARStage(client: client, reset: reset, answer: { ask, allow in model.answer(ask, allow: allow) }, onPlaced: { placed = $0 }).ignoresSafeArea()
            HStack {
                Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).frame(width: 40, height: 40) }.buttonStyle(.glass).accessibilityLabel("Cerrar")
                Spacer()
                if placed { Button { reset += 1 } label: { Label("Reubicar", systemImage: "arrow.triangle.2.circlepath").font(.system(size: 14, weight: .semibold)).padding(.horizontal, 6) }.buttonStyle(.glass) }
            }.padding(.horizontal, 16).padding(.top, 8)
            if !placed {
                VStack { Spacer(); Text("Apunta a una mesa o al suelo y toca para colocar las mascotas.").font(.system(size: 14, weight: .medium)).multilineTextAlignment(.center).padding(14).glassEffect(.regular, in: .rect(cornerRadius: 18)).padding(.bottom, 40).padding(.horizontal, 24) }
            }
        }
        .background(Color.black)
    }
}

struct ARStage: UIViewRepresentable {
    @ObservedObject var client: VistoClient
    var reset: Int
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
        view.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(ARCoordinator.tapped(_:))))
        context.coordinator.attach(view)
        return view
    }

    func updateUIView(_ view: ARView, context: Context) {
        let c = context.coordinator
        c.answer = answer; c.onPlaced = onPlaced
        if c.lastReset != reset { c.lastReset = reset; c.clear() }
        c.sync(agents: client.agents, asks: client.asks, plan: client.plan)
    }

    static func dismantleUIView(_ view: ARView, coordinator: ARCoordinator) { view.session.pause(); coordinator.stop() }
}

@MainActor
final class ARCoordinator: NSObject {
    weak var view: ARView?
    var answer: (Ask, Bool) -> Void = { _, _ in }
    var onPlaced: (Bool) -> Void = { _ in }
    var lastReset = 0
    private var anchor: AnchorEntity?
    private var stage = Entity()
    private var pets: [String: (entity: Entity, state: String)] = [:]
    private var cardRoot = Entity()
    private var labels = Entity()
    private var signature = ""
    private var asks: [String: Ask] = [:]
    private var time: Float = 0
    private var updates: Cancellable?
    private var materials: [UInt32: SimpleMaterial] = [:]

    func attach(_ v: ARView) {
        view = v
        updates = v.scene.subscribe(to: SceneEvents.Update.self) { [weak self] e in self?.tick(Float(e.deltaTime)) }
    }

    func stop() { updates?.cancel(); updates = nil }

    func clear() {
        anchor?.removeFromParent(); anchor = nil; pets = [:]; signature = ""
        stage = Entity(); cardRoot = Entity(); labels = Entity()
        onPlaced(false)
    }

    // MARK: colocar y tocar

    @objc func tapped(_ g: UITapGestureRecognizer) {
        guard let view else { return }
        let p = g.location(in: view)
        if anchor == nil {
            guard let hit = view.raycast(from: p, allowing: .estimatedPlane, alignment: .horizontal).first else { return }
            let a = AnchorEntity(raycastResult: hit)
            a.addChild(stage); stage.addChild(labels); stage.addChild(cardRoot)
            view.scene.addAnchor(a)
            anchor = a
            signature = ""
            onPlaced(true)
            return
        }
        guard let hit = view.entity(at: p) else { return }
        var e: Entity? = hit
        while let cur = e {
            if cur.name.hasPrefix("allow:") || cur.name.hasPrefix("deny:") {
                let allow = cur.name.hasPrefix("allow:"), id = String(cur.name.drop(while: { $0 != ":" }).dropFirst())
                if let ask = asks[id] { answer(ask, allow) }
                return
            }
            e = cur.parent
        }
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

    private func voxelPet(_ art: PixelArt, cell: Float = 0.0072) -> Entity {
        let root = Entity()
        let mesh = MeshResource.generateBox(size: [cell, cell, cell * 1.7])
        for (y, row) in art.rows.enumerated() {
            for (x, ch) in row.enumerated() {
                guard let color = art.palette[ch] else { continue }
                let m = ModelEntity(mesh: mesh, materials: [material(color)])
                m.position = [(Float(x) - Float(art.width) / 2) * cell, Float(art.height - 1 - y) * cell, 0]
                root.addChild(m)
            }
        }
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

    func sync(agents: [AgentInfo], asks list: [Ask], plan: PlanSnapshot?) {
        guard anchor != nil else { return }
        let sig = agents.map { "\($0.agent)\($0.state)\($0.project)\($0.contextRemaining ?? -1)" }.joined() + list.map(\.id).joined() + "\(plan?.five?.remaining() ?? -1)"
        guard sig != signature else { return }
        signature = sig
        asks = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })

        labels.children.forEach { $0.removeFromParent() }
        cardRoot.children.forEach { $0.removeFromParent() }
        let shown = agents.isEmpty ? [AgentInfo(agent: "claude", state: "idle", project: "", since: Date(), contextRemaining: nil)] : agents
        let gap: Float = 0.17
        for (i, a) in shown.enumerated() {
            let x = (Float(i) - Float(shown.count - 1) / 2) * gap
            if pets[a.agent]?.entity.parent == nil || pets[a.agent] == nil {
                let pet = voxelPet(a.agent == "codex" ? PixelArt.codex : PixelArt.claude)
                pets[a.agent] = (pet, a.state); stage.addChild(pet)
            }
            pets[a.agent]?.state = a.state
            pets[a.agent]?.entity.position = [x, 0.01, 0]
            let l = Entity(); l.position = [x, 0.17, 0]; l.name = "label"
            let title = text(VTFormat.agentName(a.agent) + " · " + VTFormat.state(a.state), size: 0.016, color: UIColor(VTFormat.stateColor(a.state)))
            l.addChild(title)
            var sub = a.project
            if let c = a.contextRemaining { sub += (sub.isEmpty ? "" : " · ") + "ctx \(c)%" }
            if !sub.isEmpty { let t = text(sub, size: 0.011, color: UIColor.white.withAlphaComponent(0.7)); t.position.y = -0.02; l.addChild(t) }
            labels.addChild(l)
        }
        for (k, key) in pets.keys.enumerated() where !shown.contains(where: { $0.agent == key }) { pets[key]?.entity.removeFromParent(); pets[key] = nil; _ = k }
        if let five = plan?.five {
            let l = Entity(); l.position = [0, 0.005, 0.1]; l.name = "label"
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

    // MARK: animacion

    private func tick(_ dt: Float) {
        time += dt
        guard anchor != nil else { return }
        for (_, p) in pets {
            let e = p.entity
            var y: Float = 0.01, rot: Float = 0, dx: Float = 0, sy: Float = 1
            switch p.state {
            case "thinking", "starting": rot = sin(time * 1.4) * 0.45
            case "tool": y += abs(sin(time * 6)) * 0.012
            case "waiting": y += abs(sin(time * 4)) * 0.03
            case "done": rot = time * 3
            case "error": dx = sin(time * 40) * 0.003
            default: sy = 1 + 0.025 * sin(time * 1.6)
            }
            e.position.y = y; e.position.x += (dx - 0) * 0
            e.transform.rotation = simd_quatf(angle: rot, axis: [0, 1, 0])
            e.scale = [1, sy, 1]
        }
        // las tarjetas y etiquetas miran siempre al usuario
        guard let cam = view?.cameraTransform.translation else { return }
        for node in Array(labels.children) + Array(cardRoot.children) {
            let p = node.position(relativeTo: nil)
            node.look(at: SIMD3(cam.x, p.y, cam.z), from: p, relativeTo: nil)
            node.transform.rotation *= simd_quatf(angle: .pi, axis: [0, 1, 0])
        }
    }
}
