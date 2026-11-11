import SwiftUI
import AppKit

/// Estado de los ensayos en curso, uno por permiso pendiente. Vive en memoria y se vacia cuando el permiso se resuelve.
@MainActor final class RehearsalBoard: ObservableObject {
    static let shared = RehearsalBoard()

    enum Phase: Equatable {
        case running(since: Date)
        case done(Rehearsal.Report)
        case failed(Rehearsal.Failure)
    }

    @Published private(set) var phases: [String: Phase] = [:]

    func phase(_ id: String) -> Phase? { phases[id] }

    /// Lanza el ensayo de un permiso. Si ya hay uno para ese permiso no hace nada.
    func start(id: String, command: String, cwd: String) {
        guard phases[id] == nil else { return }
        phases[id] = .running(since: Date())
        Task {
            let result = await RehearsalRunner.rehearse(command: command, cwd: cwd)
            guard self.phases[id] != nil else { return }       // el permiso se resolvio mientras tanto
            switch result {
            case .success(let report): self.phases[id] = .done(report)
            case .failure(let why): self.phases[id] = .failed(why)
            }
        }
    }

    /// Olvida los ensayos de permisos que ya no estan pendientes.
    func prune(keeping ids: Set<String>) {
        let gone = phases.keys.filter { !ids.contains($0) }
        guard !gone.isEmpty else { return }
        for id in gone { phases[id] = nil }
    }
}

/// Que tan serio es lo que el ensayo vio. Decide el color del bloque.
enum RehearsalSeverity {
    case calm, changes, destructive, unknown

    static func of(_ r: Rehearsal.Report) -> RehearsalSeverity {
        let discards = (r.gitBefore?.dirty ?? 0) > (r.gitAfter?.dirty ?? 0)
        if !r.changes.deleted.isEmpty || discards || !r.homeWrites.isEmpty { return .destructive }
        if r.changes.isEmpty { return r.usesNetwork || r.timedOut ? .unknown : .calm }
        return .changes
    }

    var color: Color {
        switch self {
        case .calm: return Color(hex: 0x8FB89A)
        case .changes: return Color(hex: 0xE0824F)
        case .destructive: return Color(hex: 0xD85C5C)
        case .unknown: return Color.white.opacity(0.45)
        }
    }
}

/// El resultado del ensayo dentro de la tarjeta del permiso: una frase, la lista corta de lo que cambiaria y los avisos.
struct RehearsalStrip: View {
    let phase: RehearsalBoard.Phase
    @State private var pulse = false

