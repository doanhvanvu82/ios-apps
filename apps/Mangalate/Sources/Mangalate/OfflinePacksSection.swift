import OfflineLanguages
import SwiftUI
import Translation
// xtool build bằng explicit module nên cross-import overlay (`.translationTask`) không tự nạp.
import _Translation_SwiftUI

/// Tải gói Apple Dịch cho chế độ offline của extension: appex không hiện được hộp thoại tải,
/// nên phải tải ở đây (hộp thoại hệ thống hiện khi gọi `prepareTranslation`).
@available(iOS 26.4, *)
struct OfflinePacksSection: View {
    @State private var sources: [OfflineLanguages.Source] = []
    @State private var statuses: [String: LanguageAvailability.Status] = [:]
    @State private var configuration: TranslationSession.Configuration?
    /// Gói đang chờ tải, gói đầu là gói `configuration` đang tải: `translationTask` chỉ chạy một cấu hình mỗi lần.
    @State private var queue: [OfflineLanguages.Source] = []
    @State private var error: String?

    var body: some View {
        Section("4. Dịch offline (không cần key)") {
            Label("Trong popup chọn model **Offline – Apple Dịch**. Dịch trên máy, xưng hô/giới tính kém hơn Gemini. Chỉ cần tải ngôn ngữ của truyện bạn đọc.", systemImage: "wifi.slash")
            if sources.isEmpty {
                ProgressView()
            }
            let missing = sources.filter { statuses[$0.key.rawValue] == .supported }
            if !queue.isEmpty {
                Label("Đang tải \(queue.first?.name ?? "")… còn \(queue.count) gói", systemImage: "arrow.down.circle")
            } else if missing.count > 1 {
                Button("Tải tất cả (\(missing.count) gói)") { download(missing) }
            }
            ForEach(sources, id: \.key.rawValue) { source in
                HStack {
                    Text("\(source.name) → Việt")
                    Spacer()
                    switch statuses[source.key.rawValue] {
                    case .installed:
                        Label("Đã tải", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    case .supported:
                        Button("Tải") { download([source]) }
                            .disabled(!queue.isEmpty)
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
        .task {
            sources = await OfflineLanguages.sources()
            await refresh()
        }
        .translationTask(configuration) { session in
            do {
                try await session.prepareTranslation()
                error = nil
                queue = Array(queue.dropFirst())
            } catch {
                // Thường là người dùng huỷ hộp thoại tải — dừng cả hàng, không hỏi tiếp từng gói.
                self.error = "Không tải được gói \(queue.first?.name ?? ""): \(error.localizedDescription)"
                queue = []
            }
            await refresh()
            download(queue)
        }
    }

    /// Tải lần lượt; gán `configuration` mới thì `translationTask` chạy lại với gói kế tiếp.
    private func download(_ pending: [OfflineLanguages.Source]) {
        queue = pending
        configuration = pending.first.map {
            TranslationSession.Configuration(source: $0.language, target: OfflineLanguages.target, preferredStrategy: .highFidelity)
        }
    }

    private func refresh() async {
        let availability = LanguageAvailability(preferredStrategy: .highFidelity)
        for source in sources {
            statuses[source.key.rawValue] = await availability.status(from: source.language, to: OfflineLanguages.target)
        }
    }
}
