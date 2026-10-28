import Foundation
import Network

/// Lado de claude pet (Mac): escucha en la red local, se anuncia por Bonjour y habla con los dispositivos emparejados.
public final class VistoHost: @unchecked Sendable {
    public struct Peer: Equatable, Sendable { public let id: UUID; public let name: String }

    private let queue = DispatchQueue(label: "visto.host")
    private let listenQueue = DispatchQueue(label: "visto.listener")
    private final class PortBox: @unchecked Sendable { var value: UInt16 = 0 }
    private var listener: NWListener?
    private var channels: [UUID: VistoChannel] = [:]
    private var names: [UUID: String] = [:]
    private var code = ""
    private let hostName: String
    public static let maxPeers = 4

    /// Una respuesta de un dispositivo. Se llama en la cola del anfitrión.
    public var onAnswer: (@Sendable (String, Bool) -> Void)?
    public var onAlways: (@Sendable (String) -> Void)?
    /// Un dispositivo terminó el saludo: es el momento de enviarle lo que ya está pendiente.
    public var onReply: (@Sendable (String, [[Int]]) -> Void)?
    public var onFocus: (@Sendable (Bool) -> Void)?
    public var onPeerReady: (@Sendable (UUID) -> Void)?
    public var onPeersChanged: (@Sendable ([Peer]) -> Void)?
    public private(set) var port: UInt16 = 0
    /// Estado de la conexion con el relay (si hay uno configurado).
    public var onRelayState: (@Sendable (RelayState) -> Void)?
    private var relay: RelayEndpoint?
    private var relayIdle: [UUID: VistoChannel] = [:]
    private var relayFailures = 0
    private var relayState: RelayState = .off { didSet { if relayState != oldValue { onRelayState?(relayState) } } }
    static let relayPool = 2

    public init(hostName: String) { self.hostName = hostName }

    /// `advertise: false` en pruebas, para no publicar nada en la red.
    public func start(code: String, advertise: Bool = true) throws {
        queue.sync { stopLocked(); self.code = code }
        let l = try NWListener(using: .tcp)
        if advertise { l.service = NWListener.Service(name: String(hostName.prefix(60)), type: vistoServiceType) }
        l.newConnectionHandler = { [weak self] conn in self?.queue.async { self?.accept(conn) } }
        let ready = DispatchSemaphore(value: 0)
        let box = PortBox()
        l.stateUpdateHandler = { [weak l] s in
            if case .ready = s { box.value = l?.port?.rawValue ?? 0; ready.signal() }
            if case .failed = s { ready.signal() }
        }
        l.start(queue: listenQueue)      // cola aparte: esperar aqui no puede bloquear los callbacks del listener
        _ = ready.wait(timeout: .now() + 3)
        queue.sync { listener = l; port = box.value }
    }

    public func stop() { queue.sync { stopLocked() } }

    /// Registra la Mac en el relay: mantiene dos conexiones en espera y, cada vez que un movil se une, repone la que se uso.
    public func startRelay(_ endpoint: RelayEndpoint) { queue.async { [self] in relay = endpoint; relayFailures = 0; fillRelayPool() } }

    public func stopRelay() { queue.async { [self] in relay = nil; cancelRelayIdle(); relayState = .off } }

    private func cancelRelayIdle() { let idle = relayIdle.values; relayIdle = [:]; idle.forEach { $0.cancel() } }

