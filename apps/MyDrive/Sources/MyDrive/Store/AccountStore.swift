import Foundation

/// Một tài khoản Google đã đăng nhập. Identity = email (ổn định qua các lần cài lại).
struct DriveAccount: Codable, Hashable, Identifiable {
    var email: String
    /// Trạng thái đăng nhập: ok (token sống), needsReauth (refresh token chết), disabled (user tắt).
    var status: String        // "ok" | "needsReauth"
    /// Dung lượng cache (byte) — refresh từ about.get, không phải chân lý.
    var quotaLimit: Int64?
    var quotaUsage: Int64?
    var quotaUpdatedAt: Date?

    var id: String { email }

    var needsReauth: Bool { status == "needsReauth" }
    var freeBytes: Int64? {
        guard let limit = quotaLimit, let usage = quotaUsage else { return nil }
        return max(0, limit - usage)
    }
}

/// Quản lý danh sách account + token (lưu Keychain). Cài TokenProviding cho DriveClient.
final class AccountStore: ObservableObject, TokenProviding {
    static let shared = AccountStore()

    /// Danh sách account (persist ở UserDefaults — KHÔNG chứa token).
    @Published private(set) var accounts: [DriveAccount] = [] {
        didSet { persistAccounts() }
    }
    /// Account đang chọn để xem file (không ảnh hưởng placement — pool là chung).
    @Published var activeEmail: String?

    private let defaults: UserDefaults
    private static let accountsKey = "mydrive.accounts"
    private static let activeKey = "mydrive.activeAccount"

    /// Client ID đọc từ Info.plist.
    private var clientID: String { GoogleAuthService.clientID ?? "" }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.accountsKey),
           let list = try? JSONDecoder().decode([DriveAccount].self, from: data) {
            accounts = list
        }
        activeEmail = defaults.string(forKey: Self.activeKey)
    }

    private func persistAccounts() {
        if let data = try? JSONEncoder().encode(accounts) {
            defaults.set(data, forKey: Self.accountsKey)
        }
    }

    func setActive(_ email: String) {
        activeEmail = email
        defaults.set(email, forKey: Self.activeKey)
    }

    // MARK: - Đăng nhập / đăng xuất

    /// Thêm account sau khi OAuth xong. Trả email đã thêm.
    @discardableResult
    func addAccount(email: String, tokens: OAuthTokens) -> String {
        if let refresh = tokens.refresh_token {
            KeychainStore.set(refresh, forKey: "refresh_token", account: email)
        }
        updateTokens(email: email, tokens: tokens)
        if let idx = accounts.firstIndex(where: { $0.email == email }) {
            accounts[idx].status = "ok"
        } else {
            accounts.append(DriveAccount(email: email, status: "ok", quotaLimit: nil, quotaUsage: nil, quotaUpdatedAt: nil))
        }
        if activeEmail == nil { setActive(email) }
        return email
    }

    /// Cập nhật access token + thời điểm hết hạn (trước 60 giây để chắc).
    private func updateTokens(email: String, tokens: OAuthTokens) {
        KeychainStore.set(tokens.access_token, forKey: "access_token", account: email)
        let expiresAt = Date().addingTimeInterval((tokens.expires_in ?? 3600) - 60)
        KeychainStore.set("\(expiresAt.timeIntervalSince1970)", forKey: "token_expiry", account: email)
    }

    /// Xoá account khỏi app (không đụng dữ liệu trên Drive).
    func removeAccount(_ email: String) {
        KeychainStore.removeAll(account: email)
        accounts.removeAll { $0.email == email }
        if activeEmail == email {
            activeEmail = accounts.first?.email
            if let e = activeEmail { defaults.set(e, forKey: Self.activeKey) } else { defaults.removeObject(forKey: Self.activeKey) }
        }
    }

    /// Đánh dấu account cần đăng nhập lại (refresh token chết).
    func markNeedsReauth(_ email: String) {
        if let idx = accounts.firstIndex(where: { $0.email == email }) {
            accounts[idx].status = "needsReauth"
        }
    }

    func account(_ email: String) -> DriveAccount? {
        accounts.first { $0.email == email }
    }

    func client(for email: String) -> DriveClient? {
        guard accounts.contains(where: { $0.email == email }) else { return nil }
        return DriveClient(account: DriveAccount(email: email, status: "ok", quotaLimit: nil, quotaUsage: nil, quotaUpdatedAt: nil), tokens: self)
    }

    /// Cache quota vào model (để PlacementService và UI đọc).
    func updateQuota(email: String, limit: Int64, usage: Int64) {
        if let idx = accounts.firstIndex(where: { $0.email == email }) {
            accounts[idx].quotaLimit = limit
            accounts[idx].quotaUsage = usage
            accounts[idx].quotaUpdatedAt = Date()
        }
    }

    // MARK: - TokenProviding

    func validAccessToken(for account: DriveAccount) async throws -> String {
        guard let stored = self.account(account.email), !stored.needsReauth else {
            throw DriveError.invalidGrant
        }
        // Còn hạn thì dùng luôn.
        if let expiryText = KeychainStore.get("token_expiry", account: account.email),
           let seconds = Double(expiryText),
           Date(timeIntervalSince1970: seconds) > Date(),
           let token = KeychainStore.get("access_token", account: account.email) {
            return token
        }
        // Hết hạn → refresh.
        let token = try await refreshAccessToken(for: account.email)
        return token
    }

    func forceRefresh(for account: DriveAccount) async {
        _ = try? await refreshAccessToken(for: account.email)
    }

    /// Refresh token → access token mới (ném invalidGrant nếu cần reauth).
    private func refreshAccessToken(for email: String) async throws -> String {
        guard let refresh = KeychainStore.get("refresh_token", account: email), !clientID.isEmpty else {
            markNeedsReauth(email)
            throw DriveError.invalidGrant
        }
        do {
            let tokens = try await GoogleAuthService.refreshTokens(refreshToken: refresh, clientID: clientID)
            updateTokens(email: email, tokens: tokens)
            if let idx = accounts.firstIndex(where: { $0.email == email }) {
                accounts[idx].status = "ok"
            }
            return tokens.access_token
        } catch let err as DriveError {
            if case .invalidGrant = err {
                markNeedsReauth(email)
            }
            throw err
        }
    }
}
