import Foundation

/// Pruebas sin red de lo que se anade a claudwler: avisos de la verificacion, exportacion y prompt de arreglo.
enum ClaudwlerExtrasSelfTest {
    static func run() -> Bool {
        var ok = true
        func check(_ name: String, _ c: Bool) { print((c ? "PASS " : "FAIL ") + name); if !c { ok = false } }

        // avisos de la verificacion
        func ok200(final: String? = nil, code: Int? = nil, ms: Int = 120) -> LinkCheck { LinkCheck(state: .ok, note: "200", finalURL: final, redirectCode: code, millis: ms) }
        check("un enlace normal no avisa de nada", LinkChecker.warnings(for: ok200(), requested: "https://a.com/x").isEmpty)
        check("una redireccion permanente se avisa con su destino", LinkChecker.warnings(for: ok200(final: "https://a.com/nuevo", code: 301), requested: "https://a.com/viejo") == ["redirección permanente (301) → a.com/nuevo"])
        check("el 308 tambien es permanente", LinkChecker.warnings(for: ok200(final: "https://a.com/n", code: 308), requested: "https://a.com/v").count == 1)
        check("una redireccion temporal no se avisa", LinkChecker.warnings(for: ok200(final: "https://a.com/login", code: 302), requested: "https://a.com/panel").isEmpty)
        check("caer de https a http se avisa", LinkChecker.warnings(for: ok200(final: "http://a.com/x", code: 302), requested: "https://a.com/x") == ["redirige a http sin cifrar"])
        check("de http a https no es problema", LinkChecker.warnings(for: ok200(final: "https://a.com/x", code: 302), requested: "http://a.com/x").isEmpty)
        check("tres segundos ya es lento", LinkChecker.warnings(for: ok200(ms: 3200), requested: "https://a.com") == ["lento (3.2 s)"])
        check("2,9 segundos no es lento", LinkChecker.warnings(for: ok200(ms: 2900), requested: "https://a.com").isEmpty)
        check("un enlace roto no suma avisos", LinkChecker.warnings(for: LinkCheck(state: .broken, note: "404", finalURL: "http://x", redirectCode: 301, millis: 9000), requested: "https://a.com").isEmpty)
        check("el destino se acorta sin esquema ni barra final", LinkChecker.shortURL("https://a.com/") == "a.com" && LinkChecker.shortURL("http://a.com/x/y") == "a.com/x/y")
        check("un destino larguisimo se recorta", LinkChecker.shortURL("https://a.com/" + String(repeating: "z", count: 100)).count == 60)

        print(ok ? "CLAUDWLER EXTRAS OK" : "CLAUDWLER EXTRAS FALLO")
        return ok
    }
}
