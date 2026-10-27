import Foundation
import Security
import LocalAuthentication
import TaktCore

enum TickTickKeychain {
    private static func query(_ id: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "local.tolk.ticktick.personal-token",
         kSecAttrAccount as String: id.uuidString]
    }
    static func read(_ id: UUID) throws -> String {
        var q = query(id); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        let context = LAContext(); context.interactionNotAllowed = true
        q[kSecUseAuthenticationContext as String] = context
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data, let token = String(data: data, encoding: .utf8), !token.isEmpty else {
            throw TaktError.invalid("Доступ TickTick недоступен в Связке ключей. Подключите аккаунт заново в настройках.")
        }
        return token
    }
    static func save(_ token: String, id: UUID) throws {
        var q = query(id); q[kSecValueData as String] = Data(token.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(q as CFDictionary, nil)
        guard status == errSecSuccess else { throw TaktError.storage("Не удалось сохранить доступ TickTick в Связке ключей (\(status)).") }
    }
    static func replace(_ token: String, id: UUID) throws {
        let status = SecItemUpdate(query(id) as CFDictionary, [kSecValueData as String: Data(token.utf8)] as CFDictionary)
        if status == errSecItemNotFound { try save(token, id: id); return }
        guard status == errSecSuccess else { throw TaktError.storage("Не удалось заменить доступ TickTick в Связке ключей (\(status)).") }
    }
    static func remove(_ id: UUID) throws {
        let status = SecItemDelete(query(id) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw TaktError.storage("Не удалось удалить доступ TickTick из Связки ключей (\(status)).") }
    }
}
