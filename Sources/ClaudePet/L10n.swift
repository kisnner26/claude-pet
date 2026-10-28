import SwiftUI

/// Idioma de la interfaz. El codigo fuente esta en espanol: el espanol pasa tal cual y el ingles se busca en `L10nEN.table`.
enum Lang: String, CaseIterable, Identifiable {
    case es, en
    var id: String { rawValue }
    var name: String { self == .es ? "español" : "english" }
}

enum L {
    static let key = "language"

    /// Sin eleccion previa se sigue el idioma del sistema: espanol si es espanol, ingles en cualquier otro caso.
    static var current: Lang = {
        if let raw = UserDefaults.standard.string(forKey: key), let l = Lang(rawValue: raw) { return l }
        return (Locale.preferredLanguages.first ?? "es").hasPrefix("es") ? .es : .en
    }()

    static func set(_ lang: Lang) {
        current = lang
        UserDefaults.standard.set(lang.rawValue, forKey: key)
    }

    /// Para frases con datos que no son cifras (nombres, plurales): las dos versiones, escritas enteras.
    static func t(_ es: String, _ en: String) -> String { current == .en ? en : es }

    /// Traduce una frase escrita en espanol. Si no la conoce, devuelve el original.
    /// Las cifras de una frase con datos ("5 sesiones") se sustituyen por `#` para reutilizar la misma traduccion.
    static func tr(_ s: String) -> String {
        guard current == .en, !s.isEmpty else { return s }
        if let hit = L10nEN.table[s] { return hit }
        let (shape, digits) = shapeOf(s)
        if digits.isEmpty == false, let hit = L10nEN.table[shape] { return fill(hit, digits) }
        // frases "a · b · c": se traduce cada trozo
        if s.contains(" · ") {
            let parts = s.components(separatedBy: " · ")
            let out = parts.map { tr($0) }
            if out != parts { return out.joined(separator: " · ") }
        }
        // minusculas: las etiquetas de la interfaz no empiezan en mayuscula, pero las de la isla si
        if let first = s.first, first.isUppercase {
            let low = first.lowercased() + s.dropFirst()
            if let hit = L10nEN.table[low] { return hit.prefix(1).uppercased() + hit.dropFirst() }
            let (sh, dg) = shapeOf(low)
            if dg.isEmpty == false, let hit = L10nEN.table[sh] { let f = fill(hit, dg); return f.prefix(1).uppercased() + f.dropFirst() }
        }
        return s
    }

    private static func shapeOf(_ s: String) -> (String, [String]) {
        var out = "", digits: [String] = [], run = ""
        for ch in s {
            if ch.isASCII, ch.isNumber { run.append(ch) }
            else { if !run.isEmpty { digits.append(run); out.append("#"); run = "" }; out.append(ch) }
        }
        if !run.isEmpty { digits.append(run); out.append("#") }
        return (out, digits)
    }

    private static func fill(_ template: String, _ digits: [String]) -> String {
        var out = "", i = 0
        for ch in template {
            if ch == "#", i < digits.count { out += digits[i]; i += 1 } else { out.append(ch) }
        }
        return out
    }
}

// Con estas sobrecargas, todo `Text("...")`, `Button("...")` y `Label("...")` escrito en espanol se traduce solo.
extension Text {
    init(_ s: String) { self.init(verbatim: L.tr(s)) }
}

extension Button where Label == Text {
    init(_ title: String, action: @escaping () -> Void) { self.init(action: action) { Text(verbatim: L.tr(title)) } }
}

extension Label where Title == Text, Icon == Image {
    init(_ title: String, systemImage: String) { self.init { Text(verbatim: L.tr(title)) } icon: { Image(systemName: systemImage) } }
}

extension View {
    func help(_ s: String) -> some View { self.help(Text(verbatim: L.tr(s))) }
}
