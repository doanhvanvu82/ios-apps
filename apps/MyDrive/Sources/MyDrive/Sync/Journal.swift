import Foundation

/// Loại thao tác trong hàng đợi.
enum JournalOp: Codable, Hashable {
    case uploadFile(path: String)          // file mới hoặc sửa (so sánh rev)
    case createFolder(path: String)
    case rename(from: String, to: String)
    case move(from: String, to: String)
    /// Xoá: UI remove node khỏi index trước rồi enqueue — snapshot node
    /// (parts/placement) đi kèm op để engine biết phải trash những part nào
    /// trên Drive (op persist trong journal nên crash-safe).
    case delete(path: String, snapshot: IndexNode?)
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

/// Hàng đợi thao tác persist (Documents/.myd-meta/journal.json).
/// Crash-safe: ghi journal trước khi thực hiện; SyncEngine duyệt tuần tự.
final class Journal: ObservableObject {
    static let shared = Journal()

    @Published private(set) var entries: [JournalEntry] = []

    private let fileURL: URL
    private let queue = DispatchQueue(label: "vn.vudv.mydrive.journal")

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let metaDir = docs.appendingPathComponent(".myd-meta", isDirectory: true)
        try? FileManager.default.createDirectory(at: metaDir, withIntermediateDirectories: true)
        fileURL = metaDir.appendingPathComponent("journal.json")
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
        queue.async { [weak self] in
            guard let self else { return }
            self.entries.append(JournalEntry(op: op))
            self.persist()
        }
    }

    /// Đánh dấu entry xử lý xong (thành công → xoá khỏi hàng đợi).
    func complete(_ entry: JournalEntry) {
        queue.async { [weak self] in
            guard let self else { return }
            self.entries.removeAll { $0.id == entry.id }
            self.persist()
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
