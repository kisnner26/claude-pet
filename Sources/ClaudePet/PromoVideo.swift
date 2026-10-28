import SwiftUI
import AppKit
import AVFoundation

/// `ClaudePet --render-promo <salida.mp4>`: el video de presentacion, hecho con las propias vistas y animaciones de la app
/// (la isla, las mascotas con su animador real, los atuendos y el enfado) y codificado con AVFoundation. Sin ffmpeg ni navegador.
@MainActor
enum PromoVideo {
    static let width = 1920, height = 1080, fps = 30
    static let duration = 53.0
    /// Instantes de corte entre escenas (tambien marcan los golpes del sonido).
    static let cuts: [Double] = [0, 4, 10, 16, 22, 28, 35, 41, 47]

    struct Assets {
        var islandWorking: NSImage?, islandPermission: NSImage?, visto: NSImage?
        var montage: [(NSImage?, String)] = []
    }

    // MARK: arranque

    static func run(output: String) {
        let saved = L.current
        L.current = .es
        defer { L.current = saved }
        Sprite.skin = .block
        let assets = loadAssets()
        let silent = NSTemporaryDirectory() + "promo-silent-\(UUID().uuidString).mp4"
        let audio = NSTemporaryDirectory() + "promo-audio-\(UUID().uuidString).m4a"
        defer { try? FileManager.default.removeItem(atPath: silent); try? FileManager.default.removeItem(atPath: audio) }
        guard encodeVideo(to: silent, assets: assets) else { fputs("no se pudo codificar el video\n", stderr); return }
        guard writeAudio(to: audio) else { fputs("no se pudo crear el audio\n", stderr); return }
        try? FileManager.default.removeItem(atPath: output)
        guard mux(video: silent, audio: audio, to: output) else { fputs("no se pudo unir audio y video\n", stderr); return }
        print("listo: \(output)")
    }

