import SwiftUI
import AppKit

/// `ClaudePet --snapshot-cinema <ruta.png>`: hoja de contacto de la isla viva. Cada fila congela un instante de un efecto
/// usando las mismas funciones puras que la app (curvas, animo, cierre, estela), asi lo que se ve es lo que corre.
enum CinemaSnapshot {
    private static let cream = Color(hex: 0xF4F1EA)

    private static func label(_ text: String) -> some View {
        Text(text).font(.system(size: 10, design: .monospaced)).foregroundColor(cream.opacity(0.62))
    }

    private static func mascot(_ pose: PetPose, state: PetState = .waiting, side: CGFloat = 56) -> some View {
        Canvas { gc, size in
            let px = PetAnimator.apply(Sprite.block(state, tick: 0), pose: pose)
            PetFace.draw(&gc, size: size, pixels: px, pose: pose)
        }.frame(width: side, height: side)
    }

    private static func pose(_ mood: PetMood, t: TimeInterval = 10.45, motion: Bool = true) -> PetPose {
        var p = PetPose(); IslandCinema.applyMood(&p, mood: mood, t: t, since: 10, motion: motion); return p
    }

    /// Una isla con la tarjeta de permiso congelada en `age` segundos de su entrada.
    @MainActor private static func island(age: Double, ask: PermissionAsk, mood: PetMood, risk: PermissionRisk, edge: Double? = nil, breath: Double? = nil) -> some View {
        let shape = IslandShape(radius: 30, corners: .bottom)
        return ZStack(alignment: .topLeading) {
            shape.fill(Color.black)
            HStack(alignment: .top, spacing: 16) {
                mascot(pose(mood), state: .waiting)
                PermissionCardView(store: PetStore.shared, ask: ask).environment(\.cinemaRevealAge, age)
            }
            .padding(.horizontal, 24).padding(.top, 28).padding(.bottom, 20)
            if let breath { shape.stroke(Color(hex: 0xD85C5C).opacity(breath), lineWidth: 2) }
            if let edge { EdgeSweepView(progress: edge, radius: 30, color: Color(hex: IslandCinema.accent(agent: 0xE0824F, risk: risk))) }
        }
        .frame(width: 560, height: 208)
        .clipShape(shape)
    }

    private static func finishCell(age: Double, color: UInt32) -> some View {
        ZStack {
            Color.black
            FinishBurstView(age: age, color: color, side: 132)
            mascot(pose(.neutral), state: .done, side: 40)
        }.frame(width: 132, height: 132).clipShape(RoundedRectangle(cornerRadius: 12))
    }

    static func demoTrail() -> [MissionEvent] {
        let now = Date()
        func e(_ s: Double, _ agent: String, _ st: PetState) -> MissionEvent { MissionEvent(at: now.addingTimeInterval(-s), agent: agent, state: st, project: "claude-pet") }
        return [
            e(0, "claude", .tool), e(14, "claude", .thinking), e(40, "claude", .tool), e(70, "claude", .waiting), e(95, "claude", .tool),
            e(125, "claude", .thinking), e(150, "claude", .done), e(175, "claude", .tool), e(215, "claude", .thinking), e(250, "claude", .error), e(262, "claude", .tool),
            e(20, "codex", .thinking), e(48, "codex", .tool), e(110, "codex", .thinking), e(135, "codex", .tool), e(168, "codex", .done), e(190, "codex", .thinking), e(235, "codex", .tool),
        ].sorted { $0.at > $1.at }
    }

