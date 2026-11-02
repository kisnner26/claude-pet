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
        print(ok ? "ESCRITORIO OK" : "ESCRITORIO FALLO")
        return ok
    }
}