    /// Para revisar: guarda unos cuadros sueltos como PNG.
    static func frames(to dir: String, times: [Double]) {
        let saved = L.current; L.current = .es; defer { L.current = saved }
        Sprite.skin = .block
        let assets = loadAssets()
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for t in times {
            let r = ImageRenderer(content: PromoFrame(t: t, assets: assets))
            r.proposedSize = ProposedViewSize(width: CGFloat(width), height: CGFloat(height)); r.scale = 1
            if let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: dir + "/t\(String(format: "%05.1f", t)).png"))
            }
        }
    }

    // MARK: recursos

    private static func repoPath(_ rel: String) -> String { FileManager.default.currentDirectoryPath + "/" + rel }

    private static func islandImage(_ apply: (IslandModel, PetStore) -> Void, ask: Bool) -> NSImage? {
        let store = PetStore.shared
        IslandSnapshot.isRendering = true
        defer { IslandSnapshot.isRendering = false; store.permissionAsks = [] }
        let m = ScreenMetrics(frame: CGRect(x: 0, y: 0, width: 1440, height: 900), safeTop: 0, auxLeft: 0, auxRight: 0)
        let model = IslandModel()
        model.mode = .expanded; model.placement = .top; model.hasNotch = false
        apply(model, store)
        model.size = NotchGeometry.islandSize(.expanded, metrics: m, placement: .top, expandedHeight: ask ? NotchGeometry.permissionHeight : NotchGeometry.expandedHeight)
        let view = IslandView(model: model, store: store).frame(width: NotchGeometry.panelSize.width, height: NotchGeometry.panelSize.height, alignment: .top)
        let r = ImageRenderer(content: view); r.scale = 2
        return r.nsImage
    }

    private static func loadAssets() -> Assets {
        var a = Assets()
        let now = Date()
        a.islandWorking = islandImage({ _, s in
            s.permissionAsks = []; s.setSnapshotState(.tool)
            s.setSnapshotContext(ContextReading(usedTokens: 112_000, compactAtTokens: 160_000, model: "claude"))
            s.setSnapshotSteps([IslandStep(agent: "claude", tool: "Read", target: "src/billing.ts", added: 0, deleted: 0, workspace: "", at: now.addingTimeInterval(-42)),
                                IslandStep(agent: "claude", tool: "Edit", target: "src/billing.ts", added: 3, deleted: 1, workspace: "", at: now.addingTimeInterval(-18)),
                                IslandStep(agent: "claude", tool: "Bash", target: "npm test", added: 0, deleted: 0, workspace: "", at: now.addingTimeInterval(-3))])
        }, ask: false)
        let ask = PermissionAsk(id: "p", session: "s", tool: "Bash", project: "korus", detail: "git push origin main", canAlways: true, at: now)
        a.islandPermission = islandImage({ _, s in s.setSnapshotState(.waiting); s.permissionAsks = [ask] }, ask: true)
        a.visto = NSImage(contentsOfFile: repoPath("docs/img/visto-mascotas.jpg"))
        a.montage = [("ajustes-plugins.jpg", "plugins y taller"), ("ajustes-guardarropa.jpg", "un guardarropa para cada una"), ("dock.jpg", "acceso rápido según la app"), ("perimetro-permiso.jpg", "un perímetro por proyecto")]
            .map { (NSImage(contentsOfFile: repoPath("docs/img/" + $0.0)), $0.1) }
        return a
    }

    // MARK: codificacion

    private static func encodeVideo(to path: String, assets: Assets) -> Bool {
        guard let writer = try? AVAssetWriter(outputURL: URL(fileURLWithPath: path), fileType: .mp4) else { return false }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 9_000_000, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel]])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height])
        writer.add(input)
        guard writer.startWriting() else { return false }
        writer.startSession(atSourceTime: .zero)
        let total = Int(duration * Double(fps))
        for i in 0..<total {
            while !input.isReadyForMoreMediaData { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
            autoreleasepool {
                let t = Double(i) / Double(fps)
                let r = ImageRenderer(content: PromoFrame(t: t, assets: assets))
                r.proposedSize = ProposedViewSize(width: CGFloat(width), height: CGFloat(height)); r.scale = 1
                guard let cg = r.cgImage, let pool = adaptor.pixelBufferPool else { return }
                var pb: CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb)
                guard let buf = pb else { return }
                CVPixelBufferLockBaseAddress(buf, [])
                if let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buf), width: width, height: height, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buf),
                                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
                    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
                }
                CVPixelBufferUnlockBaseAddress(buf, [])
                adaptor.append(buf, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: CMTimeScale(fps)))
            }
            if i % 60 == 0 { print("cuadro \(i)/\(total)"); fflush(stdout) }
        }
        input.markAsFinished()
        let sem = DispatchSemaphore(value: 0)
        writer.finishWriting { sem.signal() }
        while sem.wait(timeout: .now() + 0.05) == .timedOut { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        return writer.status == .completed
    }

    // MARK: sonido: un colchon suave y un golpe grave en cada corte, sintetizado

    private static func writeAudio(to path: String) -> Bool {
        let rate = 44_100.0, frames = AVAudioFrameCount(duration * rate)
        guard let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 2, interleaved: false), let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frames),
              let ch = buf.floatChannelData else { return false }
        buf.frameLength = frames
        // acordes (Am, F, C, G) como suma de senos con ataque lento
        let chords: [[Double]] = [[110.0, 164.81, 220.0, 261.63], [87.31, 130.81, 174.61, 220.0], [130.81, 196.0, 261.63, 329.63], [98.0, 146.83, 196.0, 246.94]]
        var rng = SystemRandomNumberGenerator()
        for n in 0..<Int(frames) {
            let t = Double(n) / rate
            let idx = Int(t / 6.5) % chords.count, nextIdx = (idx + 1) % chords.count
            let k = min(1, max(0, (t.truncatingRemainder(dividingBy: 6.5) - 5.2) / 1.3))      // fundido entre acordes
            var pad = 0.0
            for (i, f) in chords[idx].enumerated() { pad += sin(2 * .pi * f * t + Double(i)) * (1 - k) * (0.5 / Double(i + 1) + 0.15) }
            for (i, f) in chords[nextIdx].enumerated() { pad += sin(2 * .pi * f * t + Double(i)) * k * (0.5 / Double(i + 1) + 0.15) }
            let swell = min(1, t / 3) * min(1, (duration - t) / 3)
            var s = pad * 0.10 * swell
            for c in cuts where t >= c && t < c + 0.9 {
                let e = t - c
                s += sin(2 * .pi * (55 - 12 * e) * e) * exp(-e * 5) * 0.55 + Double.random(in: -1...1, using: &rng) * exp(-e * 40) * 0.08
            }
            ch[0][n] = Float(s * 0.8); ch[1][n] = Float(s * 0.8 + sin(t * 0.3) * pad * 0.01)
        }
        guard let file = try? AVAudioFile(forWriting: URL(fileURLWithPath: path), settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: rate, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 160_000]) else { return false }
        do { try file.write(from: buf) } catch { return false }
        return true
    }

    private static func mux(video: String, audio: String, to output: String) -> Bool {
        let comp = AVMutableComposition()
        let v = AVURLAsset(url: URL(fileURLWithPath: video)), a = AVURLAsset(url: URL(fileURLWithPath: audio))
        guard let vt = v.tracks(withMediaType: .video).first, let at = a.tracks(withMediaType: .audio).first,
              let cv = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let ca = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { return false }
        let range = CMTimeRange(start: .zero, duration: v.duration)
        try? cv.insertTimeRange(range, of: vt, at: .zero)
        try? ca.insertTimeRange(CMTimeRange(start: .zero, duration: min(v.duration, a.duration)), of: at, at: .zero)
        guard let export = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetPassthrough) else { return false }
        export.outputURL = URL(fileURLWithPath: output); export.outputFileType = .mp4
        let sem = DispatchSemaphore(value: 0)
        export.exportAsynchronously { sem.signal() }
        while sem.wait(timeout: .now() + 0.05) == .timedOut { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        return export.status == .completed
    }
}

