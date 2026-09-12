import CompanionCore
import Foundation
import Security

final class KeychainStore: CredentialStoring, @unchecked Sendable {
    func put(hostId: String, token: String) throws {
        let data = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: hostId,
            kSecAttrService as String: "dev.vibex.companion.device",
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            #if targetEnvironment(simulator)
            UserDefaults.standard.set(token, forKey: "cred.\(hostId)")
            #else
            throw CompanionError.transport("无法写入钥匙串")
            #endif
        }
    }

    func get(hostId: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: hostId,
            kSecAttrService as String: "dev.vibex.companion.device",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data {
            return String(data: data, encoding: .utf8)
        }
        #if targetEnvironment(simulator)
        return UserDefaults.standard.string(forKey: "cred.\(hostId)")
        #else
        return nil
        #endif
    }

    func remove(hostId: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: hostId,
            kSecAttrService as String: "dev.vibex.companion.device",
        ]
        SecItemDelete(query as CFDictionary)
        UserDefaults.standard.removeObject(forKey: "cred.\(hostId)")
    }
}
