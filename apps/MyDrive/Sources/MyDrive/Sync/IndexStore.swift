import Foundation

/// Một node trong chỉ mục (file hoặc folder).
struct IndexNode: Codable, Hashable {
    var name: String
    var isDirectory: Bool
    var size: Int64
    var modified: Date?
    /// Account chứa body file (file nhỏ/lớn đều là 1 "logical file" với parts).
    var parts: [FilePart]?
    /// Số hiệu phiên bản nội dung (tăng khi sửa file) — last-write-wins.
    var rev: Int
    /// Tên file/folder trên Drive cho folder; driveFileId của folder (nếu đã tạo).
    var driveFolderId: String?
}

/// Chỉ mục toàn cục: path → node. Persist index.json (Documents/.myd-meta/index.json)
/// và mirror lên MỌI account sau mỗi đợt sync thành công.
final class IndexStore: ObservableObject {
    static let shared = IndexStore()

    static let indexFileName = "index.json"
    /// appProperties key đánh dấu file index trên Drive.
    static let indexMarkerKey = "mydIndex"
    static let indexMarkerValue = "1"

    @Published private(set) var index: [String: IndexNode] = [:] {
        didSet { needsPush = true }
    }
    /// Số hiệu chỉ mục (tăng mỗi lần thay đổi nội dung) — so index nào mới nhất khi khôi phục.
    @Published private(set) var rev: Int = 0
    private var needsPush = false

    private let metaDir: URL
    private let fileURL: URL
    private let queue = DispatchQueue(label: "vn.vudv.mydrive.index")
    private let saveQueue = DispatchQueue(label: "vn.vudv.mydrive.index.save")
    private var pendingPersist: Persisted?
    private var persistScheduled = false
    /// KHÓA bảo vệ dictionary `index`: 6 worker song song (1.87) cùng mutate →
    /// data race trên Dictionary Swift không khóa = crash (EXC_BAD_ACCESS, đã
    /// gặp thật 08/11 khi đẩy 700 file). Mọi đọc/ghi dictionary phải qua lock.
    private let dictLock = NSLock()

    /// Đọc snapshot an toàn trong lock.
    private func withDict<T>(_ body: (inout [String: IndexNode]) -> T) -> T {
        dictLock.lock()
        defer { dictLock.unlock() }
        return body(&index)
    }

    private init() {
        _ = AppPaths.migrated
        metaDir = AppPaths.meta
        fileURL = metaDir.appendingPathComponent(Self.indexFileName)
        load()
    }

