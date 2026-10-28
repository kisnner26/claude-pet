import Foundation

/// `ClaudePet --selftest-phone`: el servidor y el tema validos, el texto de los avisos (sin detalle ni secretos por defecto) y cuando se envian.
enum PhoneAlertsSelfTest {
    static func run() -> Bool {
        var failures = 0
        func check(_ name: String, _ ok: Bool) { if !ok { failures += 1; print("FALLO \(name)") } }
        typealias R = PhoneAlertRules

        let topic = R.newTopic()
        check("tema nuevo valido y largo", R.validTopic(topic) && topic.count == 26)
        check("dos temas nunca coinciden", R.newTopic() != R.newTopic())
        check("temas invalidos", !R.validTopic("") && !R.validTopic("corto") && !R.validTopic("TEMA_con_Mayusculas_y_guiones") && !R.validTopic(String(repeating: "a", count: 80)) && !R.validTopic("abc/../../x1234567890"))
        check("servidor https con y sin barra y puerto", R.normalizedServer("https://ntfy.sh") == "https://ntfy.sh" && R.normalizedServer(" https://ntfy.sh/ ") == "https://ntfy.sh" && R.normalizedServer("https://mi.servidor:8443") == "https://mi.servidor:8443")
        check("servidor http, con credenciales, con ruta o raro se rechaza", R.normalizedServer("http://ntfy.sh") == nil && R.normalizedServer("https://user:pw@ntfy.sh") == nil && R.normalizedServer("https://ntfy.sh/otro") == nil
              && R.normalizedServer("ftp://x") == nil && R.normalizedServer("") == nil && R.normalizedServer("ntfy.sh") == nil && R.normalizedServer("https://ntfy.sh?x=1") == nil)
        check("direccion de envio", R.url(server: "https://ntfy.sh", topic: topic)?.absoluteString == "https://ntfy.sh/" + topic && R.url(server: "http://x", topic: topic) == nil && R.url(server: "https://ntfy.sh", topic: "x") == nil)
        check("enlace de suscripcion para la app", R.subscribeLink(server: "https://ntfy.sh", topic: topic) == "ntfy://ntfy.sh/" + topic)

        let p = R.message(.permission, agent: "claude", tool: "Bash", project: "claude-pet", detail: "rm -rf build", language: .es)
        check("permiso: herramienta y proyecto, sin el comando", p.body == "Claude pide permiso: Bash en claude-pet" && !p.body.contains("rm -rf") && p.priority == 4)
        let withDetail = R.message(.permission, agent: "claude", tool: "Bash", project: "p", detail: "swift build\n-c release", includeDetail: true, language: .es)
        check("con detalle pedido, el comando va en una linea", withDetail.body.contains("swift build -c release") && !withDetail.body.contains("\n-c"))
        let secret = R.message(.permission, agent: "claude", tool: "Bash", project: "p", detail: "export KEY=sk-ant-api03-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", includeDetail: true, language: .es)
        check("un comando con secreto nunca viaja", !secret.body.contains("sk-ant"))
        check("riesgo alto avisa y sube la prioridad", R.message(.permission, agent: "claude", tool: "Bash", project: "p", risky: true, language: .es).priority == 5)
        check("el detalle se recorta", R.message(.permission, agent: "claude", tool: "Bash", project: "p", detail: String(repeating: "x", count: 500), includeDetail: true, language: .es).body.count < 200)
        check("fin de tarea con minutos", R.message(.done, agent: "codex", project: "api", seconds: 300, language: .es).body == "Codex terminó en api (5 min)")
        check("fallo y pregunta", R.message(.error, agent: "claude", project: "api", language: .es).body == "Claude falló en api" && R.message(.question, agent: "claude", project: "api", language: .es).body == "Claude te hace una pregunta en api")
        check("en ingles", R.message(.done, agent: "claude", project: "api", language: .en).body == "Claude finished in api")
        let planEs = R.message(.plan, agent: "claude", project: "secreto-interno", detail: "límite 5 horas: queda el 14% · se reinicia en 2 h 10 m", language: .es)
        check("plan: el aviso es el de la isla y no menciona el proyecto", planEs.body == "límite 5 horas: queda el 14% · se reinicia en 2 h 10 m" && !planEs.body.contains("secreto") && planEs.priority == 4)
        check("plan en ingles", R.message(.plan, agent: "claude", project: "", detail: "límite semanal: queda el 5% · se reinicia en 45 m", language: .en).body == "weekly limit: 5% left · resets in 45 m")
        check("plan: llega aunque se haya apagado el detalle", R.shouldSend(enabled: true, onlyAway: false, idleSeconds: 0, vistoConnected: false, kind: .plan))
        check("nunca lleva emojis ni etiquetas", !p.body.unicodeScalars.contains { $0.properties.isEmojiPresentation })

        check("apagado no envia", !R.shouldSend(enabled: false, onlyAway: false, idleSeconds: 999, vistoConnected: false, kind: .permission))
        check("solo si no estas: delante del Mac no envia", !R.shouldSend(enabled: true, onlyAway: true, idleSeconds: 5, vistoConnected: false, kind: .done))
        check("solo si no estas: un minuto fuera si envia", R.shouldSend(enabled: true, onlyAway: true, idleSeconds: 61, vistoConnected: false, kind: .done))
        check("sin la restriccion envia siempre", R.shouldSend(enabled: true, onlyAway: false, idleSeconds: 0, vistoConnected: false, kind: .permission))
        check("con Visto conectada no duplica", !R.shouldSend(enabled: true, onlyAway: false, idleSeconds: 999, vistoConnected: true, kind: .permission))

        print(failures == 0 ? "AVISOS OK" : "AVISOS \(failures) FALLOS")
        return failures == 0
    }
}
