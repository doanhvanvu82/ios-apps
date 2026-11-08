import Foundation

/// Loại thao tác trong hàng đợi.
enum JournalOp: Codable, Hashable {
    case uploadFile(path: String)          // file mới hoặc sửa (so sánh rev)
    case createFolder(path: String)
    case rename(from: String, to: String)
    case move(from: String, to: String)
    /// Xoá: UI remove node khỏi index trước rồi enqueue — snapshot đi kèm op
    /// (node gốc + toàn bộ node con) để engine biết phải trash những part nào
    /// trên Drive (op persist trong journal nên crash-safe).
    case delete(path: String, snapshot: TrashSnapshot?)
    /// Khôi phục từ "Đã xóa gần đây": untrash các part trên Drive
    /// (lúc xoá đã trash — FIFO journal đảm bảo untrash chạy sau trash).
    case restoreTrash(path: String, node: IndexNode)
}

/// Chụp toàn bộ cây bị xoá lúc người dùng xoá (index bị remove TRƯỚC khi op
/// chạy nên engine không đọc lại được từ index).
struct TrashSnapshot: Codable, Hashable {
    var root: IndexNode?
    var children: [String: IndexNode]
}

/// Một bản ghi thao tác.
struct JournalEntry: Codable, Hashable, Identifiable {
    var id: UUID
    var op: JournalOp
    var createdAt: Date
    var attempts: Int
    var lastError: String?

    init(op: JournalOp) {
        id = UUID()
        self.op = op
        createdAt = Date()
        attempts = 0
        lastError = nil
    }
}

/// Hàng đợi thao tác persist (Application Support/MyDrive.meta/journal.json).
/// Crash-safe: ghi journal trước khi thực hiện; SyncEngine duyệt tuần tự.
final class Journal: ObservableObject {
    static let shared = Journal()

    @Published private(set) var entries: [JournalEntry] = []

    private let fileURL: URL
    private let queue = DispatchQueue(label: "vn.vudv.mydrive.journal")

    private init() {
        _ = AppPaths.migrated
        try? FileManager.default.createDirectory(at: AppPaths.meta, withIntermediateDirectories: true)
        fileURL = AppPaths.meta.appendingPathComponent("journal.json")
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let list = try? JSONDecoder().decode([JournalEntry].self, from: data) else { return }
        entries = list
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// Đăng ký 1 thao tác (gọi TRƯỚC khi thay đổi local để đảm bảo không mất).
    func enqueue(_ op: JournalOp) {
        let entry = JournalEntry(op: op)
        queue.async { [weak self] in
            guard let self else { return }
            self.entries.append(entry)
            self.persist()
            self.publishCount()
        }
    }

    /// Đánh dấu entry xử lý xong (thành công → xoá khỏi hàng đợi).
    func complete(_ entry: JournalEntry) {
        queue.async { [weak self] in
            guard let self else { return }
            self.entries.removeAll { $0.id == entry.id }
            self.persist()
            self.publishCount()
        }
    }

    /// Ghi nhận lỗi + tăng attempts (giữ entry trong hàng đợi).
    func recordFailure(_ entry: JournalEntry, error: String) {
        queue.async { [weak self] in
            guard let self else { return }
            guard let idx = self.entries.firstIndex(where: { $0.id == entry.id }) else { return }
            self.entries[idx].attempts += 1
            self.entries[idx].lastError = String(error.prefix(300))
            self.persist()
            self.publishCount()
        }
    }

    /// @Published phải phát trên MAIN — SwiftUI đang quan sát Journal (băng
    /// trạng thái đọc count); mutate từ queue nền gây re-render sai luồng (UI đơ).
    private func publishCount() {
        let n = entries.count
        if Thread.isMainThread {
            objectWillChange.send()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.objectWillChange.send()
            }
        }
    }

    /// Lấy 1 snapshot entries để xử lý (SyncEngine duyệt).
    func pending() -> [JournalEntry] {
        queue.sync { entries }
    }

    var count: Int {
        queue.sync { entries.count }
    }
}
