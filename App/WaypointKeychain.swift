import CryptoKit
import Foundation
import Security

final class WaypointKeychain {
    private let service = "com.raph559.waypoint.signing-key"
    private let account = "default"

    init() {}

    func savePrivateKey(_ key: Curve25519.Signing.PrivateKey) throws {
        try deletePrivateKey()

        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: key.rawRepresentation,
        ]

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw WaypointAPIError.keychainStatus(status)
        }
    }

    func loadPrivateKey() throws -> Curve25519.Signing.PrivateKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw WaypointAPIError.keychainStatus(status)
        }
        guard let data = result as? Data else {
            throw WaypointAPIError.invalidPrivateKey
        }

        do {
            return try Curve25519.Signing.PrivateKey(rawRepresentation: data)
        } catch {
            throw WaypointAPIError.invalidPrivateKey
        }
    }

    func deletePrivateKey() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw WaypointAPIError.keychainStatus(status)
        }
    }
}