    private func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight, design: .monospaced) }

    private func header(_ accent: Color, trailing: String) -> some View {
        HStack(spacing: 6) {
            Text(verbatim: L.t("ENSAYO", "REHEARSAL")).font(mono(9, .bold)).tracking(1.2).foregroundColor(accent)
            Text(verbatim: L.t("copia aislada · sin red", "isolated copy · no network")).font(mono(9)).foregroundColor(.white.opacity(0.42))
            Spacer(minLength: 4)
            Text(verbatim: trailing).font(mono(9)).foregroundColor(.white.opacity(0.55)).lineLimit(1)
        }
    }

    private func row(_ sign: String, _ text: String, _ color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(verbatim: sign).font(mono(10.5, .bold)).foregroundColor(color).frame(width: 9, alignment: .center)
            Text(verbatim: text).font(mono(10.5)).foregroundColor(.white.opacity(0.86)).lineLimit(1).truncationMode(.middle)
        }
    }

    private func frame<C: View>(_ accent: Color, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4, content: content)
            .padding(.leading, 10).padding(.trailing, 8).padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.055)))
            .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 1).fill(accent).frame(width: 2).padding(.vertical, 6).padding(.leading, 3) }
    }

    var body: some View {
        switch phase {
        case .running:
            let accent = Color(hex: 0xE0824F)
            frame(accent) {
                header(accent, trailing: "")
                HStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { i in
                        Rectangle().fill(accent).frame(width: 5, height: 5)
                            .opacity(IslandSnapshot.isRendering ? (i == 1 ? 1 : 0.35) : (pulse ? 1 : 0.25))
                            .animation(IslandSnapshot.isRendering ? nil : .easeInOut(duration: 0.5).repeatForever().delay(Double(i) * 0.16), value: pulse)
                    }
                    Text(verbatim: L.t("ejecutándolo en una copia del proyecto…", "running it on a copy of the project…")).font(mono(10.5)).foregroundColor(.white.opacity(0.75))
                }
                .onAppear { pulse = true }
            }
            .accessibilityLabel(Text(verbatim: L.t("ensayando el comando en una copia del proyecto", "rehearsing the command on a copy of the project")))
        case .failed(let why):
            let accent = Color.white.opacity(0.45)
            frame(accent) {
                header(accent, trailing: "")
                Text(verbatim: why.text).font(.system(size: 11)).foregroundColor(.white.opacity(0.75)).fixedSize(horizontal: false, vertical: true)
            }
        case .done(let r):
            let severity = RehearsalSeverity.of(r), accent = severity.color
            let red = RehearsalSeverity.destructive.color, amber = RehearsalSeverity.changes.color, green = RehearsalSeverity.calm.color
            frame(accent) {
                header(accent, trailing: Rehearsal.outcome(r))
                Text(verbatim: Rehearsal.headline(r)).font(.system(size: 12, weight: .semibold)).foregroundColor(.white).fixedSize(horizontal: false, vertical: true)
                ForEach(Rehearsal.grouped(r.changes.deleted, max: 3), id: \.self) { row("−", $0, red) }
                ForEach(Rehearsal.grouped(r.changes.modified, max: 3), id: \.self) { row("~", $0, amber) }
                ForEach(Rehearsal.grouped(r.changes.created, max: 3), id: \.self) { row("+", $0, green) }
                ForEach(Rehearsal.grouped(r.homeWrites.map { "~/" + $0 }, max: 2), id: \.self) { row("+", $0, red) }
                ForEach(Rehearsal.caveats(r), id: \.self) { note in
                    Text(verbatim: note).font(.system(size: 10)).foregroundColor(.white.opacity(0.58)).fixedSize(horizontal: false, vertical: true)
                }
            }
            .contextMenu {
                Button(L.t("copiar informe del ensayo", "copy rehearsal report"), systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(Rehearsal.text(r), forType: .string)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(verbatim: L.t("ensayo: ", "rehearsal: ") + Rehearsal.headline(r) + ". " + Rehearsal.outcome(r)))
        }
    }
}

extension IslandSnapshot {
    /// `ClaudePet --snapshot-rehearsal <ruta.png>`: el bloque del ensayo en sus estados, con informes inventados.
    @MainActor static func rehearsal(to path: String) {
        var wipe = Rehearsal.Report()
        wipe.changes.deleted = (0..<214).map { "build/o\($0).o" } + ["dist/app.js", "dist/app.css"]
        wipe.changes.modified = ["package-lock.json"]; wipe.changes.bytesDelta = -48_000_000; wipe.seconds = 1.24
        var reset = Rehearsal.Report()
        reset.changes.modified = ["Sources/Auth/Login.swift", "Sources/Auth/Session.swift", "README.md"]; reset.changes.deleted = ["Sources/Auth/Draft.swift"]
        reset.gitBefore = .init(head: "a1b2c3d", branch: "main", dirty: 4); reset.gitAfter = .init(head: "a1b2c3d", branch: "main", dirty: 0); reset.seconds = 0.31
        var build = Rehearsal.Report()
        build.changes.created = ["dist/index.html", "dist/app.js", "dist/app.css", "dist/img/logo.png"]; build.changes.bytesDelta = 320_000; build.seconds = 6.8
        var net = Rehearsal.Report()
        net.exitCode = 6; net.seconds = 0.4; net.usesNetwork = true
        var home = Rehearsal.Report()
        home.homeWrites = [".zshrc", ".config/tool/settings.json"]; home.blockedOutside = true; home.seconds = 0.2
        let phases: [RehearsalBoard.Phase] = [.running(since: Date()), .done(wipe), .done(reset), .done(build), .done(net), .done(home), .done(Rehearsal.Report()), .failed(.tooBig)]
        isRendering = true
        defer { isRendering = false }
        let view = VStack(spacing: 10) { ForEach(Array(phases.enumerated()), id: \.offset) { RehearsalStrip(phase: $0.element) } }
            .padding(18).frame(width: 440).background(Color.black)
        let r = ImageRenderer(content: view); r.scale = 2
        guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }
}
