import Foundation
import Security

protocol TokenStoring {
    func read() -> String?
    func save(_ token: String) throws
    func delete()
}

struct KeychainError: Error, Equatable, LocalizedError {
    let status: OSStatus

    var errorDescription: String? {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "status \(status)"
        return "Keychain error: \(message)"
    }
}

struct Keychain: TokenStoring {
    private let service = "status-widget"
    private let account = "jira-api-token"

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func read() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard
            SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
            let data = result as? Data,
            let token = String(data: data, encoding: .utf8),
            !token.isEmpty
        else { return nil }
        return token
    }

    func save(_ token: String) throws {
        let data = Data(token.utf8)
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainError(status: updateStatus)
        }
        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainError(status: addStatus)
        }
    }

    func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
