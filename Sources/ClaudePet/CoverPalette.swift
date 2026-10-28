import AppKit

/// Color de acento de una portada: el tono vivo que mas pesa, sin contar grises, blancos ni negros. Puro salvo `from(image:)`.
enum CoverPalette {
    static func hsv(_ r: Double, _ g: Double, _ b: Double) -> (h: Double, s: Double, v: Double) {
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        var h = 0.0
        if d > 0 {
            if mx == r { h = ((g - b) / d).truncatingRemainder(dividingBy: 6) } else if mx == g { h = (b - r) / d + 2 } else { h = (r - g) / d + 4 }
            h /= 6; if h < 0 { h += 1 }
        }
        return (h, mx == 0 ? 0 : d / mx, mx)
    }

    static func rgb(h: Double, s: Double, v: Double) -> (r: Double, g: Double, b: Double) {
        let hh = (h - h.rounded(.down)) * 6, c = v * s, x = c * (1 - abs(hh.truncatingRemainder(dividingBy: 2) - 1)), m = v - c
        let (r, g, b): (Double, Double, Double)
        switch Int(hh) { case 0: (r, g, b) = (c, x, 0); case 1: (r, g, b) = (x, c, 0); case 2: (r, g, b) = (0, c, x); case 3: (r, g, b) = (0, x, c); case 4: (r, g, b) = (x, 0, c); default: (r, g, b) = (c, 0, x) }
        return (r + m, g + m, b + m)
    }

    static func hex(_ c: (r: Double, g: Double, b: Double)) -> UInt32 {
        func b8(_ v: Double) -> UInt32 { UInt32(max(0, min(255, (v * 255).rounded()))) }
        return b8(c.r) << 16 | b8(c.g) << 8 | b8(c.b)
    }

    /// `pixels`: componentes 0...1. nil si la portada es casi toda gris, blanca o negra.
    static func dominant(_ pixels: [(r: Double, g: Double, b: Double)]) -> UInt32? {
        guard !pixels.isEmpty else { return nil }
        var weight = [Double](repeating: 0, count: 12)
        var sum = [(r: Double, g: Double, b: Double)](repeating: (0, 0, 0), count: 12)
        for p in pixels {
            let c = hsv(p.r, p.g, p.b)
            guard c.s > 0.25, c.v > 0.2 else { continue }          // los grises y los oscuros no son un color
            let k = min(11, Int(c.h * 12)), w = c.s * c.v
            weight[k] += w; sum[k] = (sum[k].r + p.r * w, sum[k].g + p.g * w, sum[k].b + p.b * w)
        }
        guard let best = weight.indices.max(by: { weight[$0] < weight[$1] }), weight[best] > 0.02 * Double(pixels.count) else { return nil }
        let avg = (r: sum[best].r / weight[best], g: sum[best].g / weight[best], b: sum[best].b / weight[best])
        let c = hsv(avg.r, avg.g, avg.b)
        return hex(rgb(h: c.h, s: max(c.s, 0.62), v: max(c.v, 0.88)))      // acento: vivo y claro para que se vea sobre negro
    }

    static func from(_ image: NSImage, side: Int = 24) -> UInt32? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil), side > 0 else { return nil }
        var data = [UInt8](repeating: 0, count: side * side * 4)
        guard let ctx = CGContext(data: &data, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
        var px: [(r: Double, g: Double, b: Double)] = []
        for i in stride(from: 0, to: data.count, by: 4) where data[i + 3] > 200 { px.append((Double(data[i]) / 255, Double(data[i + 1]) / 255, Double(data[i + 2]) / 255)) }
        return dominant(px)
    }

    /// Sin portada: un tono estable por titulo, el mismo que usa la portada de respaldo.
    static func fallback(seed: String) -> UInt32 {
        let h = Double(seed.utf8.reduce(UInt32(2166136261)) { ($0 ^ UInt32($1)) &* 16777619 } % 360) / 360
        return hex(rgb(h: h, s: 0.62, v: 0.9))
    }

    /// Tres tonos vecinos del acento para graves, medios y agudos.
    static func palette(tint: UInt32) -> [UInt32] {
        let c = hsv(Double(tint >> 16 & 0xFF) / 255, Double(tint >> 8 & 0xFF) / 255, Double(tint & 0xFF) / 255)
        return [tint, hex(rgb(h: c.h + 0.07, s: max(0.45, c.s * 0.85), v: 1)), hex(rgb(h: c.h - 0.07, s: max(0.35, c.s * 0.7), v: 1))]
    }
}
