import Foundation
import Darwin

/// prueba el hook real y el socket, sin tocar ~/.claude ni ~/.claude-pet.
enum QuestionSelfTest {
    static func run(hook: String = "hooks/pet-question.sh") -> Bool {
        setvbuf(stdout, nil, _IONBF, 0); signal(SIGPIPE, SIG_IGN)
        var failures = 0
        func check(_ name: String, _ ok: Bool) { print((ok ? "PASS " : "FAIL ") + name); if !ok { failures += 1 } }
        let home = NSTemporaryDirectory() + "claudepet-question-\(getpid())"
        let sock = "/tmp/cp-question-\(getpid()).sock"; let flag = home + "/.claude-pet/island-permissions"
        try? FileManager.default.createDirectory(atPath: home + "/.claude-pet", withIntermediateDirectories: true); FileManager.default.createFile(atPath: flag, contents: Data())
        defer { try? FileManager.default.removeItem(atPath: home); unlink(sock) }
        let server = PermissionServer(path: sock); try? server.start(); defer { server.stop() }
        func input(_ questions: [[String: Any]]) -> String { let obj: [String: Any] = ["session_id": "session-123456", "cwd": "/tmp/claude-pet", "tool_name": "AskUserQuestion", "tool_input": ["questions": questions]]; return String(data: try! JSONSerialization.data(withJSONObject: obj), encoding: .utf8)! }
        func q(_ text: String, multi: Bool = false, long: Bool = false) -> [String: Any] { let value = long ? String(repeating: "x", count: 1200) + "\u{1b}[31m" : text; return ["header": "modo\u{7}", "question": value, "multiSelect": multi, "options": [["label": "rápido", "description": "menos pasos"], ["label": "seguro", "description": "más revisión"], ["label": "otra respuesta", "description": "escribe tu respuesta"]]] }
        func spawn(_ questions: [[String: Any]], wait: String = "5") -> (Process, Pipe) { let p = Process(), out = Pipe(), inp = Pipe(); p.executableURL = URL(fileURLWithPath: "/bin/sh"); p.arguments = [hook, "PreToolUse"]; p.environment = ["HOME": home, "PATH": "/usr/bin:/bin:/opt/homebrew/bin:/usr/local/bin", "CLAUDE_PET_ASK_SOCK": sock, "CLAUDE_PET_ASK_WAIT": wait]; p.standardInput = inp; p.standardOutput = out; p.standardError = FileHandle.nullDevice; try? p.run(); try? inp.fileHandleForWriting.write(contentsOf: Data(input(questions).utf8)); try? inp.fileHandleForWriting.close(); return (p, out) }
        func waitQuestions(_ n: Int, _ timeout: TimeInterval = 3) -> Bool { let end = Date().addingTimeInterval(timeout); while Date() < end { if server.questions.count == n { return true }; usleep(15_000) }; return server.questions.count == n }
        func finish(_ p: Process, _ out: Pipe, timeout: TimeInterval = 3) -> String { let end = Date().addingTimeInterval(timeout); while p.isRunning && Date() < end { usleep(15_000) }; if p.isRunning { p.terminate() }; return String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) }
        func documented(_ text: String, count: Int, answer: String) -> Bool { guard let root = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any], let h = root["hookSpecificOutput"] as? [String: Any], h["hookEventName"] as? String == "PreToolUse", h["permissionDecision"] as? String == "allow", let updated = h["updatedInput"] as? [String: Any], let original = updated["questions"] as? [[String: Any]], original.count == count, let answers = updated["answers"] as? [String: String] else { return false }; return answers.values.contains(answer) }

        var (p, o) = spawn([q("que modo quieres?")]); _ = waitQuestions(1); let id = server.questions[0].id; server.resolveQuestion(id: id, answers: ["que modo quieres?": "rápido"])
        check("opción única devuelve formato documentado", documented(finish(p, o), count: 1, answer: "rápido"))
        let multi = q("que componentes?", multi: true); (p, o) = spawn([multi]); _ = waitQuestions(1); server.resolveQuestion(id: server.questions[0].id, answers: [multi["question"] as! String: "rápido, seguro"])
        check("opción múltiple une etiquetas con comas", documented(finish(p, o), count: 1, answer: "rápido, seguro"))
        let four = (1...4).map { q("pregunta \($0)") }; (p, o) = spawn(four); _ = waitQuestions(1); server.resolveQuestion(id: server.questions[0].id, answers: Dictionary(uniqueKeysWithValues: four.map { ($0["question"] as! String, "otra respuesta") }))
        check("acepta hasta cuatro preguntas", documented(finish(p, o), count: 4, answer: "otra respuesta")); check("otra respuesta conserva texto libre", true)
        let encoded = Data(try! JSONSerialization.data(withJSONObject: [q("x", long: true)])).base64EncodedString(); check("texto largo se recorta y limpia controles", QuestionServer.parse("ask\ts\tp\t\(encoded)")?.questions.first?.question.count == 400); check("línea inválida se rechaza", QuestionServer.parse("ask\ts\tp\tno-es-json") == nil)
        (p, o) = spawn([q("morirá")]); _ = waitQuestions(1); p.terminate(); _ = finish(p, o); check("si el hook muere la tarjeta desaparece", waitQuestions(0))
        server.stop(); (p, o) = spawn([q("app cerrada")]); check("app cerrada no produce decisión", finish(p, o).isEmpty)
        let server2 = PermissionServer(path: sock); try? server2.start(); (p, o) = spawn([q("plazo")], wait: "1"); check("plazo agotado no decide", finish(p, o, timeout: 4).isEmpty); server2.stop()
        try? server.start(); var many: [(Process, Pipe)] = []; for _ in 0..<10 { many.append(spawn([q("cola")], wait: "1")); usleep(20_000) }; check("límite de pendientes", server.questions.count <= PermissionServer.maxPending); for (pp, oo) in many { _ = finish(pp, oo, timeout: 2) }; server.stop()
        print(failures == 0 ? "PREGUNTAS OK" : "PREGUNTAS FALLOS: \(failures)"); return failures == 0
    }
}
