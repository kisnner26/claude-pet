import SwiftUI
import AppKit
import CoreGraphics

/// Lee los contactos del trackpad con MultitouchSupport (framework privado del sistema, cargado en tiempo de ejecucion:
/// si no esta o cambia, el modo simplemente no se activa) y lleva el cursor al punto equivalente de la pantalla.
/// Un filtro de eventos descarta el movimiento relativo del trackpad mientras hay un dedo apoyado, para que el sistema
/// no pelee con la posicion absoluta. Se apaga solo al cerrar la app: el filtro vive y muere con el proceso.
private typealias MTCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32
private typealias MTCreateList = @convention(c) () -> Unmanaged<CFArray>?
private typealias MTRegister = @convention(c) (UnsafeMutableRawPointer, MTCallback) -> Void
private typealias MTStart = @convention(c) (UnsafeMutableRawPointer, Int32) -> Int32
private typealias MTStop = @convention(c) (UnsafeMutableRawPointer) -> Int32
private typealias MTDimensions = @convention(c) (UnsafeMutableRawPointer, UnsafeMutablePointer<Int32>, UnsafeMutablePointer<Int32>) -> Int32

/// Estado compartido entre los hilos de MultitouchSupport y del filtro de eventos (no son el hilo principal).
private final class TrackpadBridge: @unchecked Sendable {
    static let shared = TrackpadBridge()
    static let marker: Int64 = 0x434C5041          // "CLPA": marca los eventos propios para que el filtro los deje pasar

    private let lock = NSLock()
    private var _active = false, _fingersDown = 0, _buttonDown = false
    private var _margin = 0.04
    private var smoother = TrackpadSmoother()
    private var lastUI = Date.distantPast
    var onFingers: (@Sendable ([TrackpadFinger]) -> Void)?

    var active: Bool { get { lock.lock(); defer { lock.unlock() }; return _active } set { lock.lock(); _active = newValue; if !newValue { smoother.reset() }; lock.unlock() } }
    var margin: Double { get { lock.lock(); defer { lock.unlock() }; return _margin } set { lock.lock(); _margin = newValue; lock.unlock() } }
    var fingersDown: Int { lock.lock(); defer { lock.unlock() }; return _fingersDown }
    var buttonDown: Bool { get { lock.lock(); defer { lock.unlock() }; return _buttonDown } set { lock.lock(); _buttonDown = newValue; lock.unlock() } }

    func handle(_ touches: UnsafePointer<MTTouchRaw>?, count: Int) {
        let fingers = touches.map { TrackpadTouch.fingers(from: $0, count: count) } ?? []
        lock.lock()
        _fingersDown = fingers.count
        let on = _active, m = _margin
        var target: CGPoint?
        if on, let f = TrackpadTouch.pointer(fingers) {
            let p = TrackpadTouch.map(x: f.x, y: f.y, margin: m, in: CGDisplayBounds(CGMainDisplayID()))
            let s = smoother.add(Double(p.x), Double(p.y))
            target = CGPoint(x: s.x, y: s.y)
        } else { smoother.reset() }
        let down = _buttonDown
        let publish = Date().timeIntervalSince(lastUI) > 1.0 / 30.0
        if publish { lastUI = Date() }
        lock.unlock()

        if let t = target {
            let e = CGEvent(mouseEventSource: CGEventSource(stateID: .hidSystemState), mouseType: down ? .leftMouseDragged : .mouseMoved, mouseCursorPosition: t, mouseButton: .left)
            e?.setIntegerValueField(.eventSourceUserData, value: Self.marker)
            e?.post(tap: .cghidEventTap)
        }
        if publish { let cb = onFingers; DispatchQueue.main.async { cb?(fingers) } }
    }
}

private let trackpadCallback: MTCallback = { _, touches, count, _, _ in
    TrackpadBridge.shared.handle(touches.map { UnsafePointer($0.assumingMemoryBound(to: MTTouchRaw.self)) }, count: Int(count))
    return 0
}

