import SwiftUI
import AppKit

extension SettingsPage {
    var subtitle: String {
        switch self {
        case .resumen: return "lo que ha pasado hoy y esta semana, y el estado de tus agentes."
        case .apariencia: return "dónde sale la isla, qué enseña y cómo se ven las mascotas."
        case .comportamiento: return "cuándo asoma, cuánto tarda en plegarse y cuándo aparece sola."
        case .agentes: return "qué agentes vigila claude-pet y qué detalle enseña de cada uno."
        case .permisos: return "responder desde la isla, reglas de aprobación y puntos de restauración."
        case .perimetro: return "por dónde puede moverse el agente en cada proyecto, comprobado en el permiso antes de que algo cambie."
        case .privacidad: return "todo se queda en tu Mac. aquí decides qué se comparte y qué se borra."
        case .guardarropa: return "atuendos que se desbloquean al subir de nivel."
        case .sonidos: return "volumen por categoría, prueba de cada sonido y tus propios archivos."
        case .musica: return "reproductor de Spotify y Apple Music en la isla, y cómo reacciona la mascota."
        case .foco: return "silencia lo que no importa y trabaja por ciclos."
        case .atajos: return "combinaciones globales. siempre con control y opción más la letra que elijas."
        case .copia: return "exporta tus ajustes, impórtalos en otro Mac o vuelve a empezar."
        case .acerca: return "versión, herramientas relacionadas y dónde vive cada dato."
        }
    }
}

struct SettingsView: View {
    @ObservedObject var store: PetStore
    @State private var page: SettingsPage
    @State private var query = ""
    private let fixedSize: Bool

    init(store: PetStore, page: SettingsPage = .resumen, fixedSize: Bool = false) {
        self.store = store
        self.fixedSize = fixedSize
        _page = State(initialValue: page)
    }

