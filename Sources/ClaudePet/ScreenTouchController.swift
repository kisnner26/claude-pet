import SwiftUI
import AppKit
import AVFoundation
import Vision
import CoreGraphics

enum ScreenTouchMode: String, CaseIterable, Codable, Identifiable {
    case mirror = "espejo", air = "aire"
    var id: String { rawValue }
}

/// La camara: reduce cada fotograma a 160 x 120, le pasa el filtro de piel y busca el dedo y su reflejo (modo espejo)
/// o la mano con Vision (modo aire). No guarda ni envia imagenes: cada fotograma se descarta al procesarlo.
final class ScreenTouchCamera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    struct Config { var mode: ScreenTouchMode = .mirror; var params = TouchParams(); var wantsPreview = false }

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "claudepet.screentouch.camera")
    private let lock = NSLock()
    private var config = Config()
    private var last: TouchReading?
    private var pinchClosed = false
    private var frames = 0
    private var fpsStart = Date()
    private var fps = 0.0
    private var configured = false
    var onFrame: (@Sendable (TouchReading, CGImage?, Double) -> Void)?

    static let width = 160, height = 120

    func update(_ c: Config) { lock.lock(); config = c; lock.unlock() }
    private func current() -> Config { lock.lock(); defer { lock.unlock() }; return config }

    func start() {
        queue.async { [self] in
            if !configured {
                session.beginConfiguration()
                session.sessionPreset = .vga640x480
                guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified) ?? AVCaptureDevice.default(for: .video),
                      let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else { session.commitConfiguration(); return }
                session.addInput(input)
                let out = AVCaptureVideoDataOutput()
                out.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                out.alwaysDiscardsLateVideoFrames = true
                out.setSampleBufferDelegate(self, queue: queue)
                guard session.canAddOutput(out) else { session.commitConfiguration(); return }
                session.addOutput(out)
                session.commitConfiguration()
                configured = true
            }
            if !session.isRunning { last = nil; session.startRunning() }
        }
    }

    func stop() { queue.async { [self] in if session.isRunning { session.stopRunning() } } }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let cfg = current()
        frames += 1
        let now = Date()
        if now.timeIntervalSince(fpsStart) >= 1 { fps = Double(frames) / now.timeIntervalSince(fpsStart); frames = 0; fpsStart = now }

        CVPixelBufferLockBaseAddress(pb, .readOnly)
        let w = Self.width, h = Self.height
        let srcW = CVPixelBufferGetWidth(pb), srcH = CVPixelBufferGetHeight(pb), stride = CVPixelBufferGetBytesPerRow(pb)
        guard let base = CVPixelBufferGetBaseAddress(pb)?.assumingMemoryBound(to: UInt8.self) else { CVPixelBufferUnlockBaseAddress(pb, .readOnly); return }
        var mask = [UInt8](repeating: 0, count: w * h)
        var rgba = cfg.wantsPreview ? [UInt8](repeating: 255, count: w * h * 4) : []
        for y in 0..<h {
            let sy = min(srcH - 1, y * srcH / h)
            for x in 0..<w {
                let sx = min(srcW - 1, x * srcW / w)
                let o = sy * stride + sx * 4
                let b = Int(base[o]), g = Int(base[o + 1]), r = Int(base[o + 2])
                let skin = SkinFilter.isSkin(r: r, g: g, b: b)
                if skin { mask[y * w + x] = 1 }
                if cfg.wantsPreview {
                    let i = (y * w + x) * 4
                    // lo que ve el detector: la piel en naranja y el resto atenuado
                    if skin { rgba[i] = 255; rgba[i + 1] = 150; rgba[i + 2] = 60 } else { let l = UInt8((r + g + b) / 6); rgba[i] = l; rgba[i + 1] = l; rgba[i + 2] = l }
                }
            }
        }
        CVPixelBufferUnlockBaseAddress(pb, .readOnly)

        var reading: TouchReading
        if cfg.mode == .mirror {
            reading = MirrorTouch.read(blobs: BlobFinder.find(mask: mask, width: w, height: h, minArea: cfg.params.minArea), width: w, height: h, params: cfg.params, previous: last)
        } else {
            reading = airReading(pb, previous: last)
        }
        last = reading

        var image: CGImage?
        if cfg.wantsPreview {
            let data = Data(rgba) as CFData
            if let provider = CGDataProvider(data: data) {
                image = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
            }
        }
        let callback = onFrame, f = fps
        DispatchQueue.main.async { callback?(reading, image, f) }
    }

    /// Modo aire: la punta del indice es el cursor y pellizcar con el pulgar es el clic.
    private var airSkip = false
    private func airReading(_ pb: CVPixelBuffer, previous: TouchReading?) -> TouchReading {
        airSkip.toggle()
        if airSkip, let p = previous { return p }          // la deteccion de mano cuesta: una de cada dos
        let request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = 1
        try? VNImageRequestHandler(cvPixelBuffer: pb, orientation: .up, options: [:]).perform([request])
        guard let hand = request.results?.first,
              let index = try? hand.recognizedPoint(.indexTip), let thumb = try? hand.recognizedPoint(.thumbTip),
              let wrist = try? hand.recognizedPoint(.wrist), let mid = try? hand.recognizedPoint(.middleMCP),
              index.confidence > 0.3, thumb.confidence > 0.3, wrist.confidence > 0.3, mid.confidence > 0.3 else { pinchClosed = false; return TouchReading() }
        func pt(_ p: VNRecognizedPoint) -> CGPoint { CGPoint(x: p.location.x, y: 1 - p.location.y) }
        let ratio = Pinch.ratio(thumb: pt(thumb), index: pt(index), wrist: pt(wrist), middleBase: pt(mid))
        pinchClosed = Pinch.closed(ratio: ratio, wasClosed: pinchClosed)
        return TouchReading(phase: pinchClosed ? .touch : .hover, x: pt(index).x, y: pt(index).y, gap: ratio, blobs: [])
    }
}

