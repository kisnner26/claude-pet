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

    static func baseKey(for code: String) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: Data(normalize(code).utf8)),
                               salt: Data("claude-pet-visto-v1".utf8), info: Data("code-key".utf8), outputByteCount: 32)
    }

    /// Clave de una conexión concreta: cada lado aporta 16 bytes aleatorios, así que nunca se repite un nonce aunque el código sea el mismo.
    static func sessionKey(code: String, clientRandom: Data, hostRandom: Data) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: baseKey(for: code), salt: clientRandom + hostRandom, info: Data("session".utf8), outputByteCount: 32)
    }
}
