import Foundation
import NaturalLanguage
import Translation

/// Ngôn ngữ nguồn cho dịch offline — dùng chung cho app (tải gói) và extension (nhận diện + dịch)
/// để hai bên luôn kiểm tra đúng cùng một cặp ngôn ngữ.
@available(iOS 26.4, *)
public enum OfflineLanguages {
    public static let target = Locale.Language(identifier: "vi")

    public struct Source: Sendable {
        /// Mã cho `NLLanguageRecognizer`.
        public let key: NLLanguage
        /// Ngôn ngữ đúng như Apple Dịch liệt kê — dùng cho tải gói, kiểm tra trạng thái và dịch.
        public let language: Locale.Language
        public let name: String
    }

    /// Mọi ngôn ngữ Apple Dịch hỗ trợ (trừ tiếng Việt), mỗi mã nhận diện một biến thể (vd en-US và en-GB → "en").
    public static func sources() async -> [Source] {
        var seen = Set<NLLanguage>()
        var result: [Source] = []
        for language in await LanguageAvailability().supportedLanguages {
            guard let key = recognizerKey(language), seen.insert(key).inserted else { continue }
            result.append(Source(key: key, language: language, name: displayName(language)))
        }
        return result.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    static func recognizerKey(_ language: Locale.Language) -> NLLanguage? {
        guard let code = language.languageCode?.identifier, code != "vi" else { return nil }
        guard code == "zh" else { return NLLanguage(rawValue: code) }
        // NaturalLanguage tách Trung giản thể/phồn thể theo chữ viết; Apple Dịch có thể chỉ ghi vùng (zh-TW).
        let script = language.script?.identifier ?? (language.region?.identifier == "TW" ? "Hant" : "Hans")
        return NLLanguage(rawValue: "zh-\(script)")
    }

    private static func displayName(_ language: Locale.Language) -> String {
        Locale(identifier: "vi").localizedString(forIdentifier: language.minimalIdentifier) ?? language.minimalIdentifier
    }
}
