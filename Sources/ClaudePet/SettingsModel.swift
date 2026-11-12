import SwiftUI

/// Agrupacion de la barra lateral de ajustes.
enum SettingsGroup: String, CaseIterable, Identifiable {
    case inicio, isla, agentes, seguridad, mascota, sistema
    var id: String { rawValue }
    var title: String { rawValue }
}

enum SettingsPage: String, CaseIterable, Identifiable {
    case resumen, apariencia, comportamiento, agentes, permisos, perimetro, privacidad, guardarropa, sonidos, musica, foco, trackpad, plugins, atajos, copia, acerca
    var id: String { rawValue }
}

/// Filtros del buscador de ajustes: texto, categoria y dos interruptores. Todo es de vista; no se guarda nada salvo la categoria.
struct SettingsFilter: Equatable {
    var query = ""
    /// nil = todas las categorias.
    var group: SettingsGroup?
    var onlyEnabled = false
    var onlyExperimental = false

    var isActive: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty || group != nil || onlyEnabled || onlyExperimental }
    mutating func clear() { self = SettingsFilter() }

    /// Las categorias que se ofrecen como ficha. «inicio» no es una: el resumen aparece en «todo».
    static let categories: [SettingsGroup] = SettingsGroup.allCases.filter { $0 != .inicio }
}

extension SettingsPage {
    private var spec: SettingsPageSpec? { Self.registry[self] }
    var title: String { spec?.title ?? rawValue }
    var symbol: String { spec?.symbol ?? "circle" }
    var group: SettingsGroup { spec?.group ?? .sistema }
    var keywords: [String] { spec?.keywords ?? [] }
    var subtitle: String { spec?.subtitle ?? "" }
    var isExperimental: Bool { spec?.experimental ?? false }
    /// nil si la pagina no gobierna una funcion que se encienda y apague.
    @MainActor func isOn(_ store: PetStore) -> Bool? { spec?.isOn?(store) }
    @MainActor func makeBody(_ store: PetStore) -> AnyView { spec?.build(store) ?? AnyView(EmptyView()) }

    static func matching(_ query: String) -> [SettingsPage] {
        let q = fold(query)
        guard !q.isEmpty else { return allCases }
        return allCases.filter { page in
            fold(page.title).contains(q) || fold(page.group.title).contains(q) || page.keywords.contains { fold($0).contains(q) }
        }
    }

    /// Buscador con filtros. `isOn` dice si una pagina tiene su funcion encendida (nil = no aplica); con
    /// «solo activados» quedan fuera las apagadas y las que no se encienden.
    static func filtered(_ filter: SettingsFilter, isOn: (SettingsPage) -> Bool?) -> [SettingsPage] {
        matching(filter.query).filter { page in
            if let g = filter.group, page.group != g { return false }
            if filter.onlyEnabled, isOn(page) != true { return false }
            if filter.onlyExperimental, !page.isExperimental { return false }
            return true
        }
    }

    /// Cuantas paginas quedarian en cada categoria con el texto y los interruptores actuales (sin contar la categoria elegida).
    static func counts(_ filter: SettingsFilter, isOn: (SettingsPage) -> Bool?) -> [SettingsGroup: Int] {
        var base = filter; base.group = nil
        var out: [SettingsGroup: Int] = [:]
        for page in filtered(base, isOn: isOn) { out[page.group, default: 0] += 1 }
        return out
    }

    /// «2/3» por grupo: paginas encendidas entre las que se pueden encender. nil si el grupo no tiene ninguna.
    static func activity(in group: SettingsGroup, isOn: (SettingsPage) -> Bool?) -> (on: Int, of: Int)? {
        let states = allCases.filter { $0.group == group }.compactMap(isOn)
        return states.isEmpty ? nil : (states.filter { $0 }.count, states.count)
    }

    static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .init(identifier: "es")).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}


/// Letras de los atajos globales (siempre con control + opcion). Valida letras y duplicados.
struct ShortcutMap: Equatable {
    static let standard = ShortcutMap(keys: [.allow: "a", .deny: "d", .island: "i", .snooze: "s", .pin: "p"])
    private(set) var keys: [GlobalShortcut: Character]

    enum Failure: Error, Equatable { case notAKey, taken(by: GlobalShortcut) }

    init(keys: [GlobalShortcut: Character]) { self.keys = keys }

    func key(for shortcut: GlobalShortcut) -> Character { keys[shortcut] ?? Self.standard.keys[shortcut] ?? "?" }
    func shortcut(for key: String) -> GlobalShortcut? { keys.first { String($0.value) == key.lowercased() }?.key }