// MARK: cuadro

private func smooth(_ x: Double) -> Double { let c = min(1, max(0, x)); return c * c * (3 - 2 * c) }
private func seg(_ t: Double, _ a: Double, _ b: Double) -> Double { smooth((t - a) / max(0.001, b - a)) }

@MainActor
struct PromoFrame: View {
    let t: Double
    let assets: PromoVideo.Assets
    private let ink = Color(hex: 0xF4F1EA)

    private var scene: Int { PromoVideo.cuts.lastIndex { t >= $0 } ?? 0 }
    private func local(_ i: Int) -> Double { t - PromoVideo.cuts[i] }
    private func len(_ i: Int) -> Double { (i + 1 < PromoVideo.cuts.count ? PromoVideo.cuts[i + 1] : PromoVideo.duration) - PromoVideo.cuts[i] }

    var body: some View {
        ZStack {
            Color.black
            RadialGradient(colors: [Color(hex: 0x1C2540).opacity(0.55), .clear], center: UnitPoint(x: 0.5, y: 0.35), startRadius: 0, endRadius: 900)
            content
            // barras de cine y fundido de cada corte
            VStack { Color.black.frame(height: 70); Spacer(); Color.black.frame(height: 70) }
            Color.black.opacity(1 - seg(local(scene), 0, 0.45) + seg(local(scene), len(scene) - 0.35, len(scene)) * (scene == PromoVideo.cuts.count - 1 ? 0 : 1) * 0)
        }
        .frame(width: CGFloat(PromoVideo.width), height: CGFloat(PromoVideo.height))
        .clipped()
    }

