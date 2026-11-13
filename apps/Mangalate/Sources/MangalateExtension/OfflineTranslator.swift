import Foundation
import NaturalLanguage
import OfflineLanguages
import Translation

/// Dịch trên máy bằng Apple Translation — không cần mạng/API key, nhưng dịch từng block riêng lẻ
/// (không có hồ sơ nhân vật, xưng hô kém hơn Gemini). Gói ngôn ngữ phải được tải trước trong app chính:
/// appex không hiện được hộp thoại tải.
@available(iOS 26.4, *)
enum OfflineTranslator {
    /// Ngôn ngữ chính của cả chapter (mã `NLLanguage`). Đoán trên toàn bộ chữ chứ không theo từng lô:
    /// lô dịch nhỏ (vài câu ngắn viết hoa, chữ OCR lỗi) dễ bị đoán nhầm sang ngôn ngữ khác.
    static func detectLanguage(blocks: [[String: Any]]) async -> String? {
        let keys = (await OfflineLanguages.sources()).map(\.key)
        return detect(blocks.compactMap { $0["text"] as? String }.joined(separator: "\n"), among: keys, minConfidence: 0)?.rawValue
    }

    /// [{id, text}] → [{id, text}] tiếng Việt. Mọi block dịch theo ngôn ngữ chính của chapter; chỉ block viết bằng
    /// hệ chữ khác hẳn (vd chữ Hàn trong truyện tiếng Anh) mới được đoán riêng và chỉ khi gói đó đã tải.
    static func translate(blocks: [[String: Any]], language hint: String?) async throws -> [[String: Any]] {
        let sources = Dictionary(
            (await OfflineLanguages.sources()).map { ($0.key, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let keys = Array(sources.keys)
        let texts = blocks.compactMap { $0["text"] as? String }
        guard let dominant = hint.map(NLLanguage.init(rawValue:)).flatMap({ sources[$0] == nil ? nil : $0 })
            ?? detect(texts.joined(separator: "\n"), among: keys, minConfidence: 0),
            let dominantSource = sources[dominant] else {
            throw MangalateError("Không nhận ra ngôn ngữ của chữ trên trang, hoặc Apple Dịch không hỗ trợ ngôn ngữ này.")
        }

        let availability = LanguageAvailability(preferredStrategy: .highFidelity)
        guard try await isInstalled(dominantSource, availability) else {
            throw MangalateError("Chưa tải gói dịch \(dominantSource.name) → Việt. Mở app Mangalate › Dịch offline để tải.")
        }
        let dominantScript = Script.of(texts.joined())
        var installed: [NLLanguage: Bool] = [dominant: true]
        var groups: [NLLanguage: [TranslationSession.Request]] = [:]
        for block in blocks {
            guard let id = block["id"] as? Int, let text = block["text"] as? String else { continue }
            var language = dominant
            if Script.of(text) != dominantScript,
               let other = detect(text, among: keys, minConfidence: 0.8), let source = sources[other] {
                if installed[other] == nil { installed[other] = (try? await isInstalled(source, availability)) ?? false }
                if installed[other] == true { language = other }
            }
            groups[language, default: []].append(TranslationSession.Request(sourceText: text, clientIdentifier: String(id)))
        }

        var translations: [[String: Any]] = []
        for (key, requests) in groups {
            guard let source = sources[key] else { continue }
            let session = TranslationSession(
                installedSource: source.language,
                target: OfflineLanguages.target,
                preferredStrategy: .highFidelity
            )
            for response in try await session.translations(from: requests) {
                guard let id = response.clientIdentifier.flatMap(Int.init) else { continue }
                translations.append(["id": id, "text": response.targetText])
            }
        }
        return translations
    }

    private static func isInstalled(_ source: OfflineLanguages.Source, _ availability: LanguageAvailability) async throws -> Bool {
        switch await availability.status(from: source.language, to: OfflineLanguages.target) {
        case .installed:
            return true
        case .supported:
            return false
        case .unsupported:
            throw MangalateError("Apple Dịch không hỗ trợ \(source.name) → Việt.")
        @unknown default:
            throw MangalateError("Apple Dịch không hỗ trợ \(source.name) → Việt.")
        }
    }

    private static func detect(_ text: String, among keys: [NLLanguage], minConfidence: Double) -> NLLanguage? {
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = keys
        recognizer.processString(text)
        guard let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).first,
              confidence >= minConfidence else {
            return nil
        }
        return language
    }

    /// Hệ chữ chiếm đa số trong chuỗi. Hán và kana gộp làm một: truyện Nhật lẫn kanji vẫn là một hệ chữ.
    enum Script: Equatable {
        case latin, cjk, hangul, cyrillic, arabic, thai, other

        static func of(_ text: String) -> Script? {
            var counts: [Script: Int] = [:]
            for scalar in text.unicodeScalars where scalar.properties.isAlphabetic {
                counts[classify(scalar.value), default: 0] += 1
            }
            return counts.max { $0.value < $1.value }?.key
        }

        private static func classify(_ value: UInt32) -> Script {
            switch value {
            case 0x41...0x24F, 0x1E00...0x1EFF: return .latin
            case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0xFF66...0xFF9F: return .cjk
            case 0x1100...0x11FF, 0x3130...0x318F, 0xAC00...0xD7AF: return .hangul
            case 0x400...0x4FF: return .cyrillic
            case 0x600...0x6FF: return .arabic
            case 0xE00...0xE7F: return .thai
            default: return .other
            }
        }
    }
}
