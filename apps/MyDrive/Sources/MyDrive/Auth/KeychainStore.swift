import Foundation
import Security

/// Bọc Keychain (kSecClassGenericPassword) — lưu refresh token + access token.
/// Token KHÔNG chỉ nằm trên máy; xóa app mất Keychain → đăng nhập lại.
enum KeychainStore {
    private static let service = "vn.vudv.mydrive"

    /// Ghi 1 chuỗi cho key của account.
    static func set(_ value: String, forKey key: String, account: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "\(account)|\(key)",
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    /// Đọc 1 chuỗi cho key của account (nil nếu chưa có).
    static func get(_ key: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "\(account)|\(key)",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Xoá mọi key của 1 account (đăng xuất / xoá account).
    static func removeAll(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "\(account)|",   // prefix match không có sẵn — xoá từng key bên dưới
        ]
        SecItemDelete(query as CFDictionary)
        for key in ["refresh_token", "access_token", "token_expiry"] {
            var q = query
            q[kSecAttrAccount as String] = "\(account)|\(key)"
            SecItemDelete(q as CFDictionary)
        }
    }
}