    @MainActor static func render(to path: String) {
        IslandSnapshot.isRendering = true
        defer { IslandSnapshot.isRendering = false }
        let store = PetStore.shared
        let previous = store.permissionAsks
        defer { store.permissionAsks = previous }
        let medium = PermissionAsk(id: "c1", session: "s", tool: "Bash", project: "claude-pet", detail: "swift build -c release && tests/selftests.sh", canAlways: true, at: Date())
        let high = PermissionAsk(id: "c2", session: "s", tool: "Bash", project: "claude-pet", detail: "rm -rf build .swiftpm && git reset --hard", canAlways: false, at: Date())
        store.permissionAsks = [medium]
        let sweepFrames: [(Double, String)] = [(0.05, "0,05 s"), (0.15, "0,15 s"), (0.27, "0,27 s"), (0.4, "0,40 s"), (0.52, "0,52 s"), (0.62, "0,62 s")]

        let view = VStack(alignment: .leading, spacing: 14) {
            label("PERMISO  /  UNA PASADA DE LUZ + APARICION POR BLOQUES  /  6 FOTOGRAMAS")
            LazyVGrid(columns: [GridItem(.fixed(560), spacing: 14), GridItem(.fixed(560), spacing: 14)], spacing: 14) {
                ForEach(Array(sweepFrames.enumerated()), id: \.offset) { _, f in
                    VStack(alignment: .leading, spacing: 4) {
                        island(age: f.0, ask: medium, mood: .neutral, risk: .medium, edge: f.0 / IslandCinema.sweepDuration)
                        label(f.1)
                    }
                }
            }
            label("RIESGO ALTO  /  BORDE ROJO APAGADO QUE RESPIRA (EXHALA, INHALA)  /  ANIMO: PREOCUPADA")
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) { island(age: 9, ask: high, mood: .wary, risk: .high, breath: IslandCinema.breath(at: 0)); label("t = 0,0 s  alfa \(String(format: "%.2f", IslandCinema.breath(at: 0)))") }
                VStack(alignment: .leading, spacing: 4) { island(age: 9, ask: high, mood: .wary, risk: .high, breath: IslandCinema.breath(at: IslandCinema.breathPeriod / 2)); label("t = 1,6 s  alfa \(String(format: "%.2f", IslandCinema.breath(at: IslandCinema.breathPeriod / 2)))") }
            }
            label("MASCOTA  /  REPOSO, PREOCUPADA (RIESGO ALTO), INQUIETA (ENSAYO DESTRUCTIVO), ALIVIADA (ENSAYO LIMPIO): SUSPIRO Y CON EL SUSPIRO ASENTADO")
            HStack(spacing: 14) {
                ForEach(Array([("reposo", pose(.neutral)), ("preocupada", pose(.wary)), ("inquieta", pose(.uneasy, t: 10.3)),
                               ("aliviada: suspira", pose(.relieved, t: 10.45)), ("aliviada: asentada", pose(.relieved, t: 11.5))].enumerated()), id: \.offset) { _, c in
                    VStack(spacing: 4) { mascot(c.1, side: 96).background(Color.black); label(c.0) }
                }
            }
            label("TERMINO  /  UNA RAFAGA DE PIXELES Y UN ANILLO FINO QUE SE DISUELVE  /  CLAUDE Y CODEX")
            HStack(spacing: 10) {
                ForEach([0.06, 0.2, 0.36, 0.55, 0.8, 1.05], id: \.self) { age in
                    VStack(spacing: 4) { finishCell(age: age, color: 0xE0824F); label(String(format: "%.2f s", age)) }
                }
            }
            HStack(spacing: 10) {
                ForEach([0.06, 0.2, 0.36, 0.55, 0.8, 1.05], id: \.self) { age in finishCell(age: age, color: 0x5270E8) }
            }
            label("ESTELA DE SESION  /  PIXEL-ART, UNA COLUMNA POR TRAMO, CLAUDE ARRIBA Y CODEX ABAJO")
            SessionTrailView(events: demoTrail(), reduceMotion: true)
                .frame(width: 560).padding(14).background(RoundedRectangle(cornerRadius: 18).fill(Color(hex: 0x15161A)))
        }
        .padding(24).background(Color(hex: 0x0B0B0C))
        let r = ImageRenderer(content: view)
        r.scale = IslandSnapshot.scale
        guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }
}