// MARK: controlador

@MainActor final class ScreenTouchController: ObservableObject {
    static let shared = ScreenTouchController()

    struct Calibrating: Equatable {
        var step = 0
        var hold = 0
        var needsRelease = true
        var releasedFrames = 0
        var accX = 0.0, accY = 0.0
        var cam: [[Double]] = []
        var message = "toca el punto con el dedo"
        var done = false
    }
    static let holdFrames = 10

    private let defaults = UserDefaults.standard
    private let camera = ScreenTouchCamera()
    private var smoother = PointSmoother()
    private var debouncer = TouchDebouncer()
    private var screenBounds: CGRect { CGDisplayBounds(CGMainDisplayID()) }

    @Published var enabled: Bool { didSet { defaults.set(enabled, forKey: "claudepet.screentouch.enabled"); apply() } }
    @Published var mode: ScreenTouchMode { didSet { defaults.set(mode.rawValue, forKey: "claudepet.screentouch.mode"); syncConfig(); resetTracking() } }
    @Published var params: TouchParams { didSet { if let d = try? JSONEncoder().encode(params) { defaults.set(d, forKey: "claudepet.screentouch.params") }; syncConfig() } }
    @Published var hoverMovesCursor: Bool { didSet { defaults.set(hoverMovesCursor, forKey: "claudepet.screentouch.hover") } }
    @Published private(set) var homography: Homography?
    @Published private(set) var calibrationError: Double?
    @Published private(set) var reading = TouchReading()
    @Published private(set) var preview: CGImage?
    @Published private(set) var fps = 0.0
    @Published private(set) var cameraStatus = "apagada"
    @Published private(set) var calibration: Calibrating?
    var previewWanted = false { didSet { syncConfig() } }
    private var calibrationWindow: NSWindow?

    private init() {
        enabled = defaults.bool(forKey: "claudepet.screentouch.enabled")
        mode = ScreenTouchMode(rawValue: defaults.string(forKey: "claudepet.screentouch.mode") ?? "") ?? .mirror
        params = defaults.data(forKey: "claudepet.screentouch.params").flatMap { try? JSONDecoder().decode(TouchParams.self, from: $0) } ?? TouchParams()
        hoverMovesCursor = defaults.object(forKey: "claudepet.screentouch.hover") as? Bool ?? true
        homography = defaults.data(forKey: "claudepet.screentouch.homography").flatMap { try? JSONDecoder().decode(Homography.self, from: $0) }
        calibrationError = defaults.object(forKey: "claudepet.screentouch.error") as? Double
        camera.onFrame = { [weak self] r, image, fps in MainActor.assumeIsolated { self?.handle(r, image: image, fps: fps) } }
    }

    var accessibilityGranted: Bool { AXIsProcessTrusted() }
    var calibrated: Bool { homography != nil }

    func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    func startIfEnabled() { if enabled { apply() } }

    private func syncConfig() { camera.update(.init(mode: mode, params: params, wantsPreview: previewWanted)) }
    private func resetTracking() { smoother.reset(); debouncer = TouchDebouncer(); releaseIfPressed() }

