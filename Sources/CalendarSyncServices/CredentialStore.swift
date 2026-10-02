import Foundation
import Security

public enum CredentialStoreError: Error, LocalizedError, Sendable {
    case keychain(OSStatus)
    case invalidEncoding

    public var errorDescription: String? {
        switch self {
        case .keychain(let status): "Mac 키체인 오류(\(status))"
        case .invalidEncoding: "저장된 인증 정보를 읽을 수 없습니다"
        }
    }
}

/// Calendar secrets are stored separately from attendance data and sync metadata.
public struct CredentialStore: Sendable {
    private let service: String

    public init(service: String = "local.chanyoung.AfterSix.CalendarSync") {
        self.service = service
    }

    public func save(_ value: String, for account: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let update: [String: Any] = [kSecValueData as String: data]
        let result = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if result == errSecSuccess { return }
        guard result == errSecItemNotFound else { throw CredentialStoreError.keychain(result) }
        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let added = SecItemAdd(insert as CFDictionary, nil)
        guard added == errSecSuccess else { throw CredentialStoreError.keychain(added) }
    }

    public func load(for account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw CredentialStoreError.keychain(status) }
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw CredentialStoreError.invalidEncoding
        }
        return value
    }

    public func remove(for account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.keychain(status)
        }
    }
}
