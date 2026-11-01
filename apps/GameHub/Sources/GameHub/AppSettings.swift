import SwiftUI
import Combine

/// Cài đặt của app — lưu trong `Documents/GameHub/settings.json`.
///
/// Hiện có:
/// - `hapticsEnabled`: rung phản hồi khi ấn nút ảo (mặc định **BẬT**).
/// - `errorHapticEnabled`: rung cảnh báo khi nút ảo **không** tới game
///   (mặc định BẬT — nhưng độc lập với rung khi ấn).
///
/// Ghi chú: mọi tuỳ chọn đều **tuỳ chọn**, không ép buộc. Tắt rung thì phản
/// hồi thị giác (nút sáng + phình to) vẫn còn nguyên.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    /// Rung phản hồi khi ấn nút ảo.
    @Published var hapticsEnabled: Bool {
        didSet { save() }
    }

    /// Rung cảnh báo khi nút ảo không tới game (lỗi).
    @Published var errorHapticEnabled: Bool {
        didSet { save() }
    }

    private let fileURL: URL
    private var isLoading = false

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("GameHub", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("settings.json")

        // Đọc trước khi gán didSet → tránh ghi file lúc khởi tạo.
        var loaded = SettingsFile()
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(SettingsFile.self, from: data) {
            loaded = decoded
        }
        hapticsEnabled = loaded.hapticsEnabled
        errorHapticEnabled = loaded.errorHapticEnabled
    }

    private func save() {
        guard !isLoading else { return }
        let snapshot = SettingsFile(hapticsEnabled: hapticsEnabled,
                                    errorHapticEnabled: errorHapticEnabled)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Dữ liệu lưu trên đĩa.
    private struct SettingsFile: Codable {
        var hapticsEnabled: Bool = true
        var errorHapticEnabled: Bool = true
    }

    // MARK: - Haptic tiện ích

    /// Rung phản hồi khi ấn nút (nếu người dùng bật).
    static func impact(_ intensity: CGFloat = 0.75) {
        guard shared.hapticsEnabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: intensity)
    }

    /// Rung cảnh báo khi có lỗi (nếu người dùng bật).
    static func notifyError() {
        guard shared.errorHapticEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    /// Rung thành công (kiểm tra game OK).
    static func notifySuccess() {
        guard shared.errorHapticEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

// MARK: - Màn cài đặt

/// Màn cài đặt — mở từ nút bánh răng ở màn chính hoặc menu trong game.
struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var library = GameLibrary.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showingFolderPicker = false
    @State private var confirmingClearCovers = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                            .background(
                                LinearGradient(colors: [Theme.accent, Color(red: 0.7, green: 0.35, blue: 1.0)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Game Hub").font(.title3.weight(.bold))
                            Text(AppVersion.display).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    LabeledContent {
                        Text(library.gamesRoot?.lastPathComponent ?? "Chưa chọn")
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } label: {
                        Label("Thư mục", systemImage: "folder")
                    }
                    if !library.games.isEmpty {
                        LabeledContent {
                            Text("\(library.games.count) game · \(library.games.filter(\.isPlayable).count) chơi được")
                        } label: {
                            Label("Thư viện", systemImage: "square.grid.2x2")
                        }
                    }
                    Button {
                        showingFolderPicker = true
                    } label: {
                        Label(library.gamesRoot == nil ? "Chọn thư mục…" : "Đổi thư mục…",
                              systemImage: "folder.badge.gearshape")
                    }
                    Button {
                        library.refresh()
                    } label: {
                        Label(library.isScanning ? "Đang quét…" : "Quét lại thư viện",
                              systemImage: "arrow.clockwise")
                    }
                    .disabled(library.gamesRoot == nil || library.isScanning)
                } header: {
                    Text("Thư mục game")
                }

                Section {
                    toggleRow("Rung khi ấn nút", detail: "Phản hồi xúc giác mỗi lần bấm nút ảo",
                              symbol: "waveform", isOn: $settings.hapticsEnabled)
                    toggleRow("Rung cảnh báo lỗi", detail: "Rung kiểu báo lỗi khi nút ảo không tới được game",
                              symbol: "exclamationmark.triangle", isOn: $settings.errorHapticEnabled)
                } header: {
                    Text("Phản hồi")
                } footer: {
                    Text("Tắt rung vẫn giữ phản hồi thị giác: nút vẫn sáng trắng và phình to khi bấm.")
                }

                Section {
                    Button(role: .destructive) {
                        confirmingClearCovers = true
                    } label: {
                        Label("Xoá tất cả ảnh bìa đã chụp", systemImage: "photo.on.rectangle.angled")
                    }
                } header: {
                    Text("Ảnh bìa")
                } footer: {
                    Text("App tự chụp màn hình game lúc bạn thoát để làm ảnh bìa. Muốn tự đặt ảnh bìa: thêm file cover.jpg hoặc cover.png vào thư mục game.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Cài đặt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") { dismiss() }
                }
            }
            .fileImporter(isPresented: $showingFolderPicker,
                          allowedContentTypes: [.folder],
                          allowsMultipleSelection: false) { result in
                library.handleFolderPick(result)
            }
            .confirmationDialog("Xoá tất cả ảnh bìa đã chụp?", isPresented: $confirmingClearCovers,
                                titleVisibility: .visible) {
                Button("Xoá ảnh bìa", role: .destructive) { CoverStore.shared.removeAllSnapshots() }
            } message: {
                Text("Game sẽ dùng lại ảnh bìa tự động cho tới lần chơi sau.")
            }
        }
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
    }

    private func toggleRow(_ title: String, detail: String, symbol: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: symbol)
            }
        }
    }
}
