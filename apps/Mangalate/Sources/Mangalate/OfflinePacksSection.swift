import SwiftUI
import Translation
// xtool build bằng explicit module nên cross-import overlay (`.translationTask`) không tự nạp.
import _Translation_SwiftUI

/// Tải gói Apple Dịch cho chế độ offline của extension: appex không hiện được hộp thoại tải,
/// nên phải tải ở đây (hộp thoại hệ thống hiện khi gọi `prepareTranslation`).
@available(iOS 26.4, *)
struct OfflinePacksSection: View {
    /// Trùng `OfflineTranslator.sources` của extension.
    private static let sources: [(id: String, name: String)] = [
        ("ja", "Nhật"), ("ko", "Hàn"), ("zh-Hans", "Trung giản thể"), ("zh-Hant", "Trung phồn thể"), ("en", "Anh"),
    ]
    private static let target = Locale.Language(identifier: "vi")

    @State private var statuses: [String: LanguageAvailability.Status] = [:]
    @State private var configuration: TranslationSession.Configuration?
    @State private var error: String?

    var body: some View {
        Section("4. Dịch offline (không cần key)") {
            Label("Trong popup chọn model **Offline – Apple Dịch**. Dịch trên máy, xưng hô/giới tính kém hơn Gemini.", systemImage: "wifi.slash")
            ForEach(Self.sources, id: \.id) { source in
                HStack {
                    Text("\(source.name) → Việt")
                    Spacer()
                    switch statuses[source.id] {
                    case .installed:
                        Label("Đã tải", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    case .supported:
                        Button("Tải") {
                            configuration = TranslationSession.Configuration(
                                source: Locale.Language(identifier: source.id),
                                target: Self.target,
                                preferredStrategy: .highFidelity
                            )
                        }
                    case .unsupported, .some:
                        Text("Không hỗ trợ").foregroundStyle(.secondary)
                    case nil:
                        ProgressView()
                    }
                }
            }
            if let error {
                Text(error).foregroundStyle(.red).font(.footnote)
            }
        }
        .task { await refresh() }
        .translationTask(configuration) { session in
            do {
                try await session.prepareTranslation()
                error = nil
            } catch {
                self.error = "Không tải được gói ngôn ngữ: \(error.localizedDescription)"
            }
            configuration = nil
            await refresh()
        }
    }

    private func refresh() async {
        let availability = LanguageAvailability(preferredStrategy: .highFidelity)
        for source in Self.sources {
            statuses[source.id] = await availability.status(from: Locale.Language(identifier: source.id), to: Self.target)
        }
    }
}
