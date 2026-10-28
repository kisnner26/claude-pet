import CryptoKit
import Foundation
import Network

/// Canal TCP cifrado y autenticado (ChaCha20-Poly1305). Apretón: el cliente envía 16 bytes aleatorios y el anfitrión otros 16;
/// la clave de la sesión sale del código y de los dos. Trama: [len u32][ciphertext+tag]; el nonce lleva la dirección y un contador
/// que solo sube, de modo que una trama repetida, reordenada o de la otra dirección no descifra.
public final class VistoChannel: @unchecked Sendable {
    public enum Role: UInt8, Sendable { case client = 1, host = 2 }
    /// Saludo previo cuando la conexion pasa por un relay: el relay solo copia bytes y el apreton cifrado va por dentro, sin cambios.
    public enum Preamble: Equatable, Sendable { case none, relayJoin(room: String), relayHost(room: String) }
    static let relayReady = Data("RELAYRDY".utf8), relayPair = Data("RELAYPAR".utf8), relayOK = Data("RELAYOK!".utf8)

    public let id = UUID()
    private let connection: NWConnection
    private let role: Role
    private let code: String
    private let preamble: Preamble
    private let queue = DispatchQueue(label: "visto.channel")
    private var buffer = Data()
    private var myRandom = Data()
    private var key: SymmetricKey?
    private var sendSeq: UInt64 = 0
    private var lastRecvSeq: UInt64 = 0
    private var closed = false

    public var onMessage: (@Sendable (VistoMessage) -> Void)?
    /// Se llama cuando el apretón termina y ya se puede enviar.
    public var onReady: (@Sendable () -> Void)?
    public var onClosed: (@Sendable () -> Void)?
    /// Anfitrion en un relay: la Mac quedo registrada y espera.
    public var onRelayReady: (@Sendable () -> Void)?
    /// Anfitrion en un relay: un movil acaba de unirse a esta conexion.
    public var onPaired: (@Sendable () -> Void)?

    static let maxFrame = 64 * 1024
    static let handshakeLength = 16

    public init(connection: NWConnection, code: String, role: Role, preamble: Preamble = .none) {
        self.connection = connection; self.code = code; self.role = role; self.preamble = preamble
    }

    public func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready: self.begin()
            case .failed, .cancelled: self.finish()
            case .waiting: self.queue.asyncAfter(deadline: .now() + 6) { if case .waiting = self.connection.state { self.finish() } }
            default: break
            }
        }
        connection.start(queue: queue)
    }

    private func begin() {
        switch preamble {
        case .none: handshake()
        case .relayJoin(let room):
            connection.send(content: Data("JOIN \(room)\n".utf8), completion: .contentProcessed { _ in })
            expect(8) { [self] in $0 == Self.relayOK ? handshake() : { connection.cancel(); finish() }() }
        case .relayHost(let room):
            connection.send(content: Data("HOST \(room)\n".utf8), completion: .contentProcessed { _ in })
            expect(8) { [self] first in
                guard first == Self.relayReady else { connection.cancel(); finish(); return }
                onRelayReady?()
                expect(8) { [self] second in
                    guard second == Self.relayPair else { connection.cancel(); finish(); return }
                    onPaired?()
                    handshake()
                }
            }
        }
    }

    /// Lee exactamente `count` bytes; cualquier otra cosa cierra la conexion.
    private func expect(_ count: Int, _ then: @escaping @Sendable (Data) -> Void) {
        connection.receive(minimumIncompleteLength: count, maximumLength: count) { [weak self] data, _, _, error in
            guard let self, !self.closed else { return }
            if let data, data.count == count, error == nil { then(data) } else { self.connection.cancel(); self.finish() }
        }
    }

    private func handshake() {
        var rnd = SystemRandomNumberGenerator()
        myRandom = Data((0..<Self.handshakeLength).map { _ in UInt8.random(in: 0...255, using: &rnd) })
        if role == .client { connection.send(content: myRandom, completion: .contentProcessed { _ in }) }
        receive()
    }

    public func send(_ message: VistoMessage) {
        queue.async { [self] in
            guard !closed, let key else { return }
            sendSeq += 1
            guard let json = try? JSONEncoder().encode(Envelope(seq: sendSeq, message: message)),
                  let sealed = try? ChaChaPoly.seal(json, using: key, nonce: nonce(role, sendSeq)) else { return }
            var frame = Data()
            var len = UInt32(sealed.ciphertext.count + 16).bigEndian
            withUnsafeBytes(of: &len) { frame.append(contentsOf: $0) }
            frame.append(sealed.ciphertext); frame.append(sealed.tag)
            connection.send(content: frame, completion: .contentProcessed { _ in })
        }
    }

    public func cancel() { queue.async { [self] in connection.cancel(); finish() } }

    private func finish() {
        queue.async { [self] in
            guard !closed else { return }
            closed = true
            connection.stateUpdateHandler = nil
            connection.cancel()
            onClosed?()
        }
    }

    private func nonce(_ r: Role, _ seq: UInt64) -> ChaChaPoly.Nonce {
        var d = Data([r.rawValue, 0, 0, 0])
        var s = seq.bigEndian
        withUnsafeBytes(of: &s) { d.append(contentsOf: $0) }
        return (try? ChaChaPoly.Nonce(data: d)) ?? ChaChaPoly.Nonce()
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self, !self.closed else { return }
            if let data, !data.isEmpty {
                self.buffer.append(data)
                if !self.drain() { self.connection.cancel(); self.finish(); return }
            }
            if isComplete || error != nil { self.finish(); return }
            self.receive()
        }
    }

    /// Devuelve false si algo no es válido: se corta la conexión sin responder.
    private func drain() -> Bool {
        if key == nil {
            guard buffer.count >= Self.handshakeLength else { return true }
            let theirs = Data(buffer.prefix(Self.handshakeLength))
            buffer = Data(buffer.dropFirst(Self.handshakeLength))
            if role == .host { connection.send(content: myRandom, completion: .contentProcessed { _ in }) }
            let (c, h) = role == .client ? (myRandom, theirs) : (theirs, myRandom)
            key = Pairing.sessionKey(code: code, clientRandom: c, hostRandom: h)
            onReady?()
        }
        guard let key else { return true }
        let peer: Role = role == .client ? .host : .client
        while buffer.count >= 4 {
            let len = Int(buffer.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) })
            guard len >= 16, len <= Self.maxFrame else { return false }
            guard buffer.count >= 4 + len else { return true }
            let body = Data(buffer.subdata(in: 4..<(4 + len)))
            buffer = Data(buffer.dropFirst(4 + len))
            let seq = lastRecvSeq + 1
            guard let box = try? ChaChaPoly.SealedBox(nonce: nonce(peer, seq), ciphertext: body.dropLast(16), tag: body.suffix(16)),
                  let json = try? ChaChaPoly.open(box, using: key),
                  let env = try? JSONDecoder().decode(Envelope.self, from: json), env.seq == seq else { return false }
            lastRecvSeq = seq
            onMessage?(env.message)
        }
        return true
    }
}
