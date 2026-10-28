import Foundation
import Security

/// El código de emparejamiento es un secreto: vive en el llavero, no en UserDefaults.
enum VistoStore {
    private static let service = "com.kisnner26.visto"

    static var code: String? {
        get {
            let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "code",
                                    kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
            var out: CFTypeRef?
            guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
            return String(data: d, encoding: .utf8)
        }
        set {
            let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "code"]
            SecItemDelete(base as CFDictionary)
            guard let v = newValue, let d = v.data(using: .utf8) else { return }
            var add = base
            add[kSecValueData as String] = d
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(add as CFDictionary, nil)
        }
    }
}