    private var results: [SettingsPage] { SettingsPage.matching(query) }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(SettingsTheme.line).frame(width: 1)
            content
        }
        .frame(minWidth: 940, idealWidth: 980, minHeight: 640, idealHeight: 700)
        .frame(width: fixedSize ? 980 : nil, height: fixedSize ? 700 : nil)
        .background(SettingsTheme.background)
        .preferredColorScheme(.dark)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(SettingsTheme.mute)
                TextField("buscar un ajuste", text: $query).textFieldStyle(.plain).font(.system(size: 13))
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(SettingsTheme.mute) }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Capsule().fill(Color.white.opacity(0.07)))
            .overlay(Capsule().stroke(SettingsTheme.line, lineWidth: 1))
            .padding(.horizontal, 14).padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(SettingsGroup.allCases) { group in
                        let pages = results.filter { $0.group == group }
                        if !pages.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(group.title.uppercased())
                                    .font(.system(size: 9.5, weight: .medium, design: .monospaced)).tracking(1.5)
                                    .foregroundStyle(SettingsTheme.mute.opacity(0.8)).padding(.horizontal, 12).padding(.bottom, 4)
                                ForEach(pages) { sidebarRow($0) }
                            }
                        }
                    }
                    if results.isEmpty {
                        Text("nada coincide con “\(query)”").font(.system(size: 12)).foregroundStyle(SettingsTheme.mute).padding(.horizontal, 12)
                    }
                }
                .padding(.horizontal, 10).padding(.bottom, 16)
            }
            statusFooter
        }
        .frame(width: 232)
        .onChange(of: query) { _ in if let first = results.first, !results.contains(page) { page = first } }
    }

    /// Las dos mascotas, vestidas como las tenga el usuario: la ventana ya dice de quien es.
    private var brand: some View {
        HStack(spacing: 10) {
            HStack(spacing: -8) {
                ClaudeSprite(outfits: store.outfitsNow()).frame(width: 34, height: 34).breathing()
                CodexSprite(skin: store.codexSkin, outfits: store.outfitsNow()).frame(width: 34, height: 34).breathing(delay: 0.5)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("claude-pet").font(.system(size: 15, weight: .bold)).tracking(-0.2)
                Text(">_ claude · codex").font(.system(size: 9.5, design: .monospaced)).foregroundStyle(SettingsTheme.duo)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.top, 40).padding(.bottom, 14)
    }

    private func sidebarRow(_ p: SettingsPage) -> some View {
        let selected = p == page
        return Button { withAnimation(.easeOut(duration: 0.18)) { page = p } } label: {
            HStack(spacing: 10) {
                Image(systemName: p.symbol).font(.system(size: 13, weight: .regular)).frame(width: 18)
                    .foregroundStyle(selected ? AnyShapeStyle(SettingsTheme.duo) : AnyShapeStyle(Color.white.opacity(0.72)))
                Text(p.title).font(.system(size: 13, weight: selected ? .semibold : .regular))
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .foregroundStyle(selected ? Color.white : Color.white.opacity(0.72))
            .background(Capsule().fill(selected ? Color.white.opacity(0.1) : .clear))
            .overlay(Capsule().strokeBorder(selected ? AnyShapeStyle(SettingsTheme.duoDiagonal) : AnyShapeStyle(Color.clear), lineWidth: 1.2))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var statusFooter: some View {
        HStack(spacing: 8) {
            Circle().fill(store.layout == .island ? SettingsTheme.green : SettingsTheme.mute).frame(width: 7, height: 7)
            Text(store.layout == .island ? "isla activa" : "mascotas flotantes")
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(SettingsTheme.mute)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .overlay(alignment: .top) { Rectangle().fill(SettingsTheme.line).frame(height: 1) }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(page.title).font(.system(size: 30, weight: .bold)).tracking(-0.5)
                    Capsule().fill(SettingsTheme.duo).frame(width: 44, height: 3)
                    Text(page.subtitle).font(.system(size: 13)).foregroundStyle(SettingsTheme.mute).padding(.top, 2)
                }
                .padding(.bottom, 4)
                pageBody
            }
            .padding(.horizontal, 30).padding(.top, 44).padding(.bottom, 30)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .id(page)
            .transition(.opacity)
        }
    }

    @ViewBuilder private var pageBody: some View {
        switch page {
        case .resumen: ResumenPage(store: store)
        case .apariencia: AparienciaPage(store: store)
        case .comportamiento: ComportamientoPage(store: store)
        case .agentes: AgentesPage(store: store)
        case .permisos: PermisosPage(store: store)
        case .perimetro: PerimetroPage(store: store)
        case .privacidad: PrivacidadPage(store: store)
        case .guardarropa: GuardarropaPage(store: store)
        case .sonidos: SonidosPage(store: store)
        case .musica: MusicaPage(store: store)
        case .foco: FocoPage(store: store)
        case .atajos: AtajosPage(store: store)
        case .copia: CopiaPage(store: store)
        case .acerca: AcercaPage()
        }
    }
}

/// Capturas de las paginas para la documentacion: se monta la ventana fuera de pantalla y se vuelca su contenido.
enum SettingsSnapshot {
    @MainActor static func render(to directory: String, pages: [SettingsPage] = SettingsPage.allCases) {
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        for page in pages {
            if page == .perimetro, PerimetroPage.previewWorkspace == nil {
                let sample = "/Users/demo/mi-app"
                PerimetroPage.previewWorkspace = sample
                PetStore.shared.perimeters = [Perimeter(root: sample, allow: ["Sources/Auth", "Tests/**"], protect: Perimeter.defaultProtect, mode: .ask)]
            }
            let host = NSHostingView(rootView: SettingsView(store: PetStore.shared, page: page, fixedSize: true))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 700), styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentView = host
            host.frame = NSRect(x: 0, y: 0, width: 980, height: 700)
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.35))
            host.layoutSubtreeIfNeeded()
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
            host.cacheDisplay(in: host.bounds, to: rep)
            if let png = rep.representation(using: .png, properties: [:]) { try? png.write(to: URL(fileURLWithPath: directory + "/ajustes-\(page.rawValue).png")) }
        }
    }
}
