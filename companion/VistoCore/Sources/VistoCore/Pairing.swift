import CommonCrypto
import CryptoKit
import Foundation

/// Código de emparejamiento de 12 caracteres (~58 bits). De él sale la clave del canal: sin el código no se puede ni
/// abrir una conexión ni leer lo que viaja. No hay cuentas ni servidor: el código se muestra en claude pet y se escribe una vez en el móvil.
public enum Pairing {
    static let alphabet = Array("ABCDEFGHJKMNPQRSTVWXYZ23456789")

    public static func newCode() -> String {
        var g = SystemRandomNumberGenerator()
        return String((0..<12).map { _ in alphabet[Int.random(in: 0..<alphabet.count, using: &g)] })
    }

    public static func normalize(_ raw: String) -> String { String(raw.uppercased().filter { alphabet.contains($0) }) }
    public static func isValid(_ raw: String) -> Bool { normalize(raw).count == 12 }

    public static func display(_ code: String) -> String {
        let c = Array(normalize(code))
        guard c.count == 12 else { return code }
        return stride(from: 0, to: 12, by: 4).map { String(c[$0..<$0 + 4]) }.joined(separator: "-")
    }

    /// PBKDF2 con 120 000 vueltas: el codigo tiene unos 58 bits, asi que cada intento de adivinarlo (por ejemplo con una conexion grabada
    /// que pasara por un relay) cuesta decenas de milisegundos en lugar de nanosegundos. Se calcula una vez por codigo y se recuerda.
    static let iterations: UInt32 = 120_000
    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cache: [String: SymmetricKey] = [:]

    static func baseKey(for code: String) -> SymmetricKey {
        let norm = normalize(code)
        cacheLock.lock(); if let k = cache[norm] { cacheLock.unlock(); return k }; cacheLock.unlock()
        let password = Array(norm.utf8), salt = Array("claude-pet-visto-v2".utf8)
        var out = [UInt8](repeating: 0, count: 32)
        _ = CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), password.map { Int8(bitPattern: $0) }, password.count, salt, salt.count,
                                 CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), iterations, &out, out.count)
        let key = SymmetricKey(data: out)
        cacheLock.lock(); if cache.count > 16 { cache.removeAll() }; cache[norm] = key; cacheLock.unlock()
        return key
    }

    /// Nombre de la sala en el relay: un hash de la clave derivada. Quien ve la sala no puede sacar el codigo sin repetir la derivacion lenta.
    public static func relayRoom(code: String) -> String {
        let key = baseKey(for: code).withUnsafeBytes { Data($0) }
        return SHA256.hash(data: key + Data("relay-room-v1".utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    /// Clave de una conexión concreta: cada lado aporta 16 bytes aleatorios, así que nunca se repite un nonce aunque el código sea el mismo.
    static func sessionKey(code: String, clientRandom: Data, hostRandom: Data) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: baseKey(for: code), salt: clientRandom + hostRandom, info: Data("session".utf8), outputByteCount: 32)
    }
}
