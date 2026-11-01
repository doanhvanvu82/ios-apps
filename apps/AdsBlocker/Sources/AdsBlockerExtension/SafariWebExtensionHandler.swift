import Foundation
import SafariServices

/// Nhận message từ background.js (`browser.runtime.sendNativeMessage`).
///
/// API key chỉ đi một chiều JS → Keychain: không action nào trả key về JS.
///
/// Message:
///   {action: "getSettings"}                          → {ok, hasKey, model}
///   {action: "saveSettings", apiKey?, model?}        → {ok}   (apiKey "" = xoá key)
///   {action: "listModels"}                           → {ok, models: [{id, name}]}
///   {action: "analyze", page: {...}, screenshot?, mode?: "picked"|"trackers"} → {ok, rules: [...]}
///   {action: "diagnose", problem, page: {...}}         → {ok, summary, fixes: [...]}
///   lỗi                                              → {ok: false, error}
@objc(SafariWebExtensionHandler)
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let item = context.inputItems.first as? NSExtensionItem
        let message = item?.userInfo?[SFExtensionMessageKey] as? [String: Any] ?? [:]

        Task {
            let reply: [String: Any]
            do {
                reply = try await Self.handle(message)
            } catch {
                reply = ["ok": false, "error": error.localizedDescription]
            }
            let response = NSExtensionItem()
            response.userInfo = [SFExtensionMessageKey: reply]
            context.completeRequest(returningItems: [response], completionHandler: nil)
        }
    }

    private static func handle(_ message: [String: Any]) async throws -> [String: Any] {
        switch message["action"] as? String {
        case "getSettings":
            return ["ok": true, "hasKey": Settings.apiKey != nil, "model": Settings.model ?? ""]

        case "saveSettings":
            if let apiKey = message["apiKey"] as? String {
                try Settings.setAPIKey(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            if let model = message["model"] as? String {
                Settings.model = model
            }
            return ["ok": true]

        case "listModels":
            let models = try await client().listModels()
            return ["ok": true, "models": models]

        case "analyze":
            guard let model = Settings.model, !model.isEmpty else {
                throw GeminiError("Chưa chọn model Gemini. Mở Cài đặt trong popup để chọn.")
            }
            guard let page = message["page"] as? [String: Any] else {
                throw GeminiError("Thiếu dữ liệu trang để phân tích.")
            }
            let rules = try await client().analyze(
                model: model,
                page: page,
                screenshot: message["screenshot"] as? String,
                mode: GeminiClient.Mode(rawValue: message["mode"] as? String ?? "") ?? .scan
            )
            return ["ok": true, "rules": rules]

        case "diagnose":
            guard let model = Settings.model, !model.isEmpty else {
                throw GeminiError("Chưa chọn model Gemini. Mở Cài đặt trong popup để chọn.")
            }
            guard let page = message["page"] as? [String: Any], let problem = message["problem"] as? String else {
                throw GeminiError("Thiếu mô tả vấn đề hoặc dữ liệu trang để chẩn đoán.")
            }
            var reply = try await client().diagnose(model: model, problem: problem, page: page)
            reply["ok"] = true
            return reply

        default:
            throw GeminiError("Action không hợp lệ: \(message["action"] ?? "nil")")
        }
    }

    private static func client() throws -> GeminiClient {
        guard let apiKey = Settings.apiKey else {
            throw GeminiError("Chưa nhập Gemini API key. Mở Cài đặt trong popup để nhập.")
        }
        return GeminiClient(apiKey: apiKey)
    }
}

/// Model lưu UserDefaults (không bí mật); API key lưu Keychain.
enum Settings {
    private static let modelKey = "geminiModel"
    private static let apiKeyAccount = "geminiApiKey"

    static var model: String? {
        get { UserDefaults.standard.string(forKey: modelKey) }
        set { UserDefaults.standard.set(newValue, forKey: modelKey) }
    }

    static var apiKey: String? {
        KeychainStore.read(account: apiKeyAccount)
    }

    static func setAPIKey(_ value: String) throws {
        try KeychainStore.write(account: apiKeyAccount, value: value.isEmpty ? nil : value)
    }
}