    private func apply() {
        guard enabled else { camera.stop(); cameraStatus = "apagada"; releaseIfPressed(); preview = nil; return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: startCamera()
        case .notDetermined:
            cameraStatus = "pidiendo permiso…"
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { MainActor.assumeIsolated { granted ? self.startCamera() : self.denied() } }
            }
        default: denied()
        }
    }

    private func startCamera() { syncConfig(); camera.start(); cameraStatus = "encendida" }
    private func denied() { cameraStatus = "sin permiso: Ajustes del Sistema > Privacidad > Cámara"; enabled = false }

    // MARK: fotogramas

    private func handle(_ r: TouchReading, image: CGImage?, fps: Double) {
        reading = r; self.fps = fps
        if previewWanted { preview = image }
        if calibration != nil { calibrationFeed(r); return }
        guard enabled, let hg = homography, accessibilityGranted else { return }
        inject(r, hg)
    }

    private func inject(_ r: TouchReading, _ hg: Homography) {
        let b = screenBounds
        if r.phase == .none && !debouncer.pressed { smoother.reset() }
        let mapped = hg.apply(r.x, r.y)
        let sp = r.phase == .none ? (x: smoother.x, y: smoother.y) : smoother.add(mapped.x, mapped.y)
        let p = CGPoint(x: min(b.maxX - 1, max(b.minX, sp.x)), y: min(b.maxY - 1, max(b.minY, sp.y)))
        switch debouncer.feed(r.phase == .touch) {
        case .pressed: post(.leftMouseDown, p)
        case .released: post(.leftMouseUp, p)
        case .none:
            if debouncer.pressed { if r.phase != .none { post(.leftMouseDragged, p) } }
            else if r.phase == .hover && hoverMovesCursor { post(.mouseMoved, p) }
        }
    }

    private func post(_ type: CGEventType, _ p: CGPoint) {
        CGEvent(mouseEventSource: CGEventSource(stateID: .hidSystemState), mouseType: type, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
    }

    private func releaseIfPressed() {
        if debouncer.pressed { post(.leftMouseUp, CGPoint(x: smoother.x, y: smoother.y)) }
        debouncer = TouchDebouncer()
    }

    // MARK: calibracion

    func startCalibration() {
        guard enabled else { enabled = true; DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.startCalibration() }; return }
        releaseIfPressed()
        calibration = Calibrating()
        showCalibrationWindow()
    }

    func cancelCalibration() { calibration = nil; calibrationWindow?.orderOut(nil); calibrationWindow = nil }

    func forgetCalibration() {
        homography = nil; calibrationError = nil
        defaults.removeObject(forKey: "claudepet.screentouch.homography"); defaults.removeObject(forKey: "claudepet.screentouch.error")
    }

    private func calibrationFeed(_ r: TouchReading) {
        guard var c = calibration, !c.done else { return }
        if c.needsRelease {
            // hay que levantar el dedo entre punto y punto para no registrar dos veces el mismo toque
            c.releasedFrames = r.phase == .touch ? 0 : c.releasedFrames + 1
            if c.releasedFrames >= 6 { c.needsRelease = false }
            calibration = c; return
        }
        if r.phase == .touch {
            c.hold += 1; c.accX += r.x; c.accY += r.y
            if c.hold >= Self.holdFrames {
                c.cam.append([c.accX / Double(c.hold), c.accY / Double(c.hold)])
                c.step += 1; c.hold = 0; c.accX = 0; c.accY = 0; c.needsRelease = true; c.releasedFrames = 0
                if c.step >= ScreenTouchCalibration.targets.count { calibration = c; finishCalibration(); return }
            }
        } else {
            c.hold = 0; c.accX = 0; c.accY = 0
        }
        calibration = c
    }

    private func finishCalibration() {
        guard var c = calibration else { return }
        let screen = ScreenTouchCalibration.screenPoints(in: screenBounds)
        let cam = c.cam.map { ($0[0], $0[1]) }
        if let hg = Homography.fit(from: cam, to: screen) {
            let err = hg.meanError(from: cam, to: screen)
            homography = hg; calibrationError = err
            if let d = try? JSONEncoder().encode(hg) { defaults.set(d, forKey: "claudepet.screentouch.homography") }
            defaults.set(err, forKey: "claudepet.screentouch.error")
            c.message = err < 25 ? "calibrada: error medio de \(Int(err.rounded())) px" : "calibrada, pero con \(Int(err.rounded())) px de error: repite con mejor luz"
        } else {
            c.message = "no se pudo calibrar: los puntos quedaron alineados, repite"
        }
        c.done = true
        calibration = c
        smoother.reset()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in self?.cancelCalibration() }
    }

    private final class CalibrationWindow: NSWindow {
        var onEscape: (() -> Void)?
        override var canBecomeKey: Bool { true }
        override func keyDown(with event: NSEvent) { if event.keyCode == 53 { onEscape?() } else { super.keyDown(with: event) } }
    }

    private func showCalibrationWindow() {
        let frame = NSScreen.main?.frame ?? .zero
        let w = CalibrationWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        w.level = .screenSaver
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        w.onEscape = { [weak self] in self?.cancelCalibration() }
        w.contentView = NSHostingView(rootView: ScreenTouchCalibrationView(controller: self))
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        calibrationWindow = w
    }
}

