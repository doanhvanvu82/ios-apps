import SwiftUI

/// Cài đặt: sync ngay, trạng thái engine, log, thông tin pool.
struct SettingsView: View {
    @StateObject private var engine = SyncEngine.shared
    @StateObject private var accounts = AccountStore.shared
    @State private var logLines: [String] = []

    var body: some View {
        NavigationStack {
            List {
                Section("Đồng bộ") {
                    Button {
                        engine.syncNow()
                    } label: {
                        Label(engine.status.isWorking ? "Đang đồng bộ…" : "Đồng bộ ngay", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(engine.status.isWorking)
                    if let last = engine.lastSyncAt {
                        LabeledRow("Lần sync cuối", last.formatted(date: .abbreviated, time: .standard))
                    }
                    LabeledRow("Thao tác chờ", "\(engine.status.pendingCount)")
                }

                Section("Dung lượng pool") {
                    ForEach(accounts.accounts) { acc in
                        HStack {
                            Text(acc.email)
                                .font(.footnote)
                                .lineLimit(1)
                            Spacer()
                            if let limit = acc.quotaLimit, let usage = acc.quotaUsage {
                                Text("\(ByteFmt.string(limit - usage)) trống")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("…")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    if !accounts.accounts.isEmpty {
                        let free = accounts.accounts.compactMap(\.freeBytes).reduce(0, +)
                        Text("Tổng còn trống: \(ByteFmt.string(free))")
                            .font(.footnote.weight(.semibold))
                    }
                }

                Section {
                    NavigationLink {
                        LogView()
                    } label: {
                        Label("Nhật ký chẩn đoán", systemImage: "doc.text.magnifyingglass")
                    }
                } footer: {
                    Text("Log lưu ở Documents/Logs — cắm USB chạy toolkit/pull_app_logs.sh vn.vudv.mydrive để lấy về máy tính.")
                }

                Section("Về app") {
                    LabeledRow("Phiên bản", AppVersion.display)
                    LabeledRow("Chia nhỏ file", "≥ 256 MiB thành parts 256 MiB")
                }
            }
            .navigationTitle("Cài đặt")
        }
    }
}

/// Xem log ngay trong app.
struct LogView: View {
    @State private var lines: [String] = []

    var body: some View {
        List(lines.reversed(), id: \.self) { line in
            Text(line)
                .font(.system(size: 11, design: .monospaced))
        }
        .navigationTitle("Nhật ký")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        .refreshable { load() }
    }

    private func load() {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: AppLog.directory, includingPropertiesForKeys: nil) else { return }
        let logs = items.filter { $0.pathExtension == "log" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
        var all: [String] = []
        if let first = logs.first, let text = try? String(contentsOf: first, encoding: .utf8) {
            all = text.split(separator: "\n").map(String.init)
        }
        lines = Array(all.suffix(500))
    }
}

private struct LabeledRow: View {
    let label: String
    let value: String
    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }
    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .font(.footnote)
        }
    }
}
