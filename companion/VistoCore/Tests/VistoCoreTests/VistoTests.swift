import Network
import XCTest
@testable import VistoCore

@MainActor
final class VistoTests: XCTestCase {
    private func pair(code: String, clientCode: String? = nil) throws -> (VistoHost, VistoClient) {
        let host = VistoHost(hostName: "Mac de prueba")
        try host.start(code: code, advertise: false)
        XCTAssertGreaterThan(host.port, 0)
        let client = VistoClient()
        client.configure(code: clientCode ?? code, deviceName: "iPhone de prueba")
        client.start(direct: .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: host.port)!))
        return (host, client)
    }

    private func wait(_ what: String, timeout: Double = 5, _ cond: @escaping @MainActor () -> Bool) async {
        let end = Date().addingTimeInterval(timeout)
        while !cond(), Date() < end { try? await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertTrue(cond(), what)
    }

    func testPairingCode() {
        let c = Pairing.newCode()
        XCTAssertTrue(Pairing.isValid(c)); XCTAssertEqual(c.count, 12)
        XCTAssertEqual(Pairing.normalize(Pairing.display(c)), c)
        XCTAssertFalse(Pairing.isValid("ABC")); XCTAssertFalse(Pairing.isValid("0OIL1" + String(repeating: "A", count: 3)))
        XCTAssertEqual(Pairing.display(c).filter { $0 == "-" }.count, 2)
    }

    func testSessionKeysDifferPerConnection() {
        let c = Pairing.newCode()
        let a = Pairing.sessionKey(code: c, clientRandom: Data(repeating: 1, count: 16), hostRandom: Data(repeating: 2, count: 16))
        let b = Pairing.sessionKey(code: c, clientRandom: Data(repeating: 3, count: 16), hostRandom: Data(repeating: 2, count: 16))
        let d = Pairing.sessionKey(code: Pairing.newCode(), clientRandom: Data(repeating: 1, count: 16), hostRandom: Data(repeating: 2, count: 16))
        XCTAssertNotEqual(a, b); XCTAssertNotEqual(a, d)
    }

    func testAskAnswerRoundTrip() async throws {
        let code = Pairing.newCode()
        let (host, client) = try pair(code: code)
        defer { client.stop(); host.stop() }
        let answered = expectation(description: "answer")
        nonisolated(unsafe) var got: (String, Bool)?
        host.onAnswer = { id, allow in got = (id, allow); answered.fulfill() }
        host.onPeerReady = { [weak host] id in host?.send(.ask(Ask(id: "viejo", tool: "Read", project: "p", detail: "a.txt", risk: "bajo", expires: Date().addingTimeInterval(60))), to: id) }
        await wait("conecta") { client.isConnected }
        XCTAssertEqual(client.hostName, "Mac de prueba")
        await wait("recibe el pendiente de antes de conectar") { client.asks.map(\.id) == ["viejo"] }
        host.broadcast(.ask(Ask(id: "nuevo", tool: "Bash", project: "p", detail: "swift build \"x\"\nfin", risk: "medio", expires: Date().addingTimeInterval(60))))
        await wait("recibe el nuevo con comillas y salto de línea") { client.asks.map(\.id) == ["viejo", "nuevo"] && client.asks[1].detail == "swift build \"x\"\nfin" }
        client.answer("nuevo", allow: true)
        await fulfillment(of: [answered], timeout: 3)
        XCTAssertEqual(got?.0, "nuevo"); XCTAssertEqual(got?.1, true)
        XCTAssertEqual(client.asks.map(\.id), ["viejo"])
        host.broadcast(.gone(id: "viejo"))
        await wait("gone retira") { client.asks.isEmpty }
        host.broadcast(.plan(PlanSnapshot(five: PlanWindow(usedPercent: 40, resetsAt: nil), week: nil)))
        await wait("plan") { client.plan?.five?.remaining() == 60 }
        host.broadcast(.ask(Ask(id: "caducado", tool: "Bash", project: "p", detail: "x", risk: "bajo", expires: Date().addingTimeInterval(-5))))
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(client.asks.isEmpty, "un permiso caducado no se muestra")
    }

    func testWrongCodeNeverConnects() async throws {
        let (host, client) = try pair(code: Pairing.newCode(), clientCode: Pairing.newCode())
        defer { client.stop(); host.stop() }
        let leaked = expectation(description: "no debe llegar"); leaked.isInverted = true
        host.onAnswer = { _, _ in leaked.fulfill() }
        client.answer("x", allow: true)
        try await Task.sleep(nanoseconds: 1_500_000_000)
        XCTAssertFalse(client.isConnected)
        XCTAssertTrue(host.peers.isEmpty)
        await fulfillment(of: [leaked], timeout: 0.5)
    }

    func testRotateCutsOldDevices() async throws {
        let code = Pairing.newCode()
        let (host, client) = try pair(code: code)
        defer { client.stop(); host.stop() }
        await wait("conecta") { client.isConnected }
        XCTAssertEqual(host.peers.map(\.name), ["iPhone de prueba"])
        try host.rotate(code: Pairing.newCode(), advertise: false)
        await wait("se corta al cambiar el código") { !client.isConnected }
        XCTAssertTrue(host.peers.isEmpty)
    }

    func testGarbageIsDropped() async throws {
        let host = VistoHost(hostName: "Mac")
        try host.start(code: Pairing.newCode(), advertise: false)
        defer { host.stop() }
        let conn = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: host.port)!, using: .tcp)
        let closed = expectation(description: "cerrada"); closed.assertForOverFulfill = false
        conn.stateUpdateHandler = { s in
            if case .ready = s { conn.send(content: Data(repeating: 0xFF, count: 400), completion: .contentProcessed { _ in }) }
            if case .failed = s { closed.fulfill() }
            if case .cancelled = s { closed.fulfill() }
        }
        conn.start(queue: .global())
        func drain() { conn.receive(minimumIncompleteLength: 1, maximumLength: 64) { _, _, complete, err in if complete || err != nil { closed.fulfill() } else { drain() } } }
        drain()
        await fulfillment(of: [closed], timeout: 4)
        XCTAssertTrue(host.peers.isEmpty)
        conn.cancel()
    }

    func testAskModel() {
        XCTAssertFalse(Ask(id: "a", tool: "Bash", project: "p", detail: "rm -rf x", risk: "alto", expires: Date().addingTimeInterval(9)).canAllow)
        XCTAssertTrue(Ask(id: "a", tool: "Bash", project: "p", detail: "ls", risk: "medio", expires: Date().addingTimeInterval(9)).canAllow)
        XCTAssertEqual(PlanWindow(usedPercent: 99, resetsAt: Date().addingTimeInterval(-1)).remaining(), 100)
        XCTAssertEqual(PlanWindow(usedPercent: 250, resetsAt: nil).remaining(), 0)
    }
}