    /// nil si se aplico; si no, el motivo.
    @discardableResult
    mutating func set(_ shortcut: GlobalShortcut, to raw: String) -> Failure? {
        let t = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard t.count == 1, let ch = t.first, ch.isASCII, ch.isLetter || ch.isNumber else { return .notAKey }
        if let other = keys.first(where: { $0.value == ch && $0.key != shortcut })?.key { return .taken(by: other) }
        keys[shortcut] = ch
        return nil
    }

    /// "allow=a,deny=d,...": lo que no se entiende o se repite vuelve a su valor original.
    static func decode(_ raw: String) -> ShortcutMap {
        var map = standard
        for part in raw.split(separator: ",") {
            let kv = part.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2, let s = GlobalShortcut(rawValue: kv[0]) else { continue }
            var copy = map
            if copy.set(s, to: kv[1]) == nil { map = copy }
        }
        return map
    }

    func encode() -> String { GlobalShortcut.allCases.map { "\($0.rawValue)=\(key(for: $0))" }.joined(separator: ",") }

    static func title(_ s: GlobalShortcut) -> String {
        switch s {
        case .allow: return "permitir la primera petición"
        case .deny: return "denegar la primera petición"
        case .island: return "abrir la isla"
        case .snooze: return "silenciar avisos un rato"
        case .pin: return "fijar las mascotas"
        }
    }
}

/// Volumen por categoria de sonido, guardado como "interfaz=0.8,alertas=1,mascota=0.5".
enum SoundCategoryVolumes {
    static func decode(_ raw: String) -> [SoundCue.Category: Double] {
        var out: [SoundCue.Category: Double] = [:]
        for part in raw.split(separator: ",") {
            let kv = part.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2, let c = SoundCue.Category(rawValue: kv[0]), let v = Double(kv[1]), v.isFinite else { continue }
            out[c] = min(1, max(0, v))
        }
        return out
    }
    static func encode(_ v: [SoundCue.Category: Double]) -> String {
        SoundCue.Category.allCases.compactMap { c in v[c].map { "\(c.rawValue)=\(String(format: "%.2f", $0))" } }.joined(separator: ",")
    }
}

/// Copia de seguridad de los ajustes: solo claves conocidas, con tipo y rango comprobados al importar.
enum SettingsBackup {
    enum Kind {
        case bool
        case number(Double, Double)
        case integer(Int, Int)
        case choice([String])
        case text(Int)
    }
    struct Entry { let key: String; let kind: Kind }