    private func fillRelayPool() {
        guard let relay, !code.isEmpty, let port = NWEndpoint.Port(rawValue: relay.port) else { return }
        while relayIdle.count < Self.relayPool {
            let conn = NWConnection(host: NWEndpoint.Host(relay.host), port: port, using: relay.tls ? .tls : .tcp)
            let ch = VistoChannel(connection: conn, code: code, role: .host, preamble: .relayHost(room: Pairing.relayRoom(code: code)))
            let id = ch.id
            ch.onRelayReady = { [weak self] in self?.queue.async { self?.relayFailures = 0; self?.relayState = .ready } }
            ch.onPaired = { [weak self] in self?.queue.async { if let c = self?.relayIdle.removeValue(forKey: id) { self?.adopt(c) }; self?.fillRelayPool() } }
            ch.onClosed = { [weak self] in
                self?.queue.async {
                    guard let self, self.relayIdle.removeValue(forKey: id) != nil else { return }
                    self.relayFailures += 1
                    if self.relayIdle.isEmpty { self.relayState = .failed("no se pudo conectar con el relay") }
                    // reintenta con calma: 2 s, 4 s... hasta 60 s
                    let wait = min(60.0, 2.0 * pow(2.0, Double(min(self.relayFailures, 5) - 1)))
                    self.queue.asyncAfter(deadline: .now() + wait) { self.fillRelayPool() }
                }
            }
            relayIdle[id] = ch
            if relayIdle.count == 1, relayState != .ready { relayState = .connecting }
            ch.start()
        }
    }

    private func stopLocked() {
        cancelRelayIdle()
        listener?.cancel(); listener = nil
        let all = channels.values
        channels = [:]; names = [:]
        for c in all { c.cancel() }
        notifyPeers()
    }

    /// Cambia el código: se desconecta a todos y solo entran los que tengan el nuevo.
    public func rotate(code: String, advertise: Bool = true) throws { try start(code: code, advertise: advertise); queue.async { [self] in relayFailures = 0; fillRelayPool() } }

    public var peers: [Peer] { queue.sync { snapshot() } }
    private func snapshot() -> [Peer] { channels.keys.compactMap { id in names[id].map { Peer(id: id, name: $0) } }.sorted { $0.name < $1.name } }
    private func notifyPeers() { let p = snapshot(); onPeersChanged?(p) }

    public func broadcast(_ m: VistoMessage) { queue.async { [self] in for (id, c) in channels where names[id] != nil { c.send(m) } } }
    public func send(_ m: VistoMessage, to id: UUID) { queue.async { [self] in if names[id] != nil { channels[id]?.send(m) } } }

    private func accept(_ conn: NWConnection) {
        guard channels.count < Self.maxPeers else { conn.cancel(); return }
        let ch = VistoChannel(connection: conn, code: code, role: .host)
        register(ch)
        ch.start()
    }

    /// Un movil se unio por el relay: la conexion ya estaba abierta, solo falta tratarla como a cualquier otra.
    private func adopt(_ ch: VistoChannel) {
        guard channels.count < Self.maxPeers else { ch.cancel(); return }
        register(ch)
    }

    private func register(_ ch: VistoChannel) {
        let id = ch.id
        ch.onMessage = { [weak self] m in self?.queue.async { self?.handle(m, from: id) } }
        ch.onClosed = { [weak self] in self?.queue.async { self?.channels[id] = nil; self?.names[id] = nil; self?.notifyPeers() } }
        channels[id] = ch
        // quien no demuestra tener el código (no descifra su primer mensaje) no llega a figurar: se corta en seco
        queue.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self, self.names[id] == nil, let c = self.channels[id] else { return }
            c.cancel()
        }
    }

    private func handle(_ m: VistoMessage, from id: UUID) {
        switch m {
        case .hello(let device):
            let first = names[id] == nil
            names[id] = String(device.prefix(40))
            channels[id]?.send(.host(name: hostName))
            notifyPeers()
            if first { onPeerReady?(id) }
        case .answer(let askID, let allow):
            guard names[id] != nil else { return }
            onAnswer?(askID, allow)
        case .always(let askID):
            guard names[id] != nil else { return }
            onAlways?(askID)
        case .reply(let qid, let picks):
            guard names[id] != nil, picks.count <= 4, picks.allSatisfy({ $0.count <= 8 }) else { return }
            onReply?(qid, picks)
        case .focus(let on):
            guard names[id] != nil else { return }
            onFocus?(on)
        default: break
        }
    }

    /// Para responder «rechazado» solo a quien preguntó.
    public func reply(_ m: VistoMessage, toAnswerFrom id: UUID) { send(m, to: id) }
}
