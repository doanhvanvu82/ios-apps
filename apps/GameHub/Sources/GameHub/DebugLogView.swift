import SwiftUI

/// Màn xem log của app — dùng để chẩn đoán khi game không chạy (màn đen,
/// treo tải…) ngay trên iPhone, không cần cắm máy tính.
///
/// Có `game` thì mặc định xem log riêng của game đó (đang chơi: cập nhật trực
/// tiếp; đã thoát: đọc tệp `logs/games/<tên>.log`), chuyển được sang log toàn app.
struct DebugLogView: View {
    /// Tên thư mục game (khoá tệp log) + tên hiển thị.
    var game: (folder: String, title: String)?

    @ObservedObject private var log = AppLog.shared
    @Environment(\.dismiss) private var dismiss
    @State private var scope: Scope = .game
    @State private var savedGameLines: [String] = []
    @State private var level: LevelFilter = .all
    @State private var query = ""
    @State private var sendStatus: String?
    @State private var sending = false

    enum LevelFilter: String, CaseIterable {
        case all = "Tất cả", errors = "Lỗi", warnings = "Cảnh báo"
    }

    enum Scope: String, CaseIterable {
        case game = "Game này", app = "Toàn app"
    }

    private var showsGame: Bool { game != nil && scope == .game }

    /// Dòng log của phạm vi đang xem — nguồn chung cho danh sách và các nút.
    private var sourceLines: [String] {
        guard showsGame, let game else { return log.lines }
        return log.activeGame == game.folder ? log.gameLines : savedGameLines
    }

    private var entries: [LogEntry] {
        LogEntry.group(sourceLines).filter { entry in
            let levelOK: Bool
            switch level {
            case .all: levelOK = true
            case .errors: levelOK = entry.icon == "❌"
            case .warnings: levelOK = entry.icon == "⚠️"
            }
            return levelOK && (query.isEmpty || entry.message.localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if game != nil {
                    Picker("Phạm vi", selection: $scope) {
                        ForEach(Scope.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                }
                Picker("Mức", selection: $level) {
                    ForEach(LevelFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(entries) { entry in
                                LogRow(entry: entry).id(entry.id)
                            }
                        }
                        .padding(8)
                    }
                    .background(Color.black)
                    .onAppear {
                        if let game { savedGameLines = log.savedLines(for: game.folder) }
                        if let last = entries.last { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                    .onChange(of: scope) { _, _ in
                        if let last = entries.last { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Tìm trong log")
            .navigationTitle(showsGame ? (game?.title ?? "Log") : "Log chẩn đoán")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Đóng") { dismiss() }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    ShareLink(item: sourceLines.joined(separator: "\n")) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Chia sẻ log")

                    Button {
                        sendToComputer()
                    } label: {
                        Image(systemName: sending ? "ellipsis" : "desktopcomputer")
                    }
                    .disabled(sending)
                    .accessibilityLabel("Gửi về máy tính")

                    Button {
                        UIPasteboard.general.string = sourceLines.joined(separator: "\n")
                        AppLog.ok("Đã copy log vào clipboard")
                        AppSettings.notifySuccess()
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .accessibilityLabel("Copy log")

                    Button(role: .destructive) {
                        if showsGame, let game {
                            log.clearGameLog(game.folder)
                            savedGameLines = []
                        } else {
                            log.clear()
                        }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("Xoá log")
                }
            }
            .overlay(alignment: .bottom) {
                if let sendStatus {
                    Text(sendStatus)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 20)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .preferredColorScheme(.dark)
        }
    }

    /// Đưa đúng nội dung nút Copy vào clipboard máy tính (toolkit/dev_server.py,
    /// địa chỉ do build.sh ghi vào Info.plist `GameHubDevServer`).
    private func sendToComputer() {
        guard let base = Bundle.main.object(forInfoDictionaryKey: "GameHubDevServer") as? String,
              let url = URL(string: base + "/clipboard") else {
            showStatus("❌ App chưa có địa chỉ máy tính (build lại bằng build.sh)")
            return
        }
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.httpMethod = "POST"
        request.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(sourceLines.joined(separator: "\n").utf8)
        sending = true
        Task {
            let message: String
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                message = code == 200 ? "✅ Đã gửi về máy tính" : "❌ Máy tính trả lỗi HTTP \(code)"
            } catch {
                message = "❌ Không tới được máy tính: \(error.localizedDescription)"
            }
            sending = false
            if message.hasPrefix("✅") { AppSettings.notifySuccess() } else { AppSettings.notifyError() }
            showStatus(message)
        }
    }

    private func showStatus(_ text: String) {
        withAnimation(Theme.spring) { sendStatus = text }
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            withAnimation(Theme.spring) { if sendStatus == text { sendStatus = nil } }
        }
    }
}

/// Một mục log đã gộp: dòng chính + các dòng `At:` đi kèm, lặp `count` lần liên tiếp.
struct LogEntry: Identifiable {
    let id: Int
    let time: String
    let icon: String
    var message: String
    var count = 1

    /// 1. Ghép dòng `JS:    At: …` (vị trí lỗi của Godot) vào mục ngay trước.
    /// 2. Gộp các mục liên tiếp giống hệt nhau (chỉ khác giờ) thành 1 mục `×N`.
    ///
    /// Phải ghép trước khi gộp: spam lỗi Godot là cặp ERROR/At xen kẽ nhau,
    /// từng dòng riêng lẻ không bao giờ lặp liên tiếp.
    static func group(_ lines: [String]) -> [LogEntry] {
        var joined: [LogEntry] = []
        for line in lines {
            let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
            let hasPrefix = parts.count == 3 && parts[0].count == 8 && parts[0].contains(":")
            let message = hasPrefix ? String(parts[2]) : line
            let isLocation = message.hasPrefix("JS:")
                && message.dropFirst(3).trimmingCharacters(in: .whitespaces).hasPrefix("At:")
            if isLocation, !joined.isEmpty {
                joined[joined.count - 1].message += "\n" + message
                continue
            }
            joined.append(LogEntry(id: 0,
                                   time: hasPrefix ? String(parts[0]) : "",
                                   icon: hasPrefix ? String(parts[1]) : "",
                                   message: message))
        }

        var result: [LogEntry] = []
        for entry in joined {
            if let last = result.last, last.icon == entry.icon, last.message == entry.message {
                result[result.count - 1].count += 1
            } else {
                result.append(LogEntry(id: result.count, time: entry.time, icon: entry.icon, message: entry.message))
            }
        }
        return result
    }
}

private struct LogRow: View {
    let entry: LogEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(entry.time)
                .foregroundStyle(.white.opacity(0.4))
            Text(entry.icon + " " + entry.message)
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, alignment: .leading)
            if entry.count > 1 {
                Text("×\(entry.count)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(color.opacity(0.2), in: Capsule())
                    .foregroundStyle(color)
            }
        }
        .font(.system(size: 11, design: .monospaced))
        .textSelection(.enabled)
    }

    private var color: Color {
        switch entry.icon {
        case "❌": return .red
        case "⚠️": return .yellow
        case "✅": return .green
        default: return .white.opacity(0.85)
        }
    }
}
