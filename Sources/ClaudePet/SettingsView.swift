import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var store: PetStore
    @State private var page: SettingsPage
    @State private var filter = SettingsFilter()
    @State private var filtersOpen: Bool
    @AppStorage(SettingsDensity.storageKey) private var densityRaw = SettingsDensity.comfortable.rawValue
    @Environment(\.colorSchemeContrast) private var contrast
    private let fixedSize: Bool
    private let densityOverride: SettingsDensity?
    private let forceHighContrast: Bool

    init(store: PetStore, page: SettingsPage = .resumen, fixedSize: Bool = false, filter: SettingsFilter = SettingsFilter(), filtersOpen: Bool = false,
         density: SettingsDensity? = nil, highContrast: Bool = false) {
        self.store = store
        self.fixedSize = fixedSize
        self.densityOverride = density
        self.forceHighContrast = highContrast
        _page = State(initialValue: page)
        _filter = State(initialValue: filter)
        _filtersOpen = State(initialValue: filtersOpen || filter.isActive)
    }

    private var density: SettingsDensity { densityOverride ?? .decode(densityRaw) }
    private var highContrast: Bool {
        forceHighContrast || contrast == .increased || NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            || ProcessInfo.processInfo.environment["CLAUDE_PET_HIGH_CONTRAST"] == "1"
    }
    private func isOn(_ p: SettingsPage) -> Bool? { p.isOn(store) }
    private var results: [SettingsPage] { SettingsPage.filtered(filter, isOn: isOn) }
    private var activeCount: Int { SettingsPage.allCases.filter { isOn($0) == true }.count }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(SettingsTheme.hairline(highContrast)).frame(width: 1)
            content
        }
        .frame(minWidth: 940, idealWidth: 980, minHeight: 640, idealHeight: 700)
        .frame(width: fixedSize ? 980 : nil, height: fixedSize ? 700 : nil)
        .background(SettingsTheme.background)
        .environment(\.settingsDensity, density)
        .environment(\.settingsHighContrast, highContrast)
        .environment(\.settingsReduceMotion, store.reduceMotion)
        .preferredColorScheme(.dark)
    }

    // MARK: barra lateral

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand
            searchField
            if filtersOpen { filterChips.padding(.horizontal, 14).padding(.bottom, 10) }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(SettingsGroup.allCases) { group in
                            let pages = results.filter { $0.group == group }
                            if !pages.isEmpty {
                                VStack(alignment: .leading, spacing: 1) {
                                    groupHeader(group)
                                    ForEach(pages) { sidebarRow($0) }
                                }
                            }
                        }
                        if results.isEmpty { emptyResults }
                    }
                    .padding(.horizontal, 10).padding(.bottom, 16).padding(.top, 2)
                }
                .scrollIndicators(.never)
                .onAppear { proxy.scrollTo(page, anchor: .center) }
                .onChange(of: page) { p in withAnimation(store.reduceMotion ? nil : .easeOut(duration: 0.2)) { proxy.scrollTo(p, anchor: .center) } }
            }
            statusFooter
        }
        .frame(width: 244)
        .onChange(of: filter) { _ in if let first = results.first, !results.contains(page) { page = first } }
    }

    /// Las dos mascotas, vestidas como las tenga el usuario: la ventana ya dice de quien es.
    private var brand: some View {
        HStack(spacing: 10) {
            HStack(spacing: -8) {
                ClaudeSprite(outfits: store.outfitsNow()).frame(width: 34, height: 34).breathing(!store.reduceMotion)
                CodexSprite(skin: store.codexSkin, outfits: store.outfitsNow(for: .codex)).frame(width: 34, height: 34).breathing(!store.reduceMotion, delay: 0.5)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("claude-pet").font(.system(size: 15, weight: .bold)).tracking(-0.2)
                HStack(spacing: 4) {
                    Text("claude").foregroundStyle(SettingsTheme.agentClaude)
                    Text("·").foregroundStyle(SettingsTheme.muted(highContrast))
                    Text("codex").foregroundStyle(SettingsTheme.agentCodex)
                }
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.top, 38).padding(.bottom, 12)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(SettingsTheme.muted(highContrast))
                TextField("buscar un ajuste", text: $filter.query).textFieldStyle(.plain).font(.system(size: 13))
                    .accessibilityLabel("buscar un ajuste")
                if !filter.query.isEmpty {
                    Button { filter.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(SettingsTheme.muted(highContrast)) }
                        .buttonStyle(.plain).accessibilityLabel("borrar la búsqueda")
                }
            }
            .padding(.horizontal, 11).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(SettingsTheme.hairline(highContrast), lineWidth: 1))

            let n = filterCount
            Button { filtersOpen.toggle() } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "line.3.horizontal.decrease").font(.system(size: 12, weight: .medium))
                        .frame(width: 30, height: 30)
                        .foregroundStyle(filtersOpen || n > 0 ? SettingsTheme.onAccent : Color.white.opacity(0.8))
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(filtersOpen || n > 0 ? SettingsTheme.accent : Color.white.opacity(0.06)))
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(filtersOpen || n > 0 ? Color.clear : SettingsTheme.hairline(highContrast), lineWidth: 1))
                    if n > 0 {
                        Text("\(n)").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(.white)
                            .frame(width: 14, height: 14).background(Circle().fill(Color.black.opacity(0.85))).offset(x: 4, y: -4)
                    }
                }
            }
            .buttonStyle(.plain)
            .help(filtersOpen ? "ocultar filtros" : "mostrar filtros")
            .accessibilityLabel("filtros").accessibilityValue(n > 0 ? "\(n) activos" : "sin filtros")
        }
        .padding(.horizontal, 14).padding(.bottom, 12)
    }

    private var filterCount: Int { (filter.group != nil ? 1 : 0) + (filter.onlyEnabled ? 1 : 0) + (filter.onlyExperimental ? 1 : 0) }

    private var filterChips: some View {
        let counts = SettingsPage.counts(filter, isOn: isOn)
        return VStack(alignment: .leading, spacing: 8) {
            SLabel("categoría")
            FlowLayout(spacing: 6, lineSpacing: 6) {
                SChip(title: "todo", count: counts.values.reduce(0, +), selected: filter.group == nil) { filter.group = nil }
                ForEach(SettingsFilter.categories) { g in
                    SChip(title: g.title, count: counts[g] ?? 0, selected: filter.group == g) { filter.group = (filter.group == g ? nil : g) }
                }
            }
            SLabel("mostrar")
            FlowLayout(spacing: 6, lineSpacing: 6) {
                SChip(title: "solo activados", symbol: "power", selected: filter.onlyEnabled) { filter.onlyEnabled.toggle() }
                SChip(title: "solo experimentales", symbol: "wand.and.stars", selected: filter.onlyExperimental) { filter.onlyExperimental.toggle() }
            }
            if filter.isActive {
                Button { filter.clear() } label: {
                    Text("quitar filtros").font(.system(size: 10.5, design: .monospaced)).underline().foregroundStyle(SettingsTheme.muted(highContrast))
                }.buttonStyle(.plain)
            }
        }
    }

    private func groupHeader(_ group: SettingsGroup) -> some View {
        HStack(spacing: 6) {
            SLabel(group.title)
            Spacer(minLength: 0)
            if let a = SettingsPage.activity(in: group, isOn: isOn) {
                Text("\(a.on)/\(a.of)").font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(a.on > 0 ? SettingsTheme.green : SettingsTheme.muted(highContrast))
                    .help("funciones encendidas en este grupo")
                    .accessibilityLabel("\(a.on) de \(a.of) encendidas")
            }
        }
        .padding(.horizontal, 12).padding(.bottom, 4).padding(.top, 2)
    }

    private func sidebarRow(_ p: SettingsPage) -> some View {
        let selected = p == page
        let on = isOn(p)
        return Button { if store.reduceMotion { page = p } else { withAnimation(.easeOut(duration: 0.18)) { page = p } } } label: {
            HStack(spacing: 10) {
                Image(systemName: p.symbol).font(.system(size: 13, weight: .regular)).frame(width: 18)
                    .foregroundStyle(selected ? SettingsTheme.accent : Color.white.opacity(highContrast ? 0.92 : 0.7))
                Text(p.title).font(.system(size: 13, weight: selected ? .semibold : .regular))
                Spacer(minLength: 4)
                if p.isExperimental {
                    Text("exp").font(.system(size: 8.5, weight: .semibold, design: .monospaced)).foregroundStyle(SettingsTheme.amber)
                        .padding(.horizontal, 4).padding(.vertical, 1.5).overlay(RoundedRectangle(cornerRadius: 3).stroke(SettingsTheme.amber.opacity(0.7), lineWidth: 1))
                        .help("tiene opciones experimentales")
                }
                if let on {
                    Circle().fill(on ? SettingsTheme.green : Color.clear).frame(width: 6, height: 6)
                        .overlay(Circle().stroke(on ? Color.clear : Color.white.opacity(0.3), lineWidth: 1))
                        .accessibilityLabel(on ? "encendida" : "apagada")
                }
            }
            .padding(.horizontal, 12).padding(.vertical, density == .compact ? 4.5 : 6)
            .foregroundStyle(selected ? Color.white : Color.white.opacity(highContrast ? 0.95 : 0.74))
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(selected ? Color.white.opacity(0.09) : .clear))
            .overlay(alignment: .leading) { if selected { Rectangle().fill(SettingsTheme.accent).frame(width: 2, height: 16).offset(x: -1) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .id(p)
    }

    private var emptyResults: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(filter.query.isEmpty ? "ninguna página cumple los filtros" : "nada coincide con “\(filter.query)”")
                .font(.system(size: 12)).foregroundStyle(SettingsTheme.muted(highContrast))
            if filter.isActive { SButton(title: "quitar filtros", symbol: "xmark") { filter.clear() } }
        }
        .padding(.horizontal, 12)
    }

    private var statusFooter: some View {
        HStack(spacing: 8) {
            Circle().fill(store.layout == .island ? SettingsTheme.green : SettingsTheme.muted(highContrast)).frame(width: 7, height: 7)
            Text(store.layout == .island ? "isla activa" : "mascotas flotantes")
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(SettingsTheme.muted(highContrast))
            Spacer()
            Text("\(activeCount) activas").font(.system(size: 11, design: .monospaced)).foregroundStyle(SettingsTheme.muted(highContrast))
                .help("funciones encendidas ahora mismo")
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .overlay(alignment: .top) { Rectangle().fill(SettingsTheme.hairline(highContrast)).frame(height: 1) }
    }

    // MARK: contenido

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: density.pageSpacing) {
                header
                page.makeBody(store)
            }
            .padding(.horizontal, 32).padding(.top, 40).padding(.bottom, 32)
            .frame(maxWidth: 780, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .id(page)
        }
        .scrollIndicators(.never)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                SLabel(page.group.title, tint: SettingsTheme.accent)
                Text(page.title).font(.system(size: 30, weight: .bold)).tracking(-0.5)
                Text(page.subtitle).font(.system(size: 13)).foregroundStyle(SettingsTheme.muted(highContrast)).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 5) {
                SLabel("densidad")
                SSegmentedControl(selection: Binding(get: { density }, set: { densityRaw = $0.rawValue }),
                                  options: SettingsDensity.allCases.map { ($0, $0.title) }, compact: true)
                    .accessibilityLabel("densidad")
            }
            .padding(.top, 4)
        }
    }
}