    @ViewBuilder private var content: some View {
        switch scene {
        case 0: intro
        case 1: islandScene(assets.islandWorking, "Mira lo que hacen\ntus agentes.", "estado en vivo · la tarea exacta · el contexto que queda")
        case 2: islandScene(assets.islandPermission, "Aprueba sin salir\nde lo que haces.", "riesgo, secretos y perímetro en cada permiso")
        case 3: pets
        case 4: weather
        case 5: rage
        case 6: companion
        case 7: montage
        default: outro
        }
    }

    // MARK: texto

    private func title(_ s: String, _ lt: Double, at a: Double, size: CGFloat = 92, y: CGFloat = 0) -> some View {
        let p = seg(lt, a, a + 0.9)
        return Text(s).font(.system(size: size, weight: .semibold)).tracking(-size * 0.02).multilineTextAlignment(.center).foregroundColor(ink)
            .lineSpacing(-4).blur(radius: (1 - p) * 22).opacity(p).scaleEffect(1.04 - 0.04 * p).offset(y: y)
    }

    private func caption(_ s: String, _ lt: Double, at a: Double) -> some View {
        let p = seg(lt, a, a + 0.7)
        return Text(s.uppercased()).font(.system(size: 22, weight: .medium, design: .monospaced)).tracking(4).foregroundColor(ink.opacity(0.62 * p)).offset(y: (1 - p) * 10)
    }

    // MARK: escenas

    private var intro: some View {
        let lt = local(0)
        return ZStack {
            PromoPet(agent: .claude, t: t, size: 420, outfits: [], pokes: [], state: .idle)
                .scaleEffect(0.75 + 0.25 * seg(lt, 0.2, 1.4)).opacity(seg(lt, 0.2, 1.0)).offset(y: -120 - 40 * seg(lt, 1.6, 3.2))
            VStack(spacing: 18) {
                Spacer().frame(height: 330)
                title("claude pet.", lt, at: 1.5, size: 150)
                caption("dos mascotas para tus agentes de código", lt, at: 2.4)
            }
        }
    }

