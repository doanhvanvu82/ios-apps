import Foundation
import SafariServices
import UIKit

/// Nhận message từ background.js (`browser.runtime.sendNativeMessage`).
///
/// API key chỉ đi một chiều JS → Keychain: không action nào trả key về JS.
/// Không action nào trả ảnh; ảnh chỉ được đọc trên máy để OCR.
///
/// Message:
///   {action: "getSettings"}                     → {ok, hasKey, model, offline}
///   (model "apple-offline" = dịch trên máy bằng Apple Translation, không cần key)
///   {action: "saveSettings", apiKey?, model?}   → {ok}   (apiKey "" = xoá key)
///   {action: "listModels"}                      → {ok, models: [{id, name}]}
///   {action: "ocr", image, languages?}          → {ok, lines: [{text, confidence, box, bg}]}
///   {action: "ocrUrl", url, referer?, cookie?, languages?} → {ok, lines}
///   {action: "analyze", blocks: [{id, text}]}   → {ok, context} (hồ sơ nhân vật/cách xưng hô)
///   {action: "translate", blocks: [{id, text}], context?} → {ok, translations: [{id, text}]}
///   {action: "log", text}                       → {ok}
///   lỗi                                         → {ok: false, error}
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
                ExtLog.log("lỗi \(message["action"] ?? "nil"): \(error.localizedDescription)")
                reply = ["ok": false, "error": error.localizedDescription]
            }
            let response = NSExtensionItem()
            response.userInfo = [SFExtensionMessageKey: reply]
            context.completeRequest(returningItems: [response], completionHandler: nil)
        }
    }

    private static func handle(_ message: [String: Any]) async throws -> [String: Any] {
        let action = message["action"] as? String ?? ""
        switch action {
        case "getSettings":
            return ["ok": true, "hasKey": Settings.apiKey != nil, "model": Settings.model, "offline": Settings.isOffline]

        case "saveSettings":
            if let apiKey = message["apiKey"] as? String {
                try Settings.setAPIKey(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            if let model = message["model"] as? String, !model.isEmpty {
                Settings.model = model
            }
            return ["ok": true]

        case "listModels":
            let models = try await client().listModels()
            return ["ok": true, "models": models]

        case "translate":
            let blocks = try textBlocks(message)
            let context = message["context"] as? String ?? ""
            let started = Date()
            let translations = try await Settings.isOffline
                ? offlineTranslate(blocks, language: message["language"] as? String)
                : client().translate(model: Settings.model, blocks: blocks, context: String(context.prefix(4000)))
            ExtLog.log("dịch \(blocks.count) block (\(Settings.model)) trong \(String(format: "%.1f", Date().timeIntervalSince(started)))s")
            return ["ok": true, "translations": translations]

        case "analyze":
            let blocks = try textBlocks(message)
            // Apple Translation dịch từng câu, không nhận hồ sơ chapter — chỉ cần chốt ngôn ngữ của cả chapter.
            if Settings.isOffline {
                var reply: [String: Any] = ["ok": true, "context": ""]
                if #available(iOS 26.4, *), let language = await OfflineTranslator.detectLanguage(blocks: blocks) {
                    ExtLog.log("ngôn ngữ chapter: \(language)")
                    reply["language"] = language
                }
                return reply
            }
            let started = Date()
            let context = try await client().analyze(model: Settings.model, blocks: blocks)
            ExtLog.log("phân tích \(blocks.count) block → \(context.count) ký tự trong \(String(format: "%.1f", Date().timeIntervalSince(started)))s")
            return ["ok": true, "context": context]

        case "ocr":
            guard let dataURL = message["image"] as? String else {
                throw MangalateError("Thiếu ảnh để OCR.")
            }
            guard let image = decodeImage(dataURL) else {
                throw MangalateError("Dữ liệu ảnh không đọc được.")
            }
            let started = Date()
            let lines = try TextRecognizer.recognize(image: image, languages: message["languages"] as? [String])
            ExtLog.log("OCR \(Int(image.size.width))x\(Int(image.size.height)) → \(lines.count) dòng trong \(String(format: "%.1f", Date().timeIntervalSince(started)))s")
            return ["ok": true, "lines": lines]

        case "ocrUrl":
            guard let url = message["url"] as? String else {
                throw MangalateError("Thiếu URL ảnh.")
            }
            let image = try await ImageFetcher.download(
                url: url,
                referer: message["referer"] as? String,
                cookie: message["cookie"] as? String
            )
            let lines = try TextRecognizer.recognize(image: image, languages: message["languages"] as? [String])
            return ["ok": true, "lines": lines]

        case "log":
            ExtLog.log("JS: " + (message["text"] as? String ?? ""))
            return ["ok": true]

        default:
            throw MangalateError("Action không hợp lệ: \(action.isEmpty ? "nil" : action)")
        }
    }

    /// Lọc text hợp lệ từ payload — dùng chung cho `translate` và `analyze`.
    private static func textBlocks(_ message: [String: Any]) throws -> [[String: Any]] {
        guard let raw = message["blocks"] as? [[String: Any]], !raw.isEmpty else {
            throw MangalateError("Thiếu text cần dịch.")
        }
        let blocks = raw.compactMap { block -> [String: Any]? in
            guard let id = block["id"] as? Int, let text = block["text"] as? String else { return nil }
            let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2000))
            return trimmed.isEmpty ? nil : ["id": id, "text": trimmed]
        }
        guard !blocks.isEmpty else {
            throw MangalateError("Không có text hợp lệ để dịch.")
        }
        return blocks
    }

    private static func decodeImage(_ dataURL: String) -> UIImage? {
        guard let comma = dataURL.firstIndex(of: ",") else { return nil }
        let base64 = String(dataURL[dataURL.index(after: comma)...])
        guard let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) else { return nil }
        return UIImage(data: data)
    }

    private static func offlineTranslate(_ blocks: [[String: Any]], language: String?) async throws -> [[String: Any]] {
        guard #available(iOS 26.4, *) else {
            throw MangalateError("Dịch offline cần iOS 26.4 trở lên.")
        }
        return try await OfflineTranslator.translate(blocks: blocks, language: language)
    }

    private static func client() throws -> GeminiClient {
        guard let apiKey = Settings.apiKey, !apiKey.isEmpty else {
            throw MangalateError("Chưa nhập Gemini API key. Mở popup Mangalate để nhập.")
        }
        return GeminiClient(apiKey: apiKey)
    }
}

/// Model lưu UserDefaults (không bí mật); API key lưu Keychain.
enum Settings {
    private static let modelKey = "geminiModel"
    private static let apiKeyAccount = "geminiApiKey"
    static let defaultModel = "gemini-2.5-flash"
    /// "Model" giả cho Apple Translation trên máy — trùng `OFFLINE_MODEL` trong popup.js.
    static let offlineModel = "apple-offline"

    static var isOffline: Bool { model == offlineModel }

    static var model: String {
        get { UserDefaults.standard.string(forKey: modelKey) ?? defaultModel }
        set { UserDefaults.standard.set(newValue, forKey: modelKey) }
    }

    static var apiKey: String? {
        KeychainStore.read(account: apiKeyAccount)
    }

    static func setAPIKey(_ value: String) throws {
        try KeychainStore.write(account: apiKeyAccount, value: value.isEmpty ? nil : value)
    }
}