    // MARK: - Persist

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let state = try? JSONDecoder().decode(Persisted.self, from: data) else { return }
        index = state.nodes
        rev = state.rev
        needsPush = false
    }


    private struct Persisted: Codable {
        var nodes: [String: IndexNode]
        var rev: Int
    }

    /// Lưu index xuống đĩa — NỀN + coalesce: snapshot state NGAY (đồng bộ,
    /// rẻ — chỉ copy dictionary) rồi encode + ghi trên serial queue. Gọi hàng
    /// trăm lần liên tiếp (đổi tên thư mục nhiều file) không chặn main thread
    /// và chỉ ghi đĩa ~1 lần/0,2 giây (các lần sau gom chung).
    func save() {
        let state = withDict { Persisted(nodes: $0, rev: rev) }
        saveQueue.async { [weak self] in
            guard let self else { return }
            self.pendingPersist = state
            guard !self.persistScheduled else { return }
            self.persistScheduled = true
            self.saveQueue.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self, let s = self.pendingPersist else { return }
                self.pendingPersist = nil
                self.persistScheduled = false
                try? FileManager.default.createDirectory(at: self.metaDir, withIntermediateDirectories: true)
                if let data = try? JSONEncoder().encode(s) {
                    try? data.write(to: self.fileURL, options: .atomic)
                }
            }
        }
    }

    /// Ghi ngay (dùng khi app sắp vào nền — đảm bảo mọi thay đổi đã xuống đĩa).
    func saveNow() {
        let state = withDict { Persisted(nodes: $0, rev: rev) }
        try? FileManager.default.createDirectory(at: metaDir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: fileURL, options: .atomic)
        }
        saveQueue.sync { pendingPersist = nil }
    }

    /// Snapshot (dùng khi mirror lên Drive).
    func snapshot() -> (nodes: [String: IndexNode], rev: Int) {
        withDict { ($0, rev) }
    }

    /// Nạp index (khôi phục sau cài lại).
    func replaceAll(nodes: [String: IndexNode], rev: Int) {
        dictLock.lock()
        index = nodes
        self.rev = rev
        needsPush = false
        dictLock.unlock()
        save()
    }

    // MARK: - Thao tác

    /// Đánh dấu cần đẩy index lên Drive (được gọi bởi SyncEngine sau khi mirror).
    func markNeedsPush() { needsPush = true }
    var pendingPush: Bool { needsPush }

    /// Ghi node mới/cập nhật node (bump rev).
    func upsert(path: String, node: IndexNode) {
        dictLock.lock()
        index[path] = node
        rev += 1
        dictLock.unlock()
        save()
    }

    func remove(path: String) {
        dictLock.lock()
        index.removeValue(forKey: path)
        rev += 1
        dictLock.unlock()
        save()
    }

    /// Xoá cả cây (di chuyển/thuộc thư mục bị xoá).
    func removeTree(prefix: String) {
        dictLock.lock()
        let p = prefix + "/"
        for key in index.keys where key.hasPrefix(p) {
            index.removeValue(forKey: key)
        }
        rev += 1
        dictLock.unlock()
        save()
    }

    func node(at path: String) -> IndexNode? {
        dictLock.lock()
        defer { dictLock.unlock() }
        return index[path]
    }

    /// Tìm node file có cùng inode-ish: file đổi tên → path cũ bị remove, path mới upsert.
    /// Dùng để giữ driveFileId khi rename (SyncEngine xử lý).
    func allNodes() -> [(path: String, node: IndexNode)] {
        dictLock.lock()
        defer { dictLock.unlock() }
        return index.map { ($0.key, $0.value) }.sorted { $0.0 < $1.0 }
    }

    /// Cập nhật node giữ nguyên path (không bump rev — dùng khi sync engine
    /// cập nhật driveFileId sau khi upload; rev chỉ tăng khi nội dung người dùng thay đổi).
    func update(path: String, _ mutate: (inout IndexNode) -> Void) {
        var changed = false
        dictLock.lock()
        if var n = index[path] {
            mutate(&n)
            index[path] = n
            changed = true
        }
        dictLock.unlock()
        if changed { save() }
    }

    /// Đọc + mutate node nếu tồn tại (dùng cho callback nền — cùng ngữ nghĩa update).
    func withNode(at path: String, _ body: (inout IndexNode) -> Void) {
        update(path: path, body)
    }

    /// Toàn bộ keys.
    var keys: [String] {
        dictLock.lock()
        defer { dictLock.unlock() }
        return Array(index.keys)
    }

    // MARK: - Merge khi khôi phục

    /// Gộp index từ Drive (khi cài lại): chấp nhận nếu rev lớn hơn rev hiện tại.
    func mergeRemote(nodes: [String: IndexNode], remoteRev: Int) -> Bool {
        guard remoteRev > rev else { return false }
        replaceAll(nodes: nodes, rev: remoteRev)
        return true
    }

    /// Cập nhật 1 part của node (upload nền xong) — không bump rev.
    func updatePart(path: String, partIndex: Int, accountEmail: String, driveFileId: String) {
        update(path: path) { node in
            guard var parts = node.parts else { return }
            for i in parts.indices where parts[i].index == partIndex {
                parts[i].driveFileId = driveFileId
                parts[i].accountEmail = accountEmail
            }
            node.parts = parts
        }
    }
}