private let trackpadEventFilter: CGEventTapCallBack = { _, type, event, _ in
    let bridge = TrackpadBridge.shared
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput { return Unmanaged.passUnretained(event) }
    if event.getIntegerValueField(.eventSourceUserData) == TrackpadBridge.marker { return Unmanaged.passUnretained(event) }
    switch type {
    case .leftMouseDown: bridge.buttonDown = true
    case .leftMouseUp: bridge.buttonDown = false
    case .mouseMoved, .leftMouseDragged:
        // el movimiento relativo del trackpad estorba a la posicion absoluta; el de un raton externo (sin dedos apoyados) pasa
        if bridge.active && bridge.fingersDown > 0 { return nil }
    default: break
    }
    return Unmanaged.passUnretained(event)
}

@MainActor final class TrackpadTouchController: ObservableObject {
    static let shared = TrackpadTouchController()

    @Published var enabled = false { didSet { if enabled != oldValue { apply() } } }
    @Published var margin: Double { didSet { UserDefaults.standard.set(margin, forKey: "claudepet.trackpadtouch.margin"); TrackpadBridge.shared.margin = margin } }
    @Published private(set) var fingers: [TrackpadFinger] = []
    @Published private(set) var status = "apagado"
    @Published private(set) var deviceCount = 0

    private var library: UnsafeMutableRawPointer?
    private var devices: [UnsafeMutableRawPointer] = []
    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?

    private init() {
        let saved = UserDefaults.standard.object(forKey: "claudepet.trackpadtouch.margin") as? Double
        margin = saved ?? 0.04
        TrackpadBridge.shared.margin = margin
        TrackpadBridge.shared.onFingers = { [weak self] f in MainActor.assumeIsolated { self?.fingers = f } }
    }

    var accessibilityGranted: Bool { AXIsProcessTrusted() }

    func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    func toggle() { enabled.toggle() }

    private func apply() {
        if enabled { start() } else { stop() }
    }

    private func start() {
        guard accessibilityGranted else { requestAccessibility(); fail("falta el permiso de accesibilidad"); return }
        guard loadDevices() else { fail("el sistema no ofrece el trackpad a las apps"); return }
        guard installFilter() else { fail("no se pudo filtrar el movimiento del trackpad"); return }
        TrackpadBridge.shared.active = true
        status = "activo"
    }

    private func stop() {
        TrackpadBridge.shared.active = false
        removeFilter()
        status = "apagado"
        fingers = []
    }

    private func fail(_ why: String) {
        status = why
        enabled = false
    }

    // MARK: MultitouchSupport

    private func loadDevices() -> Bool {
        if !devices.isEmpty { return true }
        library = library ?? dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW)
        guard let lib = library,
              let listSym = dlsym(lib, "MTDeviceCreateList"), let regSym = dlsym(lib, "MTRegisterContactFrameCallback"), let startSym = dlsym(lib, "MTDeviceStart") else { return false }
        let createList = unsafeBitCast(listSym, to: MTCreateList.self)
        let register = unsafeBitCast(regSym, to: MTRegister.self)
        let start = unsafeBitCast(startSym, to: MTStart.self)
        let dimensions = dlsym(lib, "MTDeviceGetSensorSurfaceDimensions").map { unsafeBitCast($0, to: MTDimensions.self) }
        guard let array = createList()?.takeRetainedValue() else { return false }
        let n = CFArrayGetCount(array)
        for i in 0..<n {
            guard let raw = CFArrayGetValueAtIndex(array, i) else { continue }
            let device = UnsafeMutableRawPointer(mutating: raw)
            // la Touch Bar tambien es un dispositivo multitactil, pero larguisimo: un trackpad es casi 16:10
            if let dimensions {
                var w: Int32 = 0, h: Int32 = 0
                if dimensions(device, &w, &h) == 0 || (w > 0 && h > 0) { if !TrackpadTouch.isTrackpadShape(width: Double(w), height: Double(h)) { continue } }
            }
            register(device, trackpadCallback)
            _ = start(device, 0)
            devices.append(device)
        }
        deviceCount = devices.count
        return !devices.isEmpty
    }

    // MARK: filtro de eventos

    private func installFilter() -> Bool {
        if tap != nil { return true }
        let mask: CGEventMask = (1 << CGEventType.mouseMoved.rawValue) | (1 << CGEventType.leftMouseDragged.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.leftMouseUp.rawValue)
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask, callback: trackpadEventFilter, userInfo: nil) else { return false }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        tap = port; tapSource = source
        return true
    }

    private func removeFilter() {
        if let port = tap { CGEvent.tapEnable(tap: port, enable: false) }
        if let source = tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; tapSource = nil
    }
}

