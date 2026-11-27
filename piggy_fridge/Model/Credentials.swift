import Foundation
import CryptoKit
import Security

/// Passwords stay on this iPhone. Only a salted hash is kept, in the Keychain, never the password itself.
enum Credentials {
    private static let service = "piggyfridge.password"
    private static let rounds = 20_000

    private static func key(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespaces).lowercased()
    }

    private static func hash(_ password: String, salt: Data) -> Data {
        var digest = Data(SHA256.hash(data: salt + Data(password.utf8)))
        for _ in 0..<rounds { digest = Data(SHA256.hash(data: salt + digest)) }
        return digest
    }

    private static func query(_ email: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: key(email)]
    }

    static func exists(email: String) -> Bool {
        var q = query(email)
        q[kSecReturnData as String] = false
        return SecItemCopyMatching(q as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    static func save(password: String, email: String) -> Bool {
        var salt = Data(count: 16)
        let status = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        guard status == errSecSuccess else { return false }
        let blob = salt + hash(password, salt: salt)
        SecItemDelete(query(email) as CFDictionary)
        var add = query(email)
        add[kSecValueData as String] = blob
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func verify(password: String, email: String) -> Bool {
        var q = query(email)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let blob = out as? Data, blob.count == 48 else { return false }
        let salt = blob.prefix(16)
        return hash(password, salt: Data(salt)) == blob.suffix(32)
    }

    static func remove(email: String) {
        SecItemDelete(query(email) as CFDictionary)
    }
}
