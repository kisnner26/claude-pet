import Foundation
import CoreGraphics

enum TrackpadTouchSelfTest {
    static func run() -> Bool {
        var ok = true
        func check(_ name: String, _ c: Bool) { print((c ? "PASS " : "FAIL ") + name); if !c { ok = false } }

        // la estructura debe medir lo mismo que la de MultitouchSupport
        check("el contacto mide 96 bytes", MemoryLayout<MTTouchRaw>.size == 96)
        check("los campos que se leen estan en su sitio", MemoryLayout<MTTouchRaw>.offset(of: \.timestamp) == 8 && MemoryLayout<MTTouchRaw>.offset(of: \.identifier) == 16
              && MemoryLayout<MTTouchRaw>.offset(of: \.state) == 20 && MemoryLayout<MTTouchRaw>.offset(of: \.nx) == 32
              && MemoryLayout<MTTouchRaw>.offset(of: \.ny) == 36 && MemoryLayout<MTTouchRaw>.offset(of: \.zTotal) == 48 && MemoryLayout<MTTouchRaw>.offset(of: \.zDensity) == 92)

        var a = MTTouchRaw(); a.identifier = 7; a.state = 4; a.nx = 0.25; a.ny = 0.75; a.zTotal = 0.4
        var b = MTTouchRaw(); b.identifier = 8; b.state = 2; b.nx = 0.5; b.ny = 0.5                // flotando: no cuenta
        var c = MTTouchRaw(); c.identifier = 9; c.state = 3; c.nx = 0.9; c.ny = 0.1               // apoyando: cuenta
        var d = MTTouchRaw(); d.identifier = 10; d.state = 0
        let fingers = [a, b, c, d].withUnsafeBufferPointer { TrackpadTouch.fingers(from: $0.baseAddress!, count: 4) }
        check("solo cuentan los dedos apoyados", fingers.map(\.id) == [7, 9])
        check("se leen posicion y presion", fingers.first.map { abs($0.x - 0.25) < 1e-6 && abs($0.y - 0.75) < 1e-6 && abs($0.pressure - 0.4) < 1e-6 } == true)
        check("sin contactos no hay nada", [MTTouchRaw]().withUnsafeBufferPointer { TrackpadTouch.fingers(from: $0.baseAddress ?? UnsafePointer(bitPattern: 8)!, count: 0) }.isEmpty)
        check("un dedo mueve el cursor", TrackpadTouch.pointer([fingers[0]])?.id == 7)
        check("con dos dedos se dejan los gestos del sistema", TrackpadTouch.pointer(fingers) == nil && TrackpadTouch.pointer([]) == nil)

        check("un trackpad se reconoce por su forma", TrackpadTouch.isTrackpadShape(width: 10_500, height: 7_500) && TrackpadTouch.isTrackpadShape(width: 16, height: 10))
        check("la Touch Bar no es un trackpad", !TrackpadTouch.isTrackpadShape(width: 10_800, height: 600) && !TrackpadTouch.isTrackpadShape(width: 0, height: 0))

        // mapeo
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let center = TrackpadTouch.map(x: 0.5, y: 0.5, margin: 0.04, in: screen)
        check("el centro del trackpad es el centro de la pantalla", abs(center.x - 719.5) < 0.01 && abs(center.y - 449.5) < 0.01)
        let topLeft = TrackpadTouch.map(x: 0, y: 1, margin: 0, in: screen)
        check("arriba a la izquierda del trackpad es arriba a la izquierda de la pantalla", topLeft == CGPoint(x: 0, y: 0))
        let bottomRight = TrackpadTouch.map(x: 1, y: 0, margin: 0, in: screen)
        check("abajo a la derecha tambien", bottomRight == CGPoint(x: 1439, y: 899))
        let edge = TrackpadTouch.map(x: 0.04, y: 0.96, margin: 0.04, in: screen)
        check("el borde del margen ya alcanza la esquina", abs(edge.x) < 1e-6 && abs(edge.y) < 1e-6)
        let beyond = TrackpadTouch.map(x: 0.01, y: 0.99, margin: 0.04, in: screen)
        check("pasado el margen no se sale de la pantalla", beyond == CGPoint(x: 0, y: 0))
        let second = TrackpadTouch.map(x: 0.5, y: 0.5, margin: 0, in: CGRect(x: 1440, y: 0, width: 1920, height: 1080))
        check("con otra pantalla respeta su origen", abs(second.x - (1440 + 959.5)) < 0.01 && abs(second.y - 539.5) < 0.01)
        check("el margen absurdo se acota", TrackpadTouch.map(x: 0.5, y: 0.5, margin: 0.9, in: screen).x.isFinite)

        // suavizado
        var s = TrackpadSmoother()
        check("el primer punto no se arrastra desde ningun sitio", s.add(100, 100) == (100, 100))
        var jitter = 0.0
        for i in 0..<20 { let v = s.add(100 + (i % 2 == 0 ? 2 : -2), 100); jitter = max(jitter, abs(v.x - 100)) }
        check("quieto, el temblor se amortigua", jitter < 1.5)
        var f = TrackpadSmoother()
        _ = f.add(0, 0)
        check("en movimiento rapido casi no se queda atras", f.add(300, 0).x > 250)

        print(ok ? "TRACKPAD OK" : "TRACKPAD FALLO")
        return ok
    }
}
