import Foundation

enum QuestionSelfTest {
    static func run() -> Bool {
        var failures = 0
        func check(_ name: String, _ ok: Bool) { print((ok ? "PASS " : "FAIL ") + name); if !ok { failures += 1 } }
        let raw: [[String: Any]] = [["header": "modo", "question": "que modo?", "multiSelect": false,
                                     "options": [["label": "rápido", "description": "menos pasos"], ["label": "seguro", "description": "más revisión"]]]]
        let data = try! JSONSerialization.data(withJSONObject: raw)
        let ask = QuestionServer.parse("ask\tsesión\tproyecto\t\(data.base64EncodedString())")
        check("parsea una pregunta con opciones", ask?.questions.first?.options.count == 2)
        check("conserva selección única", ask?.questions.first?.multiSelect == false)
        check("rechaza una línea inválida", QuestionServer.parse("ask\tx\tp\tno-base64") == nil)
        check("rechaza preguntas vacías", QuestionServer.parse("ask\tx\tp\t\(Data("[]".utf8).base64EncodedString())") == nil)
        print(failures == 0 ? "PREGUNTAS OK" : "PREGUNTAS FALLOS: \(failures)")
        return failures == 0
    }
}