    private func islandScene(_ img: NSImage?, _ head: String, _ cap: String) -> some View {
        let i = scene, lt = local(i)
        let rise = seg(lt, 0.2, 1.4)
        return ZStack {
            if let img {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fit).frame(width: 1500)
                    .shadow(color: .black.opacity(0.6), radius: 50, y: 20)
                    .offset(y: 190 - (1 - rise) * 500 + CGFloat(lt) * 5).scaleEffect(1 + lt * 0.006).opacity(rise)
            }
            VStack(spacing: 22) { title(head, lt, at: 0.5, size: 78); caption(cap, lt, at: 1.4) }.offset(y: -330)
        }.frame(maxHeight: .infinity, alignment: .center)
    }

    private var pets: some View {
        let lt = local(3)
        let pokes: [Double] = [2.6, 3.1, 3.6].map { PromoVideo.cuts[3] + $0 }
        let outfits: [Set<Outfit>] = [[], [.glasses], [.crown], [.bow, .scarf]]
        let o = outfits[min(3, Int(max(0, lt - 0.4) / 1.1))]
        return ZStack {
            HStack(spacing: 160) {
                PromoPet(agent: .claude, t: t, size: 440, outfits: o, pokes: pokes, state: .idle)
                PromoPet(agent: .codex, t: t + 1.3, size: 440, outfits: outfits[min(3, Int(max(0, lt - 0.9) / 1.1))], pokes: pokes, state: .idle)
            }.offset(y: 90).opacity(seg(lt, 0.1, 0.8))
            VStack(spacing: 22) { title("Dos mascotas.\nIguales de vivas.", lt, at: 0.4, size: 78); caption("las mismas expresiones y un guardarropa para cada una", lt, at: 1.2) }.offset(y: -320)
        }
    }

    private var weather: some View {
        let lt = local(4)
        let cases: [(String, Set<Outfit>)] = [("34 °C · calor", [.sunhat, .sunglasses]), ("lluvia", [.umbrella]), ("-2 °C · frío", [.beanie, .scarf, .earmuffs])]
        let i = min(2, Int(lt / 2.0)), (label, o) = cases[i]
        return ZStack {
            HStack(spacing: 140) {
                PromoPet(agent: .claude, t: t, size: 400, outfits: o, pokes: [], state: .idle)
                PromoPet(agent: .codex, t: t + 0.7, size: 400, outfits: o, pokes: [], state: .idle)
            }.offset(y: 90).id(i)
            VStack(spacing: 22) { title("Se visten\ncon el tiempo.", lt, at: 0.3, size: 78); caption(label, lt - Double(i) * 2.0 + 1.0, at: 1.0) }.offset(y: -320)
        }
    }

    private var rage: some View {
        let lt = local(5)
        let size = CGSize(width: 1920, height: 1080)
        let target = CGRect(x: 1020, y: 250, width: 700, height: 520)
        let after = RageChoreography.impactAt + 0.05
        let gone = seg(lt - 0.6, after, after + 0.5)
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 22, style: .continuous).fill(LinearGradient(colors: [Color(hex: 0x23283A), Color(hex: 0x181B27)], startPoint: .top, endPoint: .bottom))
                .overlay(alignment: .topLeading) {
                    HStack(spacing: 8) { ForEach(0..<3, id: \.self) { _ in Circle().fill(Color.white.opacity(0.2)).frame(width: 16, height: 16) } }.padding(22)
                }
                .overlay { VStack(alignment: .leading, spacing: 18) { ForEach(0..<6, id: \.self) { i in RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.07)).frame(width: CGFloat(520 - i * 50), height: 18) } }.offset(x: -30, y: 20) }
                .frame(width: target.width, height: target.height)
                .scaleEffect(1 - 0.85 * gone, anchor: .bottom).offset(x: target.minX, y: target.minY + 330 * gone).opacity(1 - gone)
            RageOverlay(store: PetStore.shared, agent: .claude, start: 0, screen: size, target: target, fixedTime: max(0, lt - 0.6))
            VStack(spacing: 22) { title("Y si las golpeas\nseguido, se enfadan.", lt, at: 0.2, size: 70); caption("nunca cierra nada: solo minimiza la ventana", lt, at: 1.0) }
                .frame(width: 900).offset(x: 60, y: 150)
        }.frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private var companion: some View {
        let lt = local(6)
        return ZStack {
            if let v = assets.visto {
                Image(nsImage: v).resizable().aspectRatio(contentMode: .fit).frame(height: 600).clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .shadow(color: .black.opacity(0.6), radius: 40, y: 20).offset(y: 120).scaleEffect(1 + lt * 0.01).opacity(seg(lt, 0.2, 1.0))
            }
            VStack(spacing: 22) { title("En tu iPhone\ny en tu reloj.", lt, at: 0.3, size: 78); caption("permitir siempre · realidad aumentada · Meta Quest · fuera de casa con tu relay", lt, at: 1.2) }.offset(y: -335)
        }
    }

    private var montage: some View {
        let lt = local(7)
        let items = assets.montage
        let i = min(items.count - 1, Int(lt / 1.35)), local1 = lt - Double(i) * 1.35
        return ZStack {
            if let img = items[safe: i]?.0 {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fit).frame(height: 600).clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: .black.opacity(0.6), radius: 40, y: 20).offset(y: 110 + CGFloat((1 - seg(local1, 0, 0.5)) * 40)).opacity(seg(local1, 0, 0.4)).id(i)
            }
            VStack(spacing: 22) { title("Hecha para\nampliarse.", lt, at: 0.2, size: 74); caption(items[safe: i]?.1 ?? "", local1, at: 0.2) }.offset(y: -335)
            if lt > 5.2 { Text("laboratorio incluido: galaxia · ciudad · radar").font(.system(size: 26, weight: .medium, design: .monospaced)).foregroundColor(ink.opacity(0.7)).offset(y: 440).opacity(seg(lt, 5.2, 5.8)) }
        }
    }

    private var outro: some View {
        let lt = local(8)
        return ZStack {
            HStack(spacing: 60) {
                PromoPet(agent: .claude, t: t, size: 260, outfits: [], pokes: [], state: .done)
                PromoPet(agent: .codex, t: t + 0.5, size: 260, outfits: [], pokes: [], state: .done)
            }.offset(y: -250).opacity(seg(lt, 0.1, 0.9))
            VStack(spacing: 20) {
                Spacer().frame(height: 170)
                title("claude pet.", lt, at: 0.7, size: 140)
                caption("macOS · iPhone · Apple Watch", lt, at: 1.5)
                Text("gratis · código abierto · MIT").font(.system(size: 34, weight: .medium)).foregroundColor(ink.opacity(0.85 * seg(lt, 2.0, 2.6)))
                Text("github.com/kisnner26/claude-pet").font(.system(size: 40, weight: .semibold, design: .monospaced)).foregroundColor(Color(hex: 0xE0824F).opacity(seg(lt, 2.4, 3.0)))
                Text("escenas renderizadas con el código de la propia app").font(.system(size: 18, design: .monospaced)).foregroundColor(ink.opacity(0.4 * seg(lt, 3.2, 3.8))).padding(.top, 30)
            }
        }
    }
}

