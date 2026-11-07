import AuthenticationServices
import CryptoKit
import Foundation

/// Đăng nhập Google bằng ASWebAuthenticationSession (RFC 8252 + PKCE).
/// Google chặn OAuth trong WebView nhúng → bắt buộc dùng API hệ thống này.
final class GoogleAuthService: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = GoogleAuthService()

    /// Đọc Client ID từ Info.plist (build.sh ghi từ oauth_client.txt).
    static var clientID: String? {
        let id = Bundle.main.object(forInfoDictionaryKey: "MyDriveOAuthClientID") as? String
        return (id?.isEmpty == false) ? id : nil
    }

    static var isConfigured: Bool { clientID != nil }

    /// Scopes: đủ dùng cho app (drive.file = non-sensitive, không cần verify).
    static let scopes = [
        "https://www.googleapis.com/auth/drive.file",
        "openid",
        "email",
        "profile",
    ].joined(separator: " ")

    /// Scheme redirect chuẩn Google cho OAuth client loại iOS:
    /// đảo thứ tự các thành phần của client ID ngăn cách bằng dấu chấm,
    /// mỗi thành phần giữ nguyên ("123-abc.apps.googleusercontent.com" →
    /// "com.googleusercontent.apps.123-abc").
    static func reversedClientID(_ clientID: String) -> String {
        clientID.split(separator: ".").map(String.init).reversed().joined(separator: ".")
    }

    // MARK: - PKCE

    private func randomCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 48)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    // MARK: - Flow chính

    /// Mở màn Google, chờ user đăng nhập + chọn account, đổi code lấy token.
    /// Trả (email, tokens). Ném lỗi nếu user huỷ / thiếu cấu hình.
    func signIn(presenting anchor: ASPresentationAnchor) async throws -> (email: String, tokens: OAuthTokens) {
        guard let clientID = Self.clientID else {
            throw DriveError.http(status: 0, reason: "noClientID", message: "Chưa cấu hình OAuth Client ID (oauth_client.txt + build lại).")
        }
        let scheme = Self.reversedClientID(clientID)
        let redirectURI = scheme + ":"

        let verifier = randomCodeVerifier()
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()

        var comps = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        comps.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: Self.scopes),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "prompt", value: "select_account"),
        ]
        guard let authURL = comps.url else {
            throw DriveError.http(status: 0, reason: "badAuthURL", message: nil)
        }

        // Chờ user xong trên trang Google. callbackURLScheme phải khớp scheme
        // đã đăng ký trong Info.plist (CFBundleURLTypes do build.sh ghi).
        let callbackURL: URL = try await withCheckedThrowingContinuation { cont in
            let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: scheme) { callbackURL, error in
                if let error {
                    cont.resume(throwing: error)
                } else if let callbackURL {
                    cont.resume(returning: callbackURL)
                } else {
                    cont.resume(throwing: DriveError.cancelled)
                }
            }
            session.presentationContextProvider = self
            // Không xoa cookie phiên → đăng nhập account kế tiếp nhanh hơn.
            session.prefersEphemeralWebBrowserSession = false
            Self.activeSession = session
            session.start()
        }

        guard let callbackComps = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let authCode = callbackComps.queryItems?.first(where: { $0.name == "code" })?.value else {
            // Google trả ?error=access_denied hoặc thiếu code.
            throw DriveError.cancelled
        }

        let tokens = try await Self.exchangeCode(authCode, verifier: verifier, clientID: clientID, redirectURI: redirectURI)
        let email = try await Self.fetchEmail(accessToken: tokens.access_token)
        return (email, tokens)
    }

    /// Đổi refresh token lấy token mới.
    static func refreshTokens(refreshToken: String, clientID: String) async throws -> OAuthTokens {
        var comps = URLComponents(string: "https://oauth2.googleapis.com/token")!
        comps.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "grant_type", value: "refresh_token"),
        ]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw DriveError.http(status: 0, reason: "noResponse", message: nil)
        }
        guard http.statusCode == 200 else {
            let text = String(decoding: data.prefix(300), as: UTF8.self)
            if text.contains("invalid_grant") {
                throw DriveError.invalidGrant
            }
            throw DriveError.http(status: http.statusCode, reason: "tokenRefresh", message: text)
        }
        return try JSONDecoder().decode(OAuthTokens.self, from: data)
    }

    /// Đổi authorization code (lần đầu) lấy token pair.
    static func exchangeCode(_ code: String, verifier: String, clientID: String, redirectURI: String) async throws -> OAuthTokens {
        var comps = URLComponents(string: "https://oauth2.googleapis.com/token")!
        comps.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "code_verifier", value: verifier),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "grant_type", value: "authorization_code"),
        ]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw DriveError.http(status: 0, reason: "noResponse", message: nil)
        }
        guard http.statusCode == 200 else {
            let text = String(decoding: data.prefix(300), as: UTF8.self)
            throw DriveError.http(status: http.statusCode, reason: "tokenExchange", message: text)
        }
        return try JSONDecoder().decode(OAuthTokens.self, from: data)
    }

    /// Email của access token (userinfo v3).
    static func fetchEmail(accessToken: String) async throws -> String {
        var req = URLRequest(url: URL(string: "https://www.googleapis.com/oauth2/v3/userinfo")!)
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw DriveError.http(status: (resp as? HTTPURLResponse)?.statusCode ?? 0, reason: "userinfo", message: nil)
        }
        struct UserInfo: Decodable { let email: String? }
        let info = try JSONDecoder().decode(UserInfo.self, from: data)
        guard let email = info.email else {
            throw DriveError.http(status: 0, reason: "noEmail", message: nil)
        }
        return email
    }

    // MARK: - ASWebAuthenticationPresentationContextProviding

    private static weak var activeSession: ASWebAuthenticationSession?

    /// ASWebAuthenticationSession gọi trên main thread khi UI đang hiển thị.
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first ?? ASPresentationAnchor()
    }
}

extension Data {
    /// base64url không padding (chuẩn PKCE).
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