// MARK: pagina de ajustes

struct TrackpadTouchPanel: View {
    @ObservedObject var controller: TrackpadTouchController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("trackpad táctil").font(.system(size: 17, weight: .bold, design: .monospaced))
                Text("experimental").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundColor(Color(hex: 0xE0824F))
                    .padding(.horizontal, 7).padding(.vertical, 2).overlay(Capsule().stroke(Color(hex: 0xE0824F), lineWidth: 1))
                Spacer()
                Toggle("activar", isOn: $controller.enabled).toggleStyle(.switch)
            }
            Text("el trackpad pasa a ser una superficie absoluta, como una tableta: tocar un punto lleva el cursor al punto equivalente de la pantalla. Con dos dedos sigues desplazando y haciendo zoom como siempre. El clic físico, o tocar para hacer clic si lo tienes activado, funciona donde esté el cursor.")
                .font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)

            Text("fase experimental: lee el trackpad con MultitouchSupport, un framework privado de macOS que Apple puede cambiar en cualquier actualización. Puede fallar o dejar de funcionar sin aviso; si algo se comporta raro, apágalo.")
                .font(.system(size: 10)).foregroundColor(Color(hex: 0xE7B45B)).fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                row("modo", controller.status, ok: controller.status == "activo")
                row("trackpad", controller.deviceCount > 0 ? "\(controller.deviceCount) dispositivo\(controller.deviceCount == 1 ? "" : "s") multitáctil" : "se detecta al activar", ok: controller.deviceCount > 0)
                HStack {
                    row("accesibilidad", controller.accessibilityGranted ? "concedida" : "falta: sin ella no se puede controlar el cursor", ok: controller.accessibilityGranted)
                    if !controller.accessibilityGranted { Button("pedir") { controller.requestAccessibility() }.controlSize(.small) }
                }
            }

            // el trackpad en vivo: cada dedo apoyado es un punto
            GeometryReader { geo in
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(Color.black)
                    RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.18), lineWidth: 1)
                    // la zona util: lo que queda dentro del margen es lo que cubre toda la pantalla
                    let m = CGFloat(controller.margin)
                    Rectangle().stroke(Color(hex: 0xE0824F).opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .frame(width: geo.size.width * (1 - 2 * m), height: geo.size.height * (1 - 2 * m))
                    ForEach(controller.fingers, id: \.id) { f in
                        Circle().fill(Color(hex: 0xE0824F)).frame(width: 18, height: 18)
                            .position(x: geo.size.width * f.x, y: geo.size.height * (1 - f.y))
                    }
                    if controller.fingers.isEmpty {
                        Text(controller.enabled ? "apoya un dedo en el trackpad" : "actívalo para ver tus dedos aquí").font(.system(size: 11, design: .monospaced)).foregroundColor(.white.opacity(0.4))
                    }
                }
            }
            .frame(height: 170).frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 1) {
                HStack { Text("margen de los bordes").font(.system(size: 11, weight: .semibold)); Spacer(); Text("\(Int((controller.margin * 100).rounded())) %").font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary) }
                Slider(value: $controller.margin, in: 0...0.15)
                Text("la franja punteada del trackpad ya cubre toda la pantalla: así llegas a las esquinas sin tocar el borde exacto.").font(.system(size: 10)).foregroundColor(.secondary)
            }
            Text("también se enciende desde la Touch Bar (botón de herramientas) y desde el menú de la barra. Solo funciona con la app abierta: al cerrarla el trackpad vuelve a ser el de siempre.").font(.system(size: 10)).foregroundColor(.secondary)
        }
    }

    private func row(_ title: String, _ value: String, ok: Bool) -> some View {
        HStack(spacing: 8) {
            Circle().fill(ok ? Color(hex: 0x6CCB8A) : Color(hex: 0xE7B45B)).frame(width: 7, height: 7)
            Text(title).font(.system(size: 11, weight: .semibold, design: .monospaced)).frame(width: 96, alignment: .leading)
            Text(value).font(.system(size: 11)).foregroundColor(.secondary)
        }
    }
}