private extension Array { subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil } }

/// Una mascota animada con el animador de verdad: respira, parpadea, mira, se marea con tres toques y se viste.
@MainActor
struct PromoPet: View {
    let agent: IslandAgentTab
    let t: Double
    let size: CGFloat
    let outfits: Set<Outfit>
    let pokes: [Double]
    let state: PetState

    var body: some View {
        let tick = Int(t * 8)
        var scene = PetScene(idleSeconds: 5, state: state)
        if state == .done { scene.confettiStart = nil }
        let gaze = CGPoint(x: CGFloat(sin(t * 0.7)) * 0.8, y: 0)
        let pose = PetAnimator.pose(at: t, gaze: gaze, pokes: pokes, hopStart: state == .done ? t - (t.truncatingRemainder(dividingBy: 2.4)) : nil, motion: true, scene: scene)
        let particles = PetAnimator.particles(at: t, pose: pose, scene: scene)
        return Group {
            if agent == .claude {
                Canvas { gc, sz in
                    var px = Sprite.pixels(state, tick: tick)
                    px = Wardrobe.compose(px, outfits: outfits, state: state, tick: tick)
                    px = PetAnimator.apply(px, pose: pose)
                    var overlay = gc
                    PetFace.draw(&gc, size: sz, pixels: px, pose: pose)
                    PetFace.draw(&overlay, size: sz, pixels: particles, pose: PetPose())
                }.frame(width: size, height: size)
            } else {
                CodexMiniFrame(face: Self.face(state, pose, tick), legs: tick % 8 < 4 ? .step : .stand, tick: tick, skin: .cloud, wave: pose.earLift, pose: pose, outfits: outfits, particles: particles)
                    .frame(width: size, height: size * 21 / 18)
            }
        }
    }

    static func face(_ state: PetState, _ pose: PetPose, _ tick: Int) -> CodexAvatar.Face {
        if pose.dizzy { return .dizzy(tick / 2) }
        if pose.annoyed { return .annoyed }
        switch state {
        case .done: return .happy
        case .error: return .cross
        default:
            if pose.sleepy || pose.blink { return .closed }
            if pose.yawn || pose.happy { return .happy }
            if pose.wideEyes { return .wide }
            return .prompt(cursor: tick % 2 == 0)
        }
    }
}