    static let schema: [Entry] = [
        Entry(key: "autoVisibility", kind: .bool), Entry(key: "layout", kind: .choice(PetLayout.allCases.map(\.rawValue))),
        Entry(key: "islandScreenPreference", kind: .choice(IslandScreenPreference.allCases.map(\.rawValue))),
        Entry(key: "islandPlacement", kind: .choice(IslandPlacement.allCases.map(\.rawValue))),
        Entry(key: "islandActivationWidth", kind: .number(120, 400)), Entry(key: "islandActivationDelay", kind: .number(0, 1)),
        Entry(key: "islandCloseDelay", kind: .number(0, 10)),
        Entry(key: "islandCompactMode", kind: .choice(IslandCompactMode.allCases.map(\.rawValue))),
        Entry(key: "islandShowClock", kind: .bool), Entry(key: "islandHideCompact", kind: .bool), Entry(key: "islandFixedScreenID", kind: .text(120)),
        Entry(key: "islandPermissions", kind: .bool), Entry(key: "globalShortcutsEnabled", kind: .bool),
        Entry(key: "autoRestorePoints", kind: .bool), Entry(key: "blockOnChange", kind: .bool),
        Entry(key: "soundsEnabled", kind: .bool), Entry(key: "soundVolume", kind: .number(0, 1)),
        Entry(key: "soundCategoryVolumes", kind: .text(80)), Entry(key: "shortcutKeys", kind: .text(80)),
        Entry(key: "wardrobe", kind: .text(160)), Entry(key: "codexWardrobe", kind: .text(160)), Entry(key: "weatherEnabled", kind: .bool), Entry(key: "rageEnabled", kind: .bool), Entry(key: "deskFollow", kind: .bool), Entry(key: "phoneAlerts", kind: .bool), Entry(key: "questEnabled", kind: .bool), Entry(key: "autoEnergySaving", kind: .bool), Entry(key: "relayEnabled", kind: .bool), Entry(key: "relayAddress", kind: .text(253)), Entry(key: "relayTLS", kind: .bool), Entry(key: "phoneAlertsServer", kind: .text(120)), Entry(key: "phoneAlertsOnlyAway", kind: .bool), Entry(key: "phoneAlertsDetail", kind: .bool), Entry(key: "deskSpots", kind: .text(400)), Entry(key: "weatherCity", kind: .text(80)), Entry(key: "weatherDress", kind: .bool), Entry(key: "ambientReactions", kind: .bool), Entry(key: "seasonalOutfits", kind: .bool), Entry(key: "danceToMusic", kind: .bool), Entry(key: "musicPlayer", kind: .bool), Entry(key: "musicReacts", kind: .bool), Entry(key: "musicListens", kind: .bool), Entry(key: "musicTint", kind: .bool), Entry(key: "quickActions", kind: .text(200)), Entry(key: "quickAppAware", kind: .bool), Entry(key: "musicVinyl", kind: .bool),
        Entry(key: "focusManual", kind: .bool), Entry(key: "focusStart", kind: .integer(-1, 23)), Entry(key: "focusEnd", kind: .integer(-1, 23)),
        Entry(key: "pinSession", kind: .bool), Entry(key: "muteClaude", kind: .bool), Entry(key: "muteCodex", kind: .bool),
        Entry(key: "animationsEnabled", kind: .bool), Entry(key: "footballEnabled", kind: .bool),
        Entry(key: "skin", kind: .choice(Skin.allCases.map(\.rawValue))), Entry(key: "codexSkin", kind: .choice(CodexSkin.allCases.map(\.rawValue))),
        Entry(key: "codexGesturesEnabled", kind: .bool), Entry(key: "showBubble", kind: .bool), Entry(key: "showDetail", kind: .bool),
        Entry(key: "stallWatch", kind: .bool), Entry(key: "alertDisplayMode", kind: .choice(AlertDisplayMode.allCases.map(\.rawValue))),
        Entry(key: "shareProject", kind: .bool), Entry(key: "claudwler.verify", kind: .bool),
    ]
    static let maxBytes = 256 * 1024
    static let format = "claude-pet-settings"

    struct Report: Equatable { var applied = 0; var skipped: [String] = [] }
    enum Failure: Error, Equatable { case tooLarge, notSettings, invalidJSON }

    static func export(from defaults: UserDefaults) -> Data {
        var out: [String: Any] = [:]
        for e in schema {
            guard let v = defaults.object(forKey: e.key) else { continue }
            if valid(v, e.kind) != nil { out[e.key] = v }
        }
        let doc: [String: Any] = ["format": format, "version": 1, "settings": out]
        return (try? JSONSerialization.data(withJSONObject: doc, options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }

    @discardableResult
    static func importing(_ data: Data, into defaults: UserDefaults) throws -> Report {
        guard data.count <= maxBytes else { throw Failure.tooLarge }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure.invalidJSON }
        guard obj["format"] as? String == format, let settings = obj["settings"] as? [String: Any] else { throw Failure.notSettings }
        var report = Report()
        for (key, raw) in settings.sorted(by: { $0.key < $1.key }) {
            guard let entry = schema.first(where: { $0.key == key }), let value = valid(raw, entry.kind) else { report.skipped.append(key); continue }
            defaults.set(value, forKey: key); report.applied += 1
        }
        return report
    }

    static func reset(in defaults: UserDefaults) { for e in schema { defaults.removeObject(forKey: e.key) } }

    /// Devuelve el valor normalizado si cumple el tipo y el rango, o nil.
    static func valid(_ v: Any, _ kind: Kind) -> Any? {
        switch kind {
        case .bool:
            guard let n = v as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else { return nil }
            return n.boolValue
        case .number(let lo, let hi):
            guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite, n.doubleValue >= lo, n.doubleValue <= hi else { return nil }
            return n.doubleValue
        case .integer(let lo, let hi):
            guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue == n.doubleValue.rounded(), Int(exactly: n.doubleValue) != nil, n.intValue >= lo, n.intValue <= hi else { return nil }
            return n.intValue
        case .choice(let options):
            guard let s = v as? String, options.contains(s) else { return nil }
            return s
        case .text(let limit):
            guard let s = v as? String, s.count <= limit, !s.contains(where: { $0.isNewline }) else { return nil }
            return s
        }
    }
}
