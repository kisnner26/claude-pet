import Foundation
import Network

/// Lado del iPhone y del Watch: busca claude pet por Bonjour, se conecta, se reconecta solo y mantiene la lista de permisos pendientes.
@MainActor
public final class VistoClient: ObservableObject {
    public enum State: Equatable { case idle, searching, connecting, connected(String) }

    @Published public private(set) var state: State = .idle
    @Published public private(set) var asks: [Ask] = []
    @Published public private(set) var plan: PlanSnapshot?
    @Published public private(set) var notice: String?
    @Published public private(set) var detail = ""

    /// Llega un permiso nuevo (para vibrar o avisar).
    public var onNewAsk: ((Ask) -> Void)?
    public var onChange: (() -> Void)?

    private var code: String?
    private var deviceName = "Dispositivo"
    private var running = false
    private var browser: NWBrowser?
    private var channel: VistoChannel?
    private var retry: Task<Void, Never>?
    private var direct: NWEndpoint?
    private var prune: Task<Void, Never>?

    public init() {}

    public var isConnected: Bool { if case .connected = state { return true } else { return false } }
    public var hostName: String? { if case .connected(let n) = state { return n } else { return nil } }

    public func configure(code: String?, deviceName: String) {
        let c = code.flatMap { Pairing.isValid($0) ? Pairing.normalize($0) : nil }
        let changed = c != self.code
        self.code = c; self.deviceName = deviceName
        if changed && running { restart() }
    }

    public func start(direct: NWEndpoint? = nil) {
        self.direct = direct
        guard !running else { return }
        running = true
        restart()
        prune = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                self?.dropExpired()
            }
        }
    }

    public func stop() {
        running = false
        retry?.cancel(); prune?.cancel()
        teardown()
        state = .idle
        asks = []; plan = nil
    }

    public func answer(_ id: String, allow: Bool) {
        let ask = asks.first { $0.id == id }
        channel?.send(.answer(id: id, allow: allow))
        // permitir algo de riesgo alto lo decide la Mac: la tarjeta se queda hasta que conteste
        if !(allow && ask?.canAllow == false) { asks.removeAll { $0.id == id } }
        onChange?()
    }

    private func restart() {
        teardown()
        guard running, let code, Pairing.isValid(code) else { state = .idle; detail = code == nil ? "Falta el código de claude pet" : ""; return }
        state = .searching
        detail = "Buscando claude pet en la red"
        if let direct { connect(to: direct, code: code); return }
        let b = NWBrowser(for: .bonjour(type: vistoServiceType, domain: nil), using: .tcp)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            guard let first = results.first else { return }
            Task { @MainActor in self?.connect(to: first.endpoint, code: code) }
        }
        b.stateUpdateHandler = { [weak self] s in
            if case .failed = s { Task { @MainActor in self?.detail = "No se pudo buscar en la red. Revisa el permiso de red local." } }
        }
        b.start(queue: .main)
        browser = b
        scheduleRetry()
    }

    private func connect(to endpoint: NWEndpoint, code: String) {
        guard channel == nil, running else { return }
        retry?.cancel()
        state = .connecting
        detail = "claude pet encontrado, conectando"
        let ch = VistoChannel(connection: NWConnection(to: endpoint, using: .tcp), code: code, role: .client)
        let name = deviceName
        ch.onReady = { [weak ch] in ch?.send(.hello(device: name)) }
        ch.onMessage = { [weak self] m in Task { @MainActor in self?.handle(m) } }
        ch.onClosed = { [weak self, id = ch.id] in
            Task { @MainActor in
                guard let self, self.channel?.id == id else { return }
                self.channel = nil
                self.state = .idle
                self.asks = []
                self.scheduleRetry(after: 2)
            }
        }
        channel = ch
        ch.start()
        browser?.cancel(); browser = nil
        scheduleRetry(after: 8)       // si el apretón nunca termina (código equivocado), se vuelve a empezar
    }

    private func handle(_ m: VistoMessage) {
        switch m {
        case .host(let name):
            state = .connected(name); detail = "Conectado a \(name)"; retry?.cancel()
        case .ask(let a):
            guard !a.isExpired(), !asks.contains(where: { $0.id == a.id }) else { return }
            asks.append(a)
            if asks.count > 12 { asks.removeFirst(asks.count - 12) }
            onNewAsk?(a); onChange?()
        case .gone(let id):
            asks.removeAll { $0.id == id }; onChange?()
        case .refused(let id, let why):
            notice = why
            if why.contains("pendiente") || why.contains("caduc") { asks.removeAll { $0.id == id } }
            onChange?()
        case .plan(let p):
            plan = p; onChange?()
        case .hello, .answer: break
        }
    }

    private func dropExpired() {
        let before = asks.count
        asks.removeAll { $0.isExpired() }
        if asks.count != before { onChange?() }
    }

    public func clearNotice() { notice = nil }

    private func scheduleRetry(after seconds: Double = 3) {
        retry?.cancel()
        retry = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled, let self, self.running, !self.isConnected else { return }
            self.restart()
        }
    }

    private func teardown() {
        retry?.cancel()
        browser?.cancel(); browser = nil
        let ch = channel
        channel = nil
        ch?.cancel()
    }
}
