import Foundation
import Network
import VistoCore

/// `ClaudePet --selftest-remote`: politica de riesgo y caducidad, y el anfitrion real con un cliente de Visto por loopback
/// (permisos pendientes, respuestas, riesgo alto rechazado, «siempre» inexistente, codigo equivocado, cambio de codigo).
enum RemoteApprovalsSelfTest {
    @MainActor static func run() -> Bool {
        setvbuf(stdout, nil, _IONBF, 0)
        var failures = 0
        func check(_ name: String, _ ok: Bool) { if !ok { failures += 1; print("FALLO \(name)") } }
        func spin(_ seconds: Double, until cond: () -> Bool = { false }) {
            let end = Date().addingTimeInterval(seconds)
            while !cond(), Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.03)) }
        }
        let now = Date()
        func ask(_ id: String, _ tool: String, _ detail: String, age: TimeInterval = 0) -> PermissionAsk {
            PermissionAsk(id: id, session: "s", tool: tool, project: "proy", detail: detail, canAlways: true, at: now.addingTimeInterval(-age))
        }
        let low = ask("a1", "Read", "README.md"), medium = ask("a2", "Bash", "swift build"), high = ask("a3", "Bash", "rm -rf build")

        check("bajo y medio se pueden permitir desde fuera", RemoteWire.verdict(allow: true, ask: low, now: now) == nil && RemoteWire.verdict(allow: true, ask: medium, now: now) == nil)
        check("riesgo alto no se permite desde fuera", RemoteWire.verdict(allow: true, ask: high, now: now)?.contains("Mac") == true)
        check("riesgo alto sí se puede denegar desde fuera", RemoteWire.verdict(allow: false, ask: high, now: now) == nil)
        check("permiso caducado se rechaza", RemoteWire.verdict(allow: true, ask: ask("a4", "Read", "x", age: 200), now: now) == "caducó")
        check("permiso inexistente se rechaza", RemoteWire.verdict(allow: true, ask: nil, now: now) != nil)
        let long = RemoteWire.wire(ask("a5", "Bash", String(repeating: "x", count: 900)))
        check("el detalle se recorta a 300", long.detail.count == 300)
        check("lleva riesgo y caducidad", long.risk == "medio" && long.expires > now)
        check("el riesgo alto viaja marcado y sin permitir", RemoteWire.wire(high).risk == "alto" && !RemoteWire.wire(high).canAllow)

        let dir = NSTemporaryDirectory() + "visto-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let codeFile = dir + "/visto-code"
        let link = RemoteLink(codePath: codeFile, advertise: false, hostName: "Mac de prueba")
        let c1 = link.code()
        check("el codigo se crea y es valido", Pairing.isValid(c1))
        check("el codigo se conserva entre arranques", RemoteLink(codePath: codeFile, advertise: false).code() == c1)
        let mode = ((try? FileManager.default.attributesOfItem(atPath: codeFile))?[.posixPermissions] as? Int) ?? 0
        check("el archivo del codigo es solo del usuario (0600)", mode & 0o077 == 0)

        var decisions: [(String, PermissionDecision)] = []
        link.onAnswer = { id, d in DispatchQueue.main.async { decisions.append((id, d)) } }
        link.sync([low, medium, high])          // pendientes antes de que nadie se conecte
        do { try link.start() } catch { print("FALLO no arranca el anfitrion: \(error)"); return false }
        check("escucha en un puerto", link.port > 0)

        let client = VistoClient()
        client.configure(code: c1, deviceName: "iPhone de prueba")
        client.start(direct: .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: link.port)!))
        spin(5) { client.isConnected && client.asks.count == 3 }
        check("el cliente se empareja con el codigo", client.hostName == "Mac de prueba")
        check("quien se conecta tarde ve los tres pendientes", Set(client.asks.map(\.id)) == ["a1", "a2", "a3"])
        check("el host ve al dispositivo", link.peers == ["iPhone de prueba"])

        client.answer("a2", allow: true)
        spin(2) { decisions.count == 1 }
        check("permitir uno de riesgo medio llega a la app", decisions.first?.0 == "a2" && decisions.first?.1 == .allow)
        client.answer("a3", allow: true)
        spin(2) { client.notice != nil }
        check("permitir uno de riesgo alto se rechaza y no llega", decisions.count == 1 && client.notice?.contains("Mac") == true && client.asks.contains { $0.id == "a3" })
        client.answer("a3", allow: false)
        spin(2) { decisions.count == 2 }
        check("denegar uno de riesgo alto sí llega", decisions.count == 2 && decisions[1].1 == .deny)
        client.answer("nope", allow: true)
        spin(1.5) { client.notice?.contains("pendiente") == true }
        check("responder a un id que no existe se rechaza", client.notice?.contains("pendiente") == true && decisions.count == 2)

        link.sync([low])
        spin(2) { client.asks.map(\.id) == ["a1"] }
        check("los resueltos en la Mac se retiran del dispositivo", client.asks.map(\.id) == ["a1"])
        link.sync([low, ask("a7", "Edit", "Sources/x.swift")])
        spin(2) { client.asks.count == 2 }
        check("un permiso nuevo llega una sola vez", client.asks.map(\.id) == ["a1", "a7"])
        link.sendPlan(PlanSnapshot(five: VistoCore.PlanWindow(usedPercent: 30, resetsAt: nil), week: nil))
        spin(2) { client.plan?.five != nil }
        check("el consumo del plan llega al dispositivo", client.plan?.five?.remaining() == 70)

        let wrong = VistoClient()
        wrong.configure(code: Pairing.newCode(), deviceName: "intruso")
        wrong.start(direct: .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: link.port)!))
        wrong.answer("a1", allow: true)
        spin(2)
        check("un codigo equivocado no se conecta ni responde", !wrong.isConnected && decisions.count == 2 && link.peers == ["iPhone de prueba"])
        wrong.stop()

        let c2 = (try? link.regenerateCode()) ?? ""
        spin(3) { !client.isConnected }
        check("cambiar el codigo desconecta a los dispositivos", Pairing.isValid(c2) && c2 != c1 && !client.isConnected && link.peers.isEmpty)
        client.stop()
        link.stop()
        check("al parar no queda nadie", link.peers.isEmpty)

        print(failures == 0 ? "REMOTO OK" : "REMOTO \(failures) FALLOS")
        return failures == 0
    }
}
