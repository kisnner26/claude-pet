import Network
import XCTest
@testable import VistoCore

/// Pruebas del relay con el servidor real de `relay/relay.js` (hace falta node 20+; si no esta, se omiten).
@MainActor
final class RelayTests: XCTestCase {
    private var process: Process?

    private static var node: String? {
        ["/opt/homebrew/bin/node", "/usr/local/bin/node", "/usr/bin/node"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func relayScript() -> String? {
        // companion/VistoCore/Tests/VistoCoreTests/RelayTests.swift -> raiz del repo de claude pet
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        let path = url.appendingPathComponent("relay/relay.js").path
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    private func startRelay() throws -> UInt16 {
        let node = try XCTUnwrap(Self.node), script = try XCTUnwrap(relayScript())
        let port = UInt16(30_000 + Int.random(in: 0..<8_000))
        let p = Process()
        p.executableURL = URL(fileURLWithPath: node); p.arguments = [script, "--port", String(port), "--host", "127.0.0.1"]
        p.standardOutput = Pipe(); p.standardError = FileHandle.nullDevice
        try p.run(); process = p
        Thread.sleep(forTimeInterval: 0.6)
        return port
    }

    override func tearDown() { process?.terminate(); process = nil }

    private func wait(_ what: String, timeout: Double = 8, _ cond: @escaping @MainActor () -> Bool) async {
        let end = Date().addingTimeInterval(timeout)
        while !cond(), Date() < end { try? await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertTrue(cond(), what)
    }

    func testRelayEndpointParsing() {
        XCTAssertEqual(RelayEndpoint.parse("mi.servidor.com:7777", tls: false), RelayEndpoint(host: "mi.servidor.com", port: 7777, tls: false))
        XCTAssertEqual(RelayEndpoint.parse("MiServidor.com", tls: true), RelayEndpoint(host: "miservidor.com", port: 443, tls: true))
        XCTAssertEqual(RelayEndpoint.parse("relay.example", tls: false)?.port, 7777)
        for bad in ["", "   ", "http://x.com", "x.com/ruta", "usuario@x.com", "x.com:0", "x.com:99999", "x y", "x.com:", "-x.com", String(repeating: "a", count: 300)] {
            XCTAssertNil(RelayEndpoint.parse(bad, tls: false), bad)
        }
    }

    func testRelayRoomHidesTheCode() {
        let code = "ABCDEFGHJKMN"
        let room = Pairing.relayRoom(code: code)
        XCTAssertEqual(room.count, 32)
        XCTAssertTrue(room.allSatisfy { "0123456789abcdef".contains($0) })
        XCTAssertEqual(room, Pairing.relayRoom(code: "abcd-efgh-jkmn"), "da igual como se escriba el codigo")
        XCTAssertNotEqual(room, Pairing.relayRoom(code: "ABCDEFGHJKMP"))
        XCTAssertFalse(room.contains(code.lowercased()))
    }

    func testPhoneReachesMacThroughTheRelay() async throws {
        guard Self.node != nil, relayScript() != nil else { throw XCTSkip("node o relay/relay.js no disponibles") }
        let port = try startRelay()
        let endpoint = RelayEndpoint(host: "127.0.0.1", port: port, tls: false)
        let code = Pairing.newCode()

        let host = VistoHost(hostName: "Mac de prueba")
        nonisolated(unsafe) var states: [RelayState] = []
        host.onRelayState = { states.append($0) }
        try host.start(code: code, advertise: false)
        host.startRelay(endpoint)

        let answered = expectation(description: "respuesta por el relay")
        nonisolated(unsafe) var got: (String, Bool)?
        host.onAnswer = { id, allow in got = (id, allow); answered.fulfill() }
        host.onPeerReady = { [weak host] id in host?.send(.ask(Ask(id: "r1", tool: "Bash", project: "p", detail: "swift build", risk: "medio", expires: Date().addingTimeInterval(60))), to: id) }

        let client = VistoClient()
        client.relayFallbackDelay = 0.2; client.searchesLocalNetwork = false
        client.configure(code: code, deviceName: "iPhone de prueba", relay: endpoint)
        client.start()                                           // sin Bonjour de por medio: la Mac anunciada no existe (advertise: false)
        defer { client.stop(); host.stop(); host.stopRelay() }

        await wait("el movil conecta por el relay") { client.isConnected }
        XCTAssertEqual(client.hostName, "Mac de prueba")
        await wait("llega el permiso pendiente") { client.asks.map(\.id) == ["r1"] }
        client.answer("r1", allow: true)
        await fulfillment(of: [answered], timeout: 5)
        XCTAssertEqual(got?.0, "r1"); XCTAssertEqual(got?.1, true)
        XCTAssertTrue(states.contains(.ready), "la Mac se registro en el relay")
        // al irse un movil se repone la conexion en espera: otro movil puede entrar despues
        client.stop()
        let second = VistoClient()
        second.relayFallbackDelay = 0.2; second.searchesLocalNetwork = false
        second.configure(code: code, deviceName: "iPad de prueba", relay: endpoint)
        second.start()
        defer { second.stop() }
        await wait("un segundo movil entra despues del primero") { second.isConnected }
    }

    func testWrongCodeOrNoMacNeverConnectsThroughTheRelay() async throws {
        guard Self.node != nil, relayScript() != nil else { throw XCTSkip("node o relay/relay.js no disponibles") }
        let port = try startRelay()
        let endpoint = RelayEndpoint(host: "127.0.0.1", port: port, tls: false)
        let host = VistoHost(hostName: "Mac de prueba")
        try host.start(code: Pairing.newCode(), advertise: false)
        host.startRelay(endpoint)
        defer { host.stop(); host.stopRelay() }
        try await Task.sleep(nanoseconds: 600_000_000)

        let stranger = VistoClient()
        stranger.relayFallbackDelay = 0.2; stranger.searchesLocalNetwork = false
        stranger.configure(code: Pairing.newCode(), deviceName: "intruso", relay: endpoint)
        stranger.start()
        defer { stranger.stop() }
        try await Task.sleep(nanoseconds: 1_500_000_000)
        XCTAssertFalse(stranger.isConnected, "otro codigo cae en otra sala: no hay Mac esperando")
        XCTAssertTrue(stranger.detail.contains("relay"), stranger.detail)
        XCTAssertTrue(host.peers.isEmpty)
    }

    func testHostReportsAnUnreachableRelay() async throws {
        let host = VistoHost(hostName: "Mac de prueba")
        nonisolated(unsafe) var last: RelayState = .off
        host.onRelayState = { last = $0 }
        try host.start(code: Pairing.newCode(), advertise: false)
        host.startRelay(RelayEndpoint(host: "127.0.0.1", port: 9, tls: false))       // nadie escucha en el puerto 9
        defer { host.stop(); host.stopRelay() }
        for _ in 0..<60 { if case .failed = last { break }; try await Task.sleep(nanoseconds: 100_000_000) }
        if case .failed = last { } else { XCTFail("deberia fallar: \(last)") }
        host.stopRelay()
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(last, .off)
    }
}
