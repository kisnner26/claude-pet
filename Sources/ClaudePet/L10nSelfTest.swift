import SwiftUI

/// `ClaudePet --selftest-lang`: la traduccion con cifras y trozos, y que los literales de SwiftUI pasen por ella.
enum L10nSelfTest {
    static func run() -> Bool {
        var failures = 0
        func check(_ name: String, _ ok: Bool) { if !ok { failures += 1; print("FALLO \(name)") } }
        let saved = L.current
        defer { L.current = saved }

        L.current = .es
        check("es: pasa tal cual", L.tr("sesiones hoy") == "sesiones hoy")

        L.current = .en
        check("en: frase exacta", L.tr("sesiones hoy") == "sessions today")
        check("en: frase con cifra", L.tr("12 sesiones") == "12 sessions")
        check("en: cifra distinta, misma plantilla", L.tr("3 sesiones") == "3 sessions")
        check("en: trozos separados por punto medio", L.tr("sesiones hoy · permisos hoy") == "sessions today · permissions today")
        check("en: inicial mayuscula", L.tr("Ahora") == "Now")
        check("en: desconocida se queda igual", L.tr("zzz qqq") == "zzz qqq")
        check("en: vacia", L.tr("") == "")

        let literal = String(reflecting: Text("sesiones hoy"))
        check("Text(\"literal\") usa la sobrecarga que traduce", literal.contains("sessions today"))
        let dynamic = String(reflecting: Text("\(3) sesiones"))
        check("Text con interpolacion usa la sobrecarga", dynamic.contains("3 sessions"))

        for (k, v) in L10nEN.table {
            check("sin valor vacio: \(k)", !v.isEmpty)
            if k.contains("#") { check("mismas cifras en la traduccion: \(k)", v.filter { $0 == "#" }.count == k.filter { $0 == "#" }.count) }
        }
        print(failures == 0 ? "IDIOMAS OK" : "IDIOMAS \(failures) FALLOS")
        return failures == 0
    }
}
