import Foundation

// MARK: - Model Drive v3 (giải JSON trả về từ REST)

/// Một file/folder trên Drive. Đủ các trường app dùng (không lấy thừa).
struct DriveFile: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    /// nil khi fields mask không lấy mimeType (vd chỉ id,name) — decode không được
    /// chết vì thiếu key (đã từng làm ensureRootFolder fail "badJSON" vĩnh viễn).
    var mimeType: String?
    var size: String?          // Drive trả dạng chuỗi; nil với folder/Google Docs
    var modifiedTime: Date?
    var createdTime: Date?
    var trashed: Bool?
    var parents: [String]?
    var appProperties: [String: String]?

    var isFolder: Bool { mimeType == "application/vnd.google-apps.folder" }
    /// Kích thước byte (0 với folder).
    var sizeBytes: Int64 { size.flatMap { Int64($0) } ?? 0 }
}

/// Danh sách trả về từ `files.list`.
struct DriveFileList: Codable {
    var files: [DriveFile]
    var nextPageToken: String?
}

/// Thông tin dung lượng từ `about.get`.
struct DriveAbout: Codable {
    struct StorageQuota: Codable {
        var limit: String?
        var usage: String?
        var usageInDrive: String?
        var usageInDriveTrash: String?
    }
    var user: DriveUser?
    var storageQuota: StorageQuota?
}

/// Người dùng Google.
struct DriveUser: Codable, Hashable {
    var emailAddress: String?
    var displayName: String?
}

/// Token trả về từ `oauth2/v4/token`.
struct OAuthTokens: Codable {
    var access_token: String
    var expires_in: Double?
    var refresh_token: String?
    var scope: String?
    var token_type: String?
}

/// Lỗi HTTP từ Google (body JSON có `error.message`).
struct GoogleErrorBody: Codable {
    var error: GoogleErrorDetail?
}

struct GoogleErrorDetail: Codable {
    var code: Int?
    var message: String?
    var errors: [GoogleErrorItem]?
}

struct GoogleErrorItem: Codable {
    var reason: String?
    var message: String?
}

/// Phân loại lỗi để SyncEngine quyết định retry/chuyển account.
enum DriveError: Error, LocalizedError {
    case http(status: Int, reason: String?, message: String?)
    case noToken
    case invalidGrant      // refresh token chết → cần đăng nhập lại
    case quotaExceeded     // storageQuotaExceeded / userRateLimitExceeded...
    case cancelled

    var errorDescription: String? {
        switch self {
        case let .http(status, reason, message):
            if let reason { return "HTTP \(status) (\(reason)): \(message ?? "-")" }
            return "HTTP \(status): \(message ?? "-")"
        case .noToken: return "Chưa có access token (chưa đăng nhập)."
        case .invalidGrant: return "Phiên Google hết hạn — cần đăng nhập lại."
        case .quotaExceeded: return "Account Google hết dung lượng."
        case .cancelled: return "Đã huỷ."
        }
    }

    /// Lấy `reason` chuẩn Google từ body lỗi (vd "storageQuotaExceeded").
    static func parse(status: Int, data: Data?) -> DriveError {
        var reason: String?
        var message: String?
        if let data,
           let body = try? JSONDecoder().decode(GoogleErrorBody.self, from: data),
           let detail = body.error {
            message = detail.message
            reason = detail.errors?.first?.reason
        }
        // Một số trả 403 với reason storageQuotaExceeded.
        if reason == "storageQuotaExceeded" || reason == "quotaExceeded" || reason == "userRateLimitExceeded" {
            if reason == "storageQuotaExceeded" || reason == "quotaExceeded" { return .quotaExceeded }
        }
        return .http(status: status, reason: reason, message: message)
    }
}