/// Fichas que saltan de linea: lo justo para los filtros de la barra lateral.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? 10_000, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (i, f) in arrange(width: bounds.width, subviews: subviews).frames.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + f.minX, y: bounds.minY + f.minY), proposal: ProposedViewSize(f.size))
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (frames: [CGRect], size: CGSize) {
        var frames: [CGRect] = [], x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowH + lineSpacing; rowH = 0 }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing; rowH = max(rowH, size.height); maxX = max(maxX, x - spacing)
        }
        return (frames, CGSize(width: maxX, height: y + rowH))
    }
}

/// Capturas de las paginas para la documentacion: se monta la ventana fuera de pantalla y se vuelca su contenido.
enum SettingsSnapshot {
    @MainActor static func render(to directory: String, pages: [SettingsPage] = SettingsPage.allCases) {
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        for page in pages {
            prepare(page)
            write(SettingsView(store: PetStore.shared, page: page, fixedSize: true), to: directory + "/ajustes-\(page.rawValue).png")
        }
        variants(to: directory)
    }

    /// Estados que las paginas normales no enseñan: filtros abiertos, densidad compacta y contraste alto.
    @MainActor private static func variants(to directory: String) {
        var f = SettingsFilter(); f.onlyEnabled = true
        write(SettingsView(store: PetStore.shared, page: .apariencia, fixedSize: true, filter: f, filtersOpen: true), to: directory + "/ajustes-filtro-activados.png")
        var q = SettingsFilter(); q.query = "sonido"; q.group = .mascota
        write(SettingsView(store: PetStore.shared, page: .sonidos, fixedSize: true, filter: q, filtersOpen: true), to: directory + "/ajustes-filtro-busqueda.png")
        var none = SettingsFilter(); none.onlyExperimental = true; none.group = .agentes
        write(SettingsView(store: PetStore.shared, page: .resumen, fixedSize: true, filter: none, filtersOpen: true), to: directory + "/ajustes-filtro-vacio.png")
        write(SettingsView(store: PetStore.shared, page: .resumen, fixedSize: true, density: .compact), to: directory + "/ajustes-resumen-compacta.png")
        write(SettingsView(store: PetStore.shared, page: .comportamiento, fixedSize: true, density: .compact), to: directory + "/ajustes-comportamiento-compacta.png")
        write(SettingsView(store: PetStore.shared, page: .resumen, fixedSize: true, highContrast: true), to: directory + "/ajustes-resumen-contraste.png")
    }

