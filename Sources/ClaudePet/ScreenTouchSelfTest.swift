import Foundation
import CoreGraphics

enum ScreenTouchSelfTest {
    static func run() -> Bool {
        var ok = true
        func check(_ name: String, _ c: Bool) { print((c ? "PASS " : "FAIL ") + name); if !c { ok = false } }

        // piel
        check("un tono de piel claro es piel", SkinFilter.isSkin(r: 224, g: 172, b: 135))
        check("un tono de piel oscuro es piel", SkinFilter.isSkin(r: 141, g: 85, b: 64))
        check("azul, verde y negro no son piel", !SkinFilter.isSkin(r: 30, g: 60, b: 200) && !SkinFilter.isSkin(r: 40, g: 180, b: 60) && !SkinFilter.isSkin(r: 5, g: 5, b: 5))

        // manchas
        let w = 40, h = 30
        func mask(_ rects: [(Int, Int, Int, Int)]) -> [UInt8] {
            var m = [UInt8](repeating: 0, count: w * h)
            for (x0, y0, x1, y1) in rects { for y in y0...y1 { for x in x0...x1 { m[y * w + x] = 1 } } }
            return m
        }
        let two = BlobFinder.find(mask: mask([(10, 4, 19, 8), (11, 12, 18, 25)]), width: w, height: h, minArea: 10)
        check("dos rectangulos son dos manchas", two.count == 2)
        check("la mas grande va primero y la caja es exacta", two.first == Blob(minX: 11, maxX: 18, minY: 12, maxY: 25, area: 8 * 14) && two.last?.area == 50)
        check("las manchas pequenas se descartan", BlobFinder.find(mask: mask([(1, 1, 2, 2)]), width: w, height: h, minArea: 10).isEmpty)
        check("una mancha en diagonal no se une (4 vecinos)", BlobFinder.find(mask: mask([(5, 5, 6, 6), (7, 7, 8, 8)]), width: w, height: h, minArea: 1).count == 2)

        // lectura del toque
        let p = TouchParams()
        func read(_ gap: Int, prev: TouchReading? = nil, shiftX: Int = 0) -> TouchReading {
            let upper = (10, 4, 19, 8), lower = (10 + shiftX, 9 + gap, 19 + shiftX, min(h - 1, 9 + gap + 12))
            let blobs = BlobFinder.find(mask: mask([upper, lower]), width: w, height: h, minArea: 10)
            return MirrorTouch.read(blobs: blobs, width: w, height: h, params: p, previous: prev)
        }
        check("pegados es un toque", read(1).phase == .touch && read(2).phase == .touch)
        check("a media distancia flota", read(8).phase == .hover)
        check("lejos no hay nada", read(20).phase == .none)
        check("sin solape horizontal no cuenta", read(1, shiftX: 25).phase == .none)
        let t = read(2)
        check("el punto cae en el hueco entre las dos manchas", abs(t.y - (Double(8) + Double(9 + 2)) / 2 / Double(h)) < 0.001 && abs(t.x - (10.0 + 19.0) / 2 / Double(w)) < 0.001)
        let merged = MirrorTouch.read(blobs: BlobFinder.find(mask: mask([(10, 4, 19, 25)]), width: w, height: h, minArea: 10), width: w, height: h, params: p, previous: t)
        check("si se funden tras un toque sigue siendo toque", merged.phase == .touch && merged.x == t.x && merged.y == t.y)
        let lone = MirrorTouch.read(blobs: BlobFinder.find(mask: mask([(10, 4, 19, 25)]), width: w, height: h, minArea: 10), width: w, height: h, params: p, previous: read(20))
        check("una sola mancha sin toque previo no es nada", lone.phase == .none)
        check("la mancha unica tras flotar lejos no se agarra", MirrorTouch.read(blobs: [Blob(minX: 0, maxX: 5, minY: 0, maxY: 5, area: 36)], width: w, height: h, params: p, previous: read(8)).phase == .none)

        // homografia
        let src: [(Double, Double)] = ScreenTouchCalibration.targets
        func truth(_ x: Double, _ y: Double) -> (Double, Double) {          // una perspectiva fuerte: giro, escala y fuga
            let d = 1 + 0.35 * x - 0.2 * y
            return ((0.8 * x + 0.15 * y + 0.1) / d * 1440, (-0.1 * x + 0.9 * y + 0.05) / d * 900)
        }
        let dst = src.map { truth($0.0, $0.1) }
        let hg = Homography.fit(from: src, to: dst)
        check("la homografia recupera la perspectiva", hg.map { $0.meanError(from: src, to: dst) < 0.001 } == true)
        let q = hg?.apply(0.33, 0.61), tq = truth(0.33, 0.61)
        check("y acierta en puntos que no uso para ajustar", q.map { abs($0.x - tq.0) < 0.01 && abs($0.y - tq.1) < 0.01 } == true)
        var noisy = dst
        for i in noisy.indices { noisy[i].0 += Double((i * 7) % 5) - 2; noisy[i].1 += Double((i * 3) % 5) - 2 }       // +-2 px
        let hn = Homography.fit(from: src, to: noisy)
        check("con ruido de 2 px el error medio sigue bajo", hn.map { $0.meanError(from: src, to: dst) < 4 } == true)
        check("con puntos alineados no hay solucion", Homography.fit(from: [(0, 0), (1, 1), (2, 2), (3, 3)], to: [(0, 0), (1, 1), (2, 2), (3, 3)]) == nil)
        check("con menos de cuatro pares no hay solucion", Homography.fit(from: Array(src.prefix(3)), to: Array(dst.prefix(3))) == nil)
        check("la calibracion tiene nueve puntos, esquinas incluidas", ScreenTouchCalibration.targets.count == 9
              && ScreenTouchCalibration.targets.contains { $0.0 < 0.1 && $0.1 < 0.1 } && ScreenTouchCalibration.targets.contains { $0.0 > 0.9 && $0.1 > 0.9 })
        let pts = ScreenTouchCalibration.screenPoints(in: CGRect(x: 0, y: 0, width: 1000, height: 500))
        check("los puntos de pantalla caen dentro del area", pts.allSatisfy { $0.0 > 0 && $0.0 < 1000 && $0.1 > 0 && $0.1 < 500 })

        // suavizado y antirrebote
        var sm = PointSmoother()
        _ = sm.add(0, 0)
        var jitter = 0.0
        for i in 0..<20 { let v = sm.add(i % 2 == 0 ? 1 : -1, 0); jitter = max(jitter, abs(v.x)) }
        check("quieto, el temblor se amortigua", jitter < 0.5)
        var fast = PointSmoother()
        _ = fast.add(0, 0)
        check("en movimiento rapido casi no se queda atras", fast.add(200, 0).x > 150)
        var db = TouchDebouncer()
        check("un solo fotograma no empieza un toque", db.feed(true) == .none && db.feed(false) == .none)
        check("dos seguidos lo empiezan", db.feed(true) == .none && db.feed(true) == .pressed && db.pressed)
        check("un parpadeo no suelta el boton", db.feed(false) == .none && db.feed(true) == .none && db.pressed)
        check("tres sin toque lo sueltan", db.feed(false) == .none && db.feed(false) == .none && db.feed(false) == .released && !db.pressed)

        // pellizco
        let hand = (wrist: CGPoint(x: 0.5, y: 0.2), mid: CGPoint(x: 0.5, y: 0.5))
        let open = Pinch.ratio(thumb: CGPoint(x: 0.35, y: 0.4), index: CGPoint(x: 0.6, y: 0.55), wrist: hand.wrist, middleBase: hand.mid)
        let closed = Pinch.ratio(thumb: CGPoint(x: 0.52, y: 0.5), index: CGPoint(x: 0.54, y: 0.52), wrist: hand.wrist, middleBase: hand.mid)
        check("el pellizco se mide respecto a la mano", open > Pinch.release && closed < Pinch.engage)
        check("el pellizco tiene histeresis", Pinch.closed(ratio: 0.35, wasClosed: true) && !Pinch.closed(ratio: 0.35, wasClosed: false))

        print(ok ? "PANTALLA TACTIL OK" : "PANTALLA TACTIL FALLO")
        return ok
    }
}