private struct ScreenTouchCalibrationView: View {
    @ObservedObject var controller: ScreenTouchController

    var body: some View {
        GeometryReader { geo in
            let c = controller.calibration
            let step = min(c?.step ?? 0, ScreenTouchCalibration.targets.count - 1)
            let t = ScreenTouchCalibration.targets[step]
            let pos = CGPoint(x: t.0 * geo.size.width, y: t.1 * geo.size.height)
            let progress = Double(c?.hold ?? 0) / Double(ScreenTouchController.holdFrames)
            ZStack {
                Color.black.opacity(0.72)
                if c?.done != true {
                    Circle().stroke(Color.white.opacity(0.25), lineWidth: 2).frame(width: 64, height: 64).position(pos)
                    Circle().trim(from: 0, to: progress).stroke(Color(hex: 0xE0824F), style: StrokeStyle(lineWidth: 4, lineCap: .round)).rotationEffect(.degrees(-90)).frame(width: 64, height: 64).position(pos)
                    Circle().fill(Color(hex: 0xE0824F)).frame(width: 14, height: 14).position(pos)
                }
                VStack(spacing: 6) {
                    Text(c?.done == true ? (c?.message ?? "") : "punto \(step + 1) de \(ScreenTouchCalibration.targets.count)").font(.system(size: 22, weight: .bold, design: .monospaced)).foregroundColor(.white)
                    Text(c?.done == true ? "" : (controller.mode == .mirror ? "toca el punto con la yema y mantén 1 segundo · esc cancela" : "pellizca sobre el punto y mantén 1 segundo · esc cancela")).font(.system(size: 13, design: .monospaced)).foregroundColor(.white.opacity(0.7))
                    if c?.done != true { Text(controller.reading.phase == .none ? "no veo el dedo" : controller.reading.phase == .hover ? "flotando: acércalo más" : "tocando").font(.system(size: 12, design: .monospaced)).foregroundColor(controller.reading.phase == .touch ? Color(hex: 0x6CCB8A) : .white.opacity(0.5)) }
                }
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
        }
    }
}

// MARK: ventana de control

@MainActor enum ScreenTouchWindow {
    private static var window: NSWindow?

    static func show() {
        if let w = window { w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 640), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        w.title = "pantalla táctil"
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: ScreenTouchPanel(controller: .shared))
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = w
    }
}

struct ScreenTouchPanel: View {
    @ObservedObject var controller: ScreenTouchController
    /// Dentro de la ventana de ajustes ocupa el ancho disponible y no lleva marco propio.
    var embedded = false

