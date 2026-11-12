import Foundation
import NaturalLanguage
import Translation

/// Dịch trên máy bằng Apple Translation — không cần mạng/API key, nhưng dịch từng block riêng lẻ
/// (không có hồ sơ nhân vật, xưng hô kém hơn Gemini). Gói ngôn ngữ phải được tải trước trong app chính:
/// appex không hiện được hộp thoại tải.
@available(iOS 26.4, *)
enum OfflineTranslator {
    static let sources: [NLLanguage] = [.japanese, .korean, .simplifiedChinese, .traditionalChinese, .english]
    private static let target = Locale.Language(identifier: "vi")

    /// [{id, text}] → [{id, text}] tiếng Việt. Block ngắn ("…", "!?") không đoán được ngôn ngữ thì theo ngôn ngữ chiếm đa số của lô.
    static func translate(blocks: [[String: Any]]) async throws -> [[String: Any]] {
        let dominant = detect(blocks.compactMap { $0["text"] as? String }.joined(separator: "\n"), minConfidence: 0)
        var groups: [NLLanguage: [TranslationSession.Request]] = [:]
        for block in blocks {
            guard let id = block["id"] as? Int, let text = block["text"] as? String else { continue }
            guard let language = detect(text, minConfidence: 0.8) ?? dominant else { continue }
            groups[language, default: []].append(TranslationSession.Request(sourceText: text, clientIdentifier: String(id)))
        }
        guard !groups.isEmpty else {
            throw MangalateError("Không nhận ra ngôn ngữ của chữ trên trang (dịch offline hỗ trợ Nhật, Hàn, Trung, Anh).")
        }

        let availability = LanguageAvailability(preferredStrategy: .highFidelity)
        var translations: [[String: Any]] = []
        for (language, requests) in groups {
            let source = Locale.Language(identifier: language.rawValue)
            switch await availability.status(from: source, to: target) {
            case .installed:
                break
            case .supported:
                throw MangalateError("Chưa tải gói dịch \(displayName(language)) → Việt. Mở app Mangalate › Dịch offline để tải.")
            case .unsupported:
                throw MangalateError("Apple Dịch không hỗ trợ \(displayName(language)) → Việt.")
            @unknown default:
                throw MangalateError("Apple Dịch không hỗ trợ \(displayName(language)) → Việt.")
            }
            let session = TranslationSession(installedSource: source, target: target, preferredStrategy: .highFidelity)
            for response in try await session.translations(from: requests) {
                guard let id = response.clientIdentifier.flatMap(Int.init) else { continue }
                translations.append(["id": id, "text": response.targetText])
            }
        }
        return translations
    }

    private static func detect(_ text: String, minConfidence: Double) -> NLLanguage? {
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = sources
        recognizer.processString(text)
        guard let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).first,
              confidence >= minConfidence else {
            return nil
        }
        return language
    }

    private static func displayName(_ language: NLLanguage) -> String {
        Locale(identifier: "vi").localizedString(forIdentifier: language.rawValue) ?? language.rawValue
    }
}
