import Foundation
import os

/// Modo conciso (opt-in, apagado de serie): una instruccion corta que `hooks/pet-brain.sh start` antepone al contexto de arranque.
///
/// CONTRATO con el hook (si cambias `pet-brain.sh`, respétalo):
///   archivo   ~/.claude-pet/conciso.txt   (UTF-8, permisos 0600, lo escribe y lo borra la app)
///   existe y no esta vacio  ->  el modo esta activo; el contenido ES la instruccion, tal cual, sin formato
///   no existe               ->  modo apagado; el hook no imprime nada de mas
///   tamano maximo 1200 bytes (el hook lee como mucho eso)
/// El hook no interpreta nada: imprime el archivo, una linea en blanco y sigue con lo que ya hacia.
enum ConciseMode {
    static let fileName = "conciso.txt"
    static let maxBytes = 1_200
    static let maxCharacters = 600

    static let defaultES = "Responde con la mayor concisión posible: ve directo al punto, sin preámbulos ni resúmenes de lo que acabas de hacer y sin repetir código que no cambió. Si algo importa de verdad, un riesgo o un error, dilo completo."
    static let defaultEN = "Answer as concisely as possible: get straight to the point, no preamble, no recap of what you just did, and do not repeat code that did not change. If something really matters, a risk or an error, say it in full."

    static func defaultText(_ lang: Lang = L.current) -> String { lang == .en ? defaultEN : defaultES }

    static func path(home: String = NSHomeDirectory()) -> String { home + "/.claude-pet/" + fileName }

    /// Texto limpio: sin controles, sin espacios de mas y dentro del limite. Vacio si no queda nada.
    static func sanitize(_ raw: String) -> String {
        let scalars = raw.unicodeScalars.filter { $0 == "\n" || $0.value >= 0x20 && $0.value != 0x7F }
        var text = String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count > maxCharacters { text = String(text.prefix(maxCharacters)) }
        while text.utf8.count > maxBytes { text.removeLast() }
        return text
    }

    static func isActive(home: String = NSHomeDirectory()) -> Bool {
        ((try? FileManager.default.attributesOfItem(atPath: path(home: home))[.size]) as? NSNumber)?.intValue ?? 0 > 0
    }

    /// Enciende (escribe el archivo con 0600) o apaga (lo borra). Sin texto propio usa el predeterminado del idioma.
    @discardableResult
    static func apply(enabled: Bool, customText: String?, home: String = NSHomeDirectory(), lang: Lang = L.current) throws -> Bool {
        let file = path(home: home)
        guard enabled else {
            try? FileManager.default.removeItem(atPath: file)
            return false
        }
        let custom = customText.map(sanitize) ?? ""
        let text = custom.isEmpty ? defaultText(lang) : custom
        let dir = (file as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let tmp = dir + "/.\(fileName).\(getpid()).tmp"
        guard FileManager.default.createFile(atPath: tmp, contents: Data(text.utf8), attributes: [.posixPermissions: 0o600]) else { throw CocoaError(.fileWriteUnknown) }
        defer { try? FileManager.default.removeItem(atPath: tmp) }
        if rename(tmp, file) != 0 { throw CocoaError(.fileWriteUnknown) }
        return true
    }
}

/// Preferencias de la funcion de ahorro. Viven en UserDefaults; el archivo de arriba es solo lo que lee el hook.
enum SavingsPreferences {
    static let conciseKey = "savings.concise"
    static let conciseTextKey = "savings.conciseText"
    static let adviceKey = "savings.advice"

    static var concise: Bool {
        get { UserDefaults.standard.bool(forKey: conciseKey) }
        set { UserDefaults.standard.set(newValue, forKey: conciseKey); sync() }
    }
    static var conciseText: String {
        get { UserDefaults.standard.string(forKey: conciseTextKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: conciseTextKey); sync() }
    }
    /// «consejos de ahorro» en la isla: apagado de serie.
    static var advice: Bool {
        get { UserDefaults.standard.bool(forKey: adviceKey) }
        set { UserDefaults.standard.set(newValue, forKey: adviceKey) }
    }
    static func sync() {
        do { try ConciseMode.apply(enabled: concise, customText: conciseText) }
        catch { Diag.savings.error("modo conciso: no se pudo escribir el archivo \(Diag.code(error), privacy: .public)") }
    }
}

extension Diag {
    /// Funcion de ahorro de tokens: solo componentes y codigos de error, nunca rutas ni contenido.
    static let savings = Logger(subsystem: subsystem, category: "ahorro")
}
