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
    /// hệ chữ khác hẳn (vd chữ Hàn trong truyện tiếng Anh) mới được đoán riêng.
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

        // Không kiểm tra `LanguageAvailability.status` trước khi dịch: trong appex nó báo `.supported`
        // (chưa tải) cho cả gói app chính đã tải xong. Dịch thẳng, lỗi thật mới báo.
        let dominantScript = Script.of(texts.joined())
        var groups: [NLLanguage: [TranslationSession.Request]] = [:]
        for block in blocks {
            guard let id = block["id"] as? Int, let text = block["text"] as? String else { continue }
            var language = dominant
            if Script.of(text) != dominantScript,
               let other = detect(text, among: keys, minConfidence: 0.8), sources[other] != nil {
                language = other
            }
            groups[language, default: []].append(TranslationSession.Request(sourceText: text, clientIdentifier: String(id)))
        }

        var translations: [[String: Any]] = []
        var retry: [TranslationSession.Request] = []
        for (key, requests) in groups where key != dominant {
            guard let source = sources[key] else { continue }
            do {
                translations += try await run(requests, from: source)
            } catch {
                // Gói phụ chưa tải: dịch các block đó theo ngôn ngữ chính còn hơn bỏ cả trang.
                ExtLog.log("offline: \(source.language.minimalIdentifier) lỗi (\(error)) → dịch theo \(dominantSource.language.minimalIdentifier)")
                retry += requests
            }
        }
        do {
            translations += try await run((groups[dominant] ?? []) + retry, from: dominantSource)
        } catch {
            let status = await LanguageAvailability(preferredStrategy: .highFidelity)
                .status(from: dominantSource.language, to: OfflineLanguages.target)
            ExtLog.log("offline: \(dominantSource.language.maximalIdentifier) lỗi \(error) (status \(status))")
            if status == .unsupported {
                throw MangalateError("Apple Dịch không hỗ trợ \(dominantSource.name) → Việt.")
            }
            throw MangalateError("Không dịch được \(dominantSource.name) → Việt (\(error.localizedDescription)). Nếu gói chưa tải: mở app Mangalate › Dịch offline để tải.")
        }
        return translations
    }

    /// Ưu tiên bản dịch chất lượng cao; gói chất lượng cao không dùng được thì thử gói chuẩn.
    private static func run(_ requests: [TranslationSession.Request], from source: OfflineLanguages.Source) async throws -> [[String: Any]] {
        guard !requests.isEmpty else { return [] }
        let responses: [TranslationSession.Response]
        do {
            responses = try await TranslationSession(
                installedSource: source.language,
                target: OfflineLanguages.target,
                preferredStrategy: .highFidelity
            ).translations(from: requests)
        } catch {
            ExtLog.log("offline: highFidelity \(source.language.minimalIdentifier) lỗi \(error), thử gói chuẩn")
            responses = try await TranslationSession(installedSource: source.language, target: OfflineLanguages.target)
                .translations(from: requests)
        }
        return responses.compactMap { response in
            response.clientIdentifier.flatMap(Int.init).map { ["id": $0, "text": response.targetText] }
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
