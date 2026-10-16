import Foundation

/// Almacén local privado. Las cápsulas son explícitamente creadas por el usuario y nunca viajan por el pet bus.
enum SessionCapsuleStore {
    nonisolated(unsafe) static var directory = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude-pet/handoff")

    static func save(_ capsule: SessionCapsule) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let url = directory.appendingPathComponent("relay-\(capsule.id.uuidString.lowercased()).json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(capsule).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return url
    }

    static func latest(now: Date = Date()) throws -> (capsule: SessionCapsule, url: URL) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw SessionCapsuleError.missing
        }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
            .filter { $0.pathExtension == "json" }
            .sorted { modificationDate($0) > modificationDate($1) }
        for url in files {
            guard let data = try? Data(contentsOf: url), let capsule = decode(data) else { continue }
            guard capsule.version == SessionCapsule.version else { continue }
            if capsule.expiresAt > now { return (capsule, url) }
        }
        throw SessionCapsuleError.missing
    }

    private static func decode(_ data: Data) -> SessionCapsule? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(SessionCapsule.self, from: data)
    }

    private static func modificationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}
