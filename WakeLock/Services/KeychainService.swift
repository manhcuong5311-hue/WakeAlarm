import Foundation
import Security

/// Thin wrapper around iOS Keychain for secure storage of QR values and alarm data
final class KeychainService {

    static let shared = KeychainService()
    private init() {}

    private let service = "com.wakelock.app"

    // MARK: - Write

    @discardableResult
    func save(_ value: String, forKey key: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        return save(data, forKey: key)
    }

    @discardableResult
    func save(_ data: Data, forKey key: String) -> Bool {
        // Delete existing item first
        delete(forKey: key)

        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String:   data,
            // Only accessible when device is unlocked (not after restart until first unlock)
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    // MARK: - Read

    func load(forKey key: String) -> String? {
        guard let data = loadData(forKey: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func loadData(forKey key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    // MARK: - Delete

    @discardableResult
    func delete(forKey key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }

    // MARK: - Codable helpers

    func saveCodable<T: Codable>(_ value: T, forKey key: String) -> Bool {
        guard let data = try? JSONEncoder().encode(value) else { return false }
        return save(data, forKey: key)
    }

    func loadCodable<T: Codable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = loadData(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
