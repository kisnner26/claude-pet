import Foundation
import CoreGraphics

enum DeskWorldSelfTest {
    static func run() -> Bool {
        var ok = true
        func check(_ name: String, _ c: Bool) { print((c ? "PASS " : "FAIL ") + name); if !c { ok = false } }
        func win(_ id: Int, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, owner: String = "Terminal", title: String = "") -> DeskWindow {
            DeskWindow(id: id, pid: Int32(id), owner: owner, title: title, frame: CGRect(x: x, y: y, width: w, height: h))
        }

        // coordenadas
        check("de CoreGraphics a AppKit se da la vuelta en vertical", DeskGeo.appKit(CGRect(x: 100, y: 50, width: 400, height: 300), primaryHeight: 900) == CGRect(x: 100, y: 550, width: 400, height: 300))
        check("una ventana en el borde de arriba queda pegada al tope en AppKit", DeskGeo.appKit(CGRect(x: 0, y: 0, width: 200, height: 100), primaryHeight: 900).maxY == 900)
        check("solo cuentan ventanas normales y de tamano util", DeskGeo.isUsable(layer: 0, frame: CGRect(x: 0, y: 0, width: 500, height: 400), alpha: 1, isOwn: false)
              && !DeskGeo.isUsable(layer: 25, frame: CGRect(x: 0, y: 0, width: 500, height: 400), alpha: 1, isOwn: false)
              && !DeskGeo.isUsable(layer: 0, frame: CGRect(x: 0, y: 0, width: 80, height: 30), alpha: 1, isOwn: false)
              && !DeskGeo.isUsable(layer: 0, frame: CGRect(x: 0, y: 0, width: 500, height: 400), alpha: 0, isOwn: false)
              && !DeskGeo.isUsable(layer: 0, frame: CGRect(x: 0, y: 0, width: 500, height: 400), alpha: 1, isOwn: true))

        // borde visible: ventanas de mas al frente primero
        let back = win(2, 100, 100, 600, 400)                    // borde superior a y = 500
        let alone = DeskGeo.visibleTop(of: 0, in: [back])
        check("una ventana sola tiene todo su borde libre", alone == [100...700])
        let covering = win(1, 300, 300, 200, 300)                // cruza y = 500 (de 300 a 600) y tapa de x 300 a 500
        let split = DeskGeo.visibleTop(of: 1, in: [covering, back])
        check("otra ventana por delante parte el borde en dos tramos", split == [100...300, 500...700])
        let below = win(1, 300, 100, 200, 300)                   // llega hasta y = 400: no cruza el borde
        check("una ventana por delante que no cruza el borde no lo tapa", DeskGeo.visibleTop(of: 1, in: [below, back]) == [100...700])
        let behind = win(3, 300, 300, 200, 300)
        check("una ventana por detras no tapa nada", DeskGeo.visibleTop(of: 0, in: [back, behind]) == [100...700])
        let wide = win(1, 0, 400, 1000, 300)
        check("si lo tapan entero no queda ningun tramo", DeskGeo.visibleTop(of: 1, in: [wide, back]).isEmpty)
        check("los trocitos demasiado cortos para pisar se descartan", DeskGeo.visibleTop(of: 1, in: [win(1, 110, 300, 580, 300), back]).isEmpty)
        check("el punto mas cercano queda dentro de un tramo", DeskGeo.nearest(400, in: [100...300, 500...700]) == 300 && DeskGeo.nearest(450, in: [100...300, 500...700]) == 500 && DeskGeo.nearest(50, in: [100...300]) == 100)
        check("con margen no pisa justo el borde", DeskGeo.nearest(100, in: [100...300], margin: 30) == 130 && DeskGeo.nearest(0, in: []) == nil)

        // suelo bajo los pies
        let floor: CGFloat = 80
        check("sin ventanas pisa el suelo de la pantalla", DeskPhysics.support(centerX: 400, feetY: 80, windows: [], floorY: floor) == DeskSurface(y: 80, window: nil))
        check("sobre una ventana pisa su borde superior", DeskPhysics.support(centerX: 400, feetY: 520, windows: [back], floorY: floor) == DeskSurface(y: 500, window: 0))
        check("fuera del ancho de la ventana sigue en el suelo", DeskPhysics.support(centerX: 800, feetY: 520, windows: [back], floorY: floor) == DeskSurface(y: 80, window: nil))
        check("si el borde queda mas alto de lo que salta, no sube", DeskPhysics.support(centerX: 400, feetY: 300, windows: [back], floorY: floor) == DeskSurface(y: 80, window: nil))
        check("si el borde esta a un salto, sube a la ventana", DeskPhysics.support(centerX: 400, feetY: 480, windows: [back], floorY: floor).window == 0)
        let tall = win(1, 150, 100, 200, 500)                    // borde en y = 600
        check("entre dos ventanas pisa la mas alta que alcance", DeskPhysics.support(centerX: 200, feetY: 620, windows: [tall, back], floorY: floor) == DeskSurface(y: 600, window: 0))
        check("no pisa un borde tapado por otra ventana", DeskPhysics.support(centerX: 400, feetY: 520, windows: [covering, back], floorY: floor) == DeskSurface(y: 80, window: nil))

        // caida y salto
        var body = DeskPhysics.Body(x: 400, feetY: 500)
        var steps = 0
        while body.feetY > 80 && steps < 600 { body = DeskPhysics.settle(body, ground: 80, dt: 1.0 / 60); steps += 1 }
        check("cae hasta el suelo y se para", body.feetY == 80 && body.vy == 0)
        check("la caida tarda lo que la gravedad manda (unos 0,5 s para 420 pt)", steps >= 25 && steps <= 40)
        var rising = DeskPhysics.Body(x: 400, feetY: 80)
        for _ in 0..<60 { rising = DeskPhysics.settle(rising, ground: 200, dt: 1.0 / 60) }
        check("si el suelo sube bajo ella, sube y se queda encima", rising.feetY == 200 && rising.vy == 0)
        check("en el suelo no se mueve", DeskPhysics.settle(DeskPhysics.Body(x: 0, feetY: 80), ground: 80, dt: 0.1) == DeskPhysics.Body(x: 0, feetY: 80, vy: 0))

        // paseo
        let w1 = DeskPhysics.walk(x: 100, toward: 400, dt: 0.1)
        check("camina hacia el destino y mira hacia alla", w1.walking && w1.facing == 1 && abs(w1.x - 115) < 0.01)
        let w2 = DeskPhysics.walk(x: 100, toward: 50, dt: 0.1)
        check("hacia la izquierda mira a la izquierda", w2.facing == -1 && w2.x < 100)
        let w3 = DeskPhysics.walk(x: 399, toward: 400, dt: 0.1)
        check("al llegar para y no se pasa", !w3.walking && w3.x == 400 && w3.facing == 0)
        var x: CGFloat = 0
        for _ in 0..<120 { x = DeskPhysics.walk(x: x, toward: 100, dt: 1.0 / 60).x }
        check("llega a su destino sin oscilar", x == 100)

        // apartarse
        let dragged = win(1, 360, 90, 300, 300)                  // una ventana arrastrada justo encima de donde esta, con borde a y = 390
        check("una ventana que le cae encima la aparta al lado libre mas cercano", DeskPhysics.sidestep(centerX: 420, feetY: 80, height: 90, windows: [dragged], supporting: nil) == 360 - DeskPhysics.half - 10)
        check("si esta mas cerca del otro lado se va por ese", DeskPhysics.sidestep(centerX: 600, feetY: 80, height: 90, windows: [dragged], supporting: nil) == 660 + DeskPhysics.half + 10)
        check("la ventana que la sostiene no la aparta", DeskPhysics.sidestep(centerX: 400, feetY: 500, height: 90, windows: [back], supporting: 0) == nil)
        check("una ventana lejos no la molesta", DeskPhysics.sidestep(centerX: 900, feetY: 80, height: 90, windows: [dragged], supporting: nil) == nil)
        check("una ventana con el borde a sus pies es suelo, no estorbo", DeskPhysics.sidestep(centerX: 400, feetY: 510, height: 90, windows: [back], supporting: nil) == nil)

        // saltos
        let leap = DeskLeap.make(from: CGPoint(x: 100, y: 80), to: CGPoint(x: 500, y: 300), now: 10)
        check("el salto empieza y acaba donde debe", leap.position(at: 10).point == CGPoint(x: 100, y: 80) && leap.position(at: 20).point == CGPoint(x: 500, y: 300) && leap.position(at: 20).done)
        let mid = leap.position(at: 10 + leap.duration / 2).point
        check("a mitad de camino va por encima de la recta (parabola)", mid.y > (80 + 300) / 2 + 20 && mid.x > 100 && mid.x < 500)
        check("un salto largo dura mas que uno corto", DeskLeap.make(from: .zero, to: CGPoint(x: 900, y: 0), now: 0).duration > DeskLeap.make(from: .zero, to: CGPoint(x: 60, y: 0), now: 0).duration)
        check("durante el salto no atraviesa el suelo al bajar", stride(from: 0.0, through: 1.0, by: 0.05).allSatisfy { leap.position(at: 10 + $0 * leap.duration).point.y >= 80 - 0.01 })

        // que quiere hacer cada mascota
        check("sin ventana donde posarse, descansa", DeskGoal.decide(state: .tool, hasWindow: false, secondsSinceBusy: 0) == .rest)
        check("trabajando se posa en la ventana", DeskGoal.decide(state: .tool, hasWindow: true, secondsSinceBusy: 0) == .perch && DeskGoal.decide(state: .thinking, hasWindow: true, secondsSinceBusy: 0) == .perch)
        check("esperando un permiso se asoma por detras", DeskGoal.decide(state: .waiting, hasWindow: true, secondsSinceBusy: 0) == .peek)
        check("al terminar sigue posada un rato y luego baja", DeskGoal.decide(state: .idle, hasWindow: true, secondsSinceBusy: 3) == .perch && DeskGoal.decide(state: .idle, hasWindow: true, secondsSinceBusy: 12) == .rest)
        check("claude y codex no se pisan en la misma ventana", DeskGoal.perchFraction(claude: true, both: true) < DeskGoal.perchFraction(claude: false, both: true) && DeskGoal.perchFraction(claude: true, both: false) == 0.75)
        check("el vaiven solo existe trabajando y no se sale de su amplitud", DeskGoal.pace(time: 3, working: false) == 0 && stride(from: 0.0, to: 20, by: 0.3).allSatisfy { abs(DeskGoal.pace(time: $0, working: true)) <= 34.001 })
        // donde se coloca segun el sitio que haya
        let screen = CGRect(x: 0, y: 0, width: 1680, height: 1000)
        check("con sitio encima se posa sobre el borde", DeskPlacement.perch(window: CGRect(x: 300, y: 100, width: 800, height: 500), screen: screen) == .above(feetY: 600))
        check("una ventana maximizada la deja dentro, bajo el tope de la pantalla", DeskPlacement.perch(window: CGRect(x: 0, y: 0, width: 1680, height: 1000), screen: screen) == .inside(feetY: 900))
        check("dentro nunca se sale por arriba", { if case .inside(let y) = DeskPlacement.perch(window: CGRect(x: 0, y: 0, width: 1680, height: 960), screen: screen) { return y + DeskPlacement.bodyHeight <= screen.maxY } else { return false } }())
        check("asomada con sitio encima, saca solo la cabeza", DeskPlacement.peek(window: CGRect(x: 300, y: 100, width: 800, height: 500), screen: screen, depth: 62) == .above(feetY: 538))
        check("sin sitio arriba se asoma por el lado derecho si hay hueco", DeskPlacement.peek(window: CGRect(x: 400, y: 0, width: 1000, height: 1000), screen: screen, depth: 62) == .side(x: 1410, feetY: 830))
        check("sin hueco a la derecha, por la izquierda", DeskPlacement.peek(window: CGRect(x: 300, y: 0, width: 1380, height: 1000), screen: screen, depth: 62) == .side(x: 290, feetY: 830))
        check("si no cabe por ningun lado, se posa dentro", DeskPlacement.peek(window: CGRect(x: 0, y: 0, width: 1680, height: 1000), screen: screen, depth: 62) == .inside(feetY: 900))
        // el Dock
        let dock = [DockItem(title: "Finder", frame: CGRect(x: 100, y: 10, width: 50, height: 50)), DockItem(title: "Terminal", frame: CGRect(x: 160, y: 10, width: 50, height: 50)),
                    DockItem(title: "Visual Studio Code", frame: CGRect(x: 220, y: 10, width: 50, height: 50)), DockItem(title: "Ghostty", frame: CGRect(x: 280, y: 10, width: 50, height: 50))]
        check("encuentra el icono por nombre exacto", DockInfo.item(forApp: "Terminal", in: dock)?.frame.minX == 160 && DockInfo.item(forApp: "terminal", in: dock)?.frame.minX == 160)
        check("encuentra un nombre parecido (Code en Visual Studio Code)", DockInfo.item(forApp: "Code", in: dock)?.frame.minX == 220)
        check("sin icono para una app que no esta en el Dock", DockInfo.item(forApp: "Cursor", in: dock) == nil && DockInfo.item(forApp: "", in: dock) == nil)
        check("el Dock solo sirve abajo y a la vista", DockInfo.isUsableLayout(orientation: "bottom", autohide: false) && DockInfo.isUsableLayout(orientation: nil, autohide: false)
              && !DockInfo.isUsableLayout(orientation: "left", autohide: false) && !DockInfo.isUsableLayout(orientation: "bottom", autohide: true))
        // llevar el archivo
        check("editar un archivo se lleva con su nombre y extension", FileCarry.editedFile(tool: "Edit", target: "/proyecto/Sources/App/Brain.swift")?.name == "Brain.swift" && FileCarry.editedFile(tool: "Write", target: "README.md")?.ext == "md")
        check("las herramientas de codex tambien cuentan", FileCarry.editedFile(tool: "apply_patch", target: "main.py")?.ext == "py")
        check("leer, buscar o ejecutar no llevan nada", FileCarry.editedFile(tool: "Read", target: "a.swift") == nil && FileCarry.editedFile(tool: "Bash", target: "swift build") == nil && FileCarry.editedFile(tool: "Grep", target: "x") == nil)
        check("sin nombre no hay archivo", FileCarry.editedFile(tool: "Edit", target: "") == nil && FileCarry.editedFile(tool: "Edit", target: "/") == nil)
        let editorWins = [win(1, 0, 0, 800, 600, owner: "Terminal", title: "claude"), win(2, 100, 100, 700, 500, owner: "Cursor", title: "Brain.swift — mi-app"), win(3, 200, 150, 700, 500, owner: "Xcode", title: "App.swift")]
        check("cae en la ventana del editor que menciona el archivo", FileCarry.destination(file: "App.swift", project: "mi-app", windows: editorWins, host: 0) == CGPoint(x: 550, y: 626))
        check("si ninguno lo menciona, en el editor del proyecto", FileCarry.destination(file: "Otro.swift", project: "mi-app", windows: editorWins, host: 0) == CGPoint(x: 450, y: 576))
        check("sin editores, en la ventana del agente", FileCarry.destination(file: "x.py", project: "p", windows: [editorWins[0]], host: 0) == CGPoint(x: 400, y: 576))
        check("sin ninguna ventana no hay destino", FileCarry.destination(file: "x", project: "p", windows: [], host: nil) == nil)
        let flight = FileFlight(from: CGPoint(x: 100, y: 200), to: CGPoint(x: 700, y: 400), start: 5)
        check("el vuelo empieza sobre la cabeza invisible y pequeno", flight.frame(at: 5).alpha == 0 && flight.frame(at: 5).scale < 0.35)
        check("antes de volar ya se ve entero", abs(flight.frame(at: 5 + FileFlight.hold).scale - 1) < 0.01 && abs(flight.frame(at: 5 + FileFlight.hold).alpha - 1) < 0.01)
        check("llega al destino al acabar el vuelo", abs(flight.frame(at: 5 + FileFlight.hold + FileFlight.fly).point.x - 700) < 0.01 && abs(flight.frame(at: 5 + FileFlight.hold + FileFlight.fly).point.y - 400) < 0.01)
        let halfway = flight.frame(at: 5 + FileFlight.hold + FileFlight.fly / 2).point
        check("a mitad de vuelo va en arco por encima de la recta", halfway.y > (206 + 400) / 2 + 30 && halfway.x > 100 && halfway.x < 700)
        check("al aterrizar se encoge y se apaga", flight.frame(at: 5 + FileFlight.total - 0.02).alpha < 0.15 && flight.frame(at: 5 + FileFlight.total).done)
        check("el vuelo dura menos de dos segundos", FileFlight.total < 2)
        // la pestana del archivo en un arbol de accesibilidad inventado
        func node(_ role: String, _ texts: [String], _ frame: CGRect?, _ kids: [AXSnap] = []) -> AXSnap { AXSnap(role: role, texts: texts, frame: frame, children: kids) }
        let tabBar = node("AXGroup", [], CGRect(x: 0, y: 580, width: 800, height: 30), [
            node("AXRadioButton", ["App.swift"], CGRect(x: 10, y: 582, width: 120, height: 26)),
            node("AXRadioButton", ["Brain.swift — Modificado"], CGRect(x: 135, y: 582, width: 160, height: 26), [node("AXStaticText", ["Brain.swift"], CGRect(x: 150, y: 588, width: 70, height: 14))]),
            node("AXRadioButton", ["Notas.md"], CGRect(x: 300, y: 582, width: 100, height: 26))])
        let tree = node("AXWindow", ["mi-app"], CGRect(x: 0, y: 0, width: 800, height: 610), [tabBar, node("AXTextArea", ["func dream() { Brain.swift }"], CGRect(x: 0, y: 0, width: 800, height: 570))])
        check("encuentra la pestana del archivo", TabFinder.find(tree, file: "Brain.swift") == CGRect(x: 135, y: 582, width: 160, height: 26))
        check("prefiere la pestana al texto suelto que la menciona", TabFinder.find(tree, file: "Brain.swift")?.width == 160)
        check("no confunde el cuerpo del editor con una pestana", TabFinder.find(tree, file: "dream") == nil)
        check("sin pestana con ese archivo no hay nada", TabFinder.find(tree, file: "Otro.swift") == nil)
        check("sin extension tambien lo reconoce si el nombre es largo", TabFinder.matches(["Brain — Editado"], file: "Brain.swift") && !TabFinder.matches(["App — Editado"], file: "App.swift"))
        check("un hueco diminuto no cuenta como pestana", TabFinder.find(node("AXWindow", [], nil, [node("AXButton", ["Brain.swift"], CGRect(x: 0, y: 0, width: 4, height: 4))]), file: "Brain.swift") == nil)
        let ghost = GhostMove(from: CGPoint(x: 500, y: 600), to: CGPoint(x: 215, y: 595), start: 3)
        check("el fantasma sale de donde cayo el archivo y acaba sobre la pestana", ghost.frame(at: 3).point == CGPoint(x: 500, y: 600) && ghost.frame(at: 3 + GhostMove.glide + 0.1).point == CGPoint(x: 215, y: 595))
        check("al llegar late: el anillo crece dos veces", { let rings = stride(from: 0.0, to: GhostMove.pulse, by: 0.02).map { ghost.frame(at: 3 + GhostMove.glide + $0).ring }; return (rings.max() ?? 0) > 0.9 && rings.indices.dropFirst().filter { rings[$0] < rings[$0 - 1] - 0.5 }.count == 1 }())
        check("al final se desvanece y termina", ghost.frame(at: 3 + GhostMove.total - 0.02).alpha < 0.15 && ghost.frame(at: 3 + GhostMove.total).done)
        print(ok ? "ESCRITORIO OK" : "ESCRITORIO FALLO")
        return ok
    }
}
