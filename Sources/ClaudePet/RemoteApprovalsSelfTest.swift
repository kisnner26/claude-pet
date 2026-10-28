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

        // preguntas de Claude, agentes, actividad, avisos y modo foco
        let single = IslandQuestion(id: "i1", header: "Plan", question: "¿Cuál?", options: [("A", "uno"), ("B", "dos"), ("Otra", "libre")], multiSelect: false)
        let multi = IslandQuestion(id: "i2", header: "Extras", question: "¿Qué más?", options: [("x", ""), ("y", ""), ("z", "")], multiSelect: true)
        let qask = QuestionAsk(id: "q1", session: "s", project: "proy", questions: [single, multi])
        check("respuesta valida se convierte en etiquetas", RemoteWire.answers(for: qask, picks: [[1], [0, 2]]) == ["¿Cuál?": "B", "¿Qué más?": "x, z"])
        check("indice fuera de rango se rechaza", RemoteWire.answers(for: qask, picks: [[7], [0]]) == nil)
        check("dos opciones en una pregunta simple se rechazan", RemoteWire.answers(for: qask, picks: [[0, 1], [0]]) == nil)
        check("sin elegir nada se rechaza", RemoteWire.answers(for: qask, picks: [[], [0]]) == nil)
        check("faltan preguntas por responder", RemoteWire.answers(for: qask, picks: [[0]]) == nil)
        var qAnswers: [(String, [String: String])] = [], focusSet: [Bool] = [], events: [(String, String, Int)] = []
        link.onQuestionAnswer = { id, a in DispatchQueue.main.async { qAnswers.append((id, a)) } }
        link.onFocus = { on in DispatchQueue.main.async { focusSet.append(on) } }
        client.onEvent = { kind, agent, _, secs in events.append((kind, agent, secs)) }
        link.syncQuestions([qask])
        spin(2) { client.questions.count == 1 }
        check("la pregunta llega con sus opciones", client.questions.first?.items.first?.options == ["A", "B", "Otra"] && client.questions.first?.items.last?.multi == true)
        client.reply("q1", picks: [[7], [0]])
        spin(0.8)
        check("una respuesta con indices invalidos no llega a la app", qAnswers.isEmpty)
        client.reply("q1", picks: [[1], [0, 2]])
        spin(2) { qAnswers.count == 1 }
        check("responder la pregunta llega con etiquetas", qAnswers.first?.0 == "q1" && qAnswers.first?.1 == ["¿Cuál?": "B", "¿Qué más?": "x, z"])
        link.syncQuestions([])
        link.sendAgents([RemoteWire.agent("claude", state: .tool, project: "proy", since: Date(), context: 55), RemoteWire.agent("codex", state: .idle, project: "", since: Date(), context: nil)])
        spin(2) { client.agents.count == 2 }
        check("los agentes llegan con su estado y contexto", client.agents.first?.state == "tool" && client.agents.first?.isBusy == true && client.agents.first?.contextRemaining == 55)
        link.sendFeed([RemoteWire.step(IslandStep(agent: "claude", tool: "Edit", target: "Sources/ClaudePet/Algo.swift", added: 3, deleted: 1, workspace: "w", at: Date()))])
        spin(2) { !client.feed.isEmpty }
        check("la actividad llega sin contenido de archivos", client.feed.first?.tool == "Edit" && client.feed.first?.delta == "+3 -1")
        link.sendEvent(kind: "done", agent: "claude", project: "proy", seconds: 90)
        spin(2) { !events.isEmpty }
        check("el aviso de terminado llega", events.first?.0 == "done" && events.first?.2 == 90)
        link.sendFocus(true)
        spin(2) { client.focus }
        check("el modo foco se difunde", client.focus)
        client.setFocus(false)
        spin(2) { !focusSet.isEmpty }
        check("pedir el modo foco desde el movil llega a la app", focusSet == [false])

        // el estado real de la mascota llega a Visto como agentes
        let st = PetStore.shared
        if let e = PetEvent.parse("thinking\tselftest-visto\t\tproy\t\tterminal\t\t/tmp") { st.apply(e) }
        let agentsNow = RemoteWire.agents(from: st)
        check("un evento de Claude se convierte en un agente en Visto", agentsNow.contains { $0.agent == "claude" && $0.state == "thinking" && $0.project == "tmp" })
        if let e = PetEvent.parse("end\tselftest-visto") { st.apply(e) }

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