    @MainActor private static func prepare(_ page: SettingsPage) {
        if page == .plugins, let examples = ProcessInfo.processInfo.environment["CLAUDE_PET_SNAPSHOT_EXAMPLES"] {
            // captura de documentacion: los ejemplos del repositorio instalados y activos, en una carpeta temporal
            let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("snap-plugins-\(UUID().uuidString)")
            let reg = PluginRegistry(root: tmp, statePath: nil)
            for n in ((try? FileManager.default.contentsOfDirectory(atPath: examples)) ?? []).sorted() { _ = try? reg.install(from: URL(fileURLWithPath: examples).appendingPathComponent(n)); reg.setEnabled(n, n != "registro-de-sesiones", approving: true) }
            PetStore.shared.plugins = PluginHost(registry: reg)
        }
        if page == .perimetro, PerimetroPage.previewWorkspace == nil {
            let sample = "/Users/demo/mi-app"
            PerimetroPage.previewWorkspace = sample
            PetStore.shared.perimeters = [Perimeter(root: sample, allow: ["Sources/Auth", "Tests/**"], protect: Perimeter.defaultProtect, mode: .ask)]
        }
    }

    @MainActor private static func write(_ view: SettingsView, to path: String) {
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 700), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.frame = NSRect(x: 0, y: 0, width: 980, height: 700)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) { try? png.write(to: URL(fileURLWithPath: path)) }
    }
}