    private var steps: String {
        controller.mode == .mirror
        ? "1. pega un espejito pequeño, inclinado, delante de la cámara: así ve la pantalla de lado.\\n2. en la vista previa debes ver tu dedo y su reflejo como dos manchas naranjas.\\n3. calibra tocando nueve puntos y listo."
        : "sin espejo: la cámara sigue tu mano. La punta del índice mueve el cursor y pellizcar con el pulgar hace clic.\\ncalibra pellizcando nueve puntos."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("pantalla táctil").font(.system(size: 17, weight: .bold, design: .monospaced))
                Spacer()
                Toggle("activar", isOn: $controller.enabled).toggleStyle(.switch)
            }
            Picker("modo", selection: $controller.mode) { ForEach(ScreenTouchMode.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
            Text(steps.replacingOccurrences(of: "\\n", with: "\n")).font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                row("cámara", controller.cameraStatus + (controller.enabled ? String(format: " · %.0f fps", controller.fps) : ""), ok: controller.cameraStatus == "encendida")
                HStack {
                    row("accesibilidad", controller.accessibilityGranted ? "concedida" : "falta: sin ella no se puede mover el cursor", ok: controller.accessibilityGranted)
                    if !controller.accessibilityGranted { Button("pedir") { controller.requestAccessibility() }.controlSize(.small) }
                }
                row("calibración", controller.calibrationError.map { "error medio \(Int($0.rounded())) px" } ?? "sin calibrar", ok: controller.calibrated)
            }

            ScreenTouchPreview(controller: controller)
                .frame(height: 240).frame(maxWidth: .infinity)
                .background(Color.black).clipShape(RoundedRectangle(cornerRadius: 10))
                .onAppear { controller.previewWanted = true }
                .onDisappear { controller.previewWanted = false }

            if controller.mode == .mirror {
                slider("distancia de toque", value: $controller.params.touchGap, range: 0...8, hint: "cuánto pueden separarse el dedo y su reflejo y seguir contando como toque")
                slider("distancia de flotar", value: $controller.params.hoverGap, range: 4...30, hint: "hasta aquí el dedo solo mueve el cursor")
            }
            Toggle("mover el cursor al flotar", isOn: $controller.hoverMovesCursor).font(.system(size: 12))
            HStack {
                Button("calibrar", action: controller.startCalibration).buttonStyle(.borderedProminent)
                Button("olvidar calibración", action: controller.forgetCalibration).disabled(!controller.calibrated)
                Spacer()
            }
            Text("experimental: no guarda ni envía imágenes; cada fotograma se descarta al procesarlo.").font(.system(size: 10)).foregroundColor(.secondary)
        }
        .padding(embedded ? 0 : 18)
        .frame(width: embedded ? nil : 520)
    }

    private func row(_ title: String, _ value: String, ok: Bool) -> some View {
        HStack(spacing: 8) {
            Circle().fill(ok ? Color(hex: 0x6CCB8A) : Color(hex: 0xE7B45B)).frame(width: 7, height: 7)
            Text(title).font(.system(size: 11, weight: .semibold, design: .monospaced)).frame(width: 96, alignment: .leading)
            Text(value).font(.system(size: 11)).foregroundColor(.secondary)
        }
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack { Text(title).font(.system(size: 11, weight: .semibold)); Spacer(); Text(String(format: "%.1f px", value.wrappedValue)).font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary) }
            Slider(value: value, in: range)
            Text(hint).font(.system(size: 10)).foregroundColor(.secondary)
        }
    }
}

/// Lo que ve el detector: la piel en naranja, las dos manchas encuadradas, el punto del toque y el estado.
private struct ScreenTouchPreview: View {
    @ObservedObject var controller: ScreenTouchController

    var body: some View {
        GeometryReader { geo in
            let sx = geo.size.width / CGFloat(ScreenTouchCamera.width), sy = geo.size.height / CGFloat(ScreenTouchCamera.height)
            let r = controller.reading
            ZStack(alignment: .topLeading) {
                if let img = controller.preview {
                    Image(decorative: img, scale: 1).interpolation(.none).resizable().frame(width: geo.size.width, height: geo.size.height)
                } else {
                    Text(controller.enabled ? "esperando imagen…" : "activa la pantalla táctil para ver la cámara").font(.system(size: 11, design: .monospaced)).foregroundColor(.white.opacity(0.4))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Canvas { gc, _ in
                    for b in r.blobs {
                        gc.stroke(Path(CGRect(x: CGFloat(b.minX) * sx, y: CGFloat(b.minY) * sy, width: CGFloat(b.width) * sx, height: CGFloat(b.height) * sy)), with: .color(.green), lineWidth: 1.5)
                    }
                    if r.phase != .none {
                        let c = r.phase == .touch ? Color.red : Color.yellow
                        gc.fill(Path(ellipseIn: CGRect(x: r.x * geo.size.width - 6, y: r.y * geo.size.height - 6, width: 12, height: 12)), with: .color(c))
                    }
                }
                Text(controller.mode == .mirror ? "\(r.phase.label) · hueco \(String(format: "%.0f", r.gap)) px · \(r.blobs.count) manchas" : "\(r.phase.label) · pellizco \(String(format: "%.2f", r.gap))")
                    .font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(.white).padding(5).background(Color.black.opacity(0.55)).padding(6)
            }
        }
    }
}

extension IslandSnapshot {
    /// `ClaudePet --snapshot-screentouch <ruta.png>`: el panel de control con una lectura de ejemplo.
    static func screenTouch(to path: String) {
        let view = ScreenTouchPanel(controller: .shared).background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, .dark)
        let r = ImageRenderer(content: view)
        r.scale = 2
        guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }
}
