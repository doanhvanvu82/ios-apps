import Foundation

/// "Đã xóa gần đây" — thùng rác cục bộ kiểu app Files: xóa chỉ chuyển dữ liệu
/// vào đây, giữ 30 ngày rồi mới dọn hẳn. Trong lúc đó khôi phục (về vị trí cũ,
/// untrash phần trên Drive) hoặc xóa ngay được.
///
/// Nội dung file nằm ở Application Support/MyDrive.trash/ (Files app không thấy —
/// vẫn nằm trong sandbox để restore sau update app qua Ksign).
/// Metadata persist ở MyDrive.meta/trash.json — update app qua Ksign giữ nguyên.
final class TrashStore: ObservableObject {
    static let shared = TrashStore()

    /// Sau 30 ngày tự xóa hẳn.
    static let retentionInterval: TimeInterval = 30 * 24 * 3600

    /// Một mục đã xóa (file hoặc cả thư mục). Thư mục chỉ lưu 1 entry gốc
    /// (đường dẫn con giữ tương đối để khôi phục đúng chỗ).
    struct Item: Codable, Identifiable, Hashable {
        var id: UUID
        /// Đường dẫn logic cũ (vd "Ảnh/a.jpg") — nơi khôi phục sẽ trả về.
        var originalPath: String
        var node: IndexNode
        /// Con của thư mục (path tương đối gốc → node). Rỗng với file.
        var children: [String: IndexNode]
        var deletedAt: Date

        var daysLeft: Int {
            max(0, Int(ceil((Self.retentionDeadline(deletedAt).timeIntervalSinceNow) / 86400)))
        }

        static func retentionDeadline(_ deletedAt: Date) -> Date {
            deletedAt.addingTimeInterval(TrashStore.retentionInterval)
        }
    }

    @Published private(set) var items: [Item] = []

    private let fileURL: URL
    private let trashDir: URL

    private init() {
        _ = AppPaths.migrated
        fileURL = AppPaths.meta.appendingPathComponent("trash.json")
        trashDir = AppPaths.trash
        try? FileManager.default.createDirectory(at: trashDir, withIntermediateDirectories: true)
        load()
        purgeExpired()
    }

    // MARK: - Persist

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let list = try? JSONDecoder().decode([Item].self, from: data) else { return }
        items = list
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    // MARK: - Đưa vào thùng rác (FileSystemStore.remove gọi TRƯỚC khi xóa mirror)

    /// Node đã đăng ký với originalPath (mới nhất).
    func node(forOriginalPath path: String) -> IndexNode? {
        items.last { $0.originalPath == path }?.node
    }

    /// Toàn bộ node con đã đăng ký với originalPath (mới nhất).
    func children(forOriginalPath path: String) -> [String: IndexNode] {
        items.last { $0.originalPath == path }?.children ?? [:]
    }

    /// Chụp node từ index, chuyển dữ liệu mirror vào .myd-trash (nếu có trên đĩa)
    /// rồi đăng ký entry. Engine sau đó trash các part trên Drive (op delete);
    /// khôi phục sẽ untrash lại (op restoreTrash — chạy sau nhờ FIFO journal).
    func stash(path: String) {
        let index = IndexStore.shared
        let root = index.node(at: path)
        let prefix = path + "/"
        var children: [String: IndexNode] = [:]
        for (childPath, childNode) in index.allNodes() where childPath.hasPrefix(prefix) {
            children[String(childPath.dropFirst(prefix.count))] = childNode
        }

        let item = Item(
            id: UUID(),
            originalPath: path,
            node: root ?? IndexNode(
                name: path.components.last ?? path, isDirectory: false, size: 0,
                modified: Date(), parts: nil, rev: 1, driveFolderId: nil
            ),
            children: children,
            deletedAt: Date()
        )

        let srcURL = FileSystemStore.shared.url(for: path.components)
        if FileManager.default.fileExists(atPath: srcURL.path) {
            let dstURL = trashDir.appendingPathComponent(item.id.uuidString)
            try? FileManager.default.removeItem(at: dstURL)
            do {
                try FileManager.default.moveItem(at: srcURL, to: dstURL)
            } catch {
                // Không stash được dữ liệu vẫn giữ entry — phần trên Drive còn trash/khôi phục được.
                AppLog.log("trash", "❌ Không chuyển được vào thùng rác: \(path) — \(error.localizedDescription)")
            }
        }

        // Đồng bộ trên main để caller (deleteEntry) đọc items ngay sau đó thấy entry.
        if Thread.isMainThread {
            items.insert(item, at: 0)
            persist()
        } else {
            DispatchQueue.main.sync { [weak self] in
                guard let self else { return }
                self.items.insert(item, at: 0)
                self.persist()
            }
        }
    }

    // MARK: - Thao tác từ UI

    /// Khôi phục về vị trí cũ: trả dữ liệu stash về mirror, đăng ký lại index
    /// và các op (upload part thiếu, untrash part đã có — engine xử lý).
    func restore(_ item: Item) {
        let store = FileSystemStore.shared
        let index = IndexStore.shared
        let journal = Journal.shared

        // 1) Vị trí đích: originalPath, tránh đè lên file/thư mục cùng tên đang có.
        var comps = item.originalPath.components
        if let last = comps.last {
            let parent = Array(comps.dropLast())
            var name = last
            while store.exists(at: parent + [name]) || index.node(at: (parent + [name]).joined(separator: "/")) != nil {
                name = uniquedName(for: last, in: parent)
            }
            comps = parent + [name]
        }
        let destPath = comps.joined(separator: "/")

        // 2) Trả dữ liệu về mirror. Thiếu dữ liệu stash (file chưa kịp tải về lúc
        //    xóa) vẫn khôi phục được phần trên Drive — chỉ bỏ qua bước move.
        let srcURL = trashDir.appendingPathComponent(item.id.uuidString)
        if FileManager.default.fileExists(atPath: srcURL.path) {
            let dstURL = store.url(for: comps)
            do {
                try FileManager.default.createDirectory(at: dstURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: dstURL.path) {
                    try FileManager.default.removeItem(at: dstURL)
                }
                try FileManager.default.moveItem(at: srcURL, to: dstURL)
            } catch {
                AppLog.log("trash", "❌ Không khôi phục được \(item.originalPath): \(error.localizedDescription)")
                return
            }
        }

        // 3) Đăng ký lại index + journal. Parts giữ nguyên placement → part đã có
        //    trên Drive chỉ cần untrash; part thiếu → op uploadFile tự điền.
        var node = item.node
        node.name = comps.last ?? node.name
        index.upsert(path: destPath, node: node)
        if node.isDirectory {
            for (childRel, childNode) in item.children {
                var c = childNode
                c.name = childRel.components.last ?? c.name
                index.upsert(path: destPath + "/" + childRel, node: c)
            }
        }
        if node.isDirectory {
            journal.enqueue(.createFolder(path: destPath))
            for (childRel, childNode) in item.children where childNode.isDirectory {
                journal.enqueue(.createFolder(path: destPath + "/" + childRel))
            }
        }
        for (childRel, childNode) in item.children where !childNode.isDirectory {
            journal.enqueue(.uploadFile(path: destPath + "/" + childRel))
        }
        if !node.isDirectory {
            journal.enqueue(.uploadFile(path: destPath))
        }
        // Cuối cùng: untrash các part đã trash lúc xóa (FIFO journal đảm bảo
        // op này chạy sau các op upload phía trên).
        journal.enqueue(.restoreTrash(path: destPath, node: node))

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.items.removeAll { $0.id == item.id }
            self.persist()
        }
        store.notifyChanged()
        SyncEngine.triggerSyncPublic()
        AppLog.log("trash", "♻️ Đã khôi phục \(item.originalPath) → \(destPath)")
    }

    /// Xóa hẳn: bỏ entry + dữ liệu stash. Part trên Drive đã bị trash lúc xóa
    /// (Drive cũng tự dọn thùng rác của nó sau 30 ngày) — không đụng lại.
    func purge(_ item: Item) {
        try? FileManager.default.removeItem(at: trashDir.appendingPathComponent(item.id.uuidString))
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.items.removeAll { $0.id == item.id }
            self.persist()
        }
        AppLog.log("trash", "🗑 Xóa hẳn \(item.originalPath)")
    }

    /// Dọn các mục quá 30 ngày (gọi lúc mở app và khi mở màn thùng rác).
    func purgeExpired() {
        let deadline = Date().addingTimeInterval(-Self.retentionInterval)
        for item in items where item.deletedAt < deadline {
            purge(item)
        }
    }

    /// Dọn sạch (nút trong UI).
    func purgeAll() {
        for item in items {
            try? FileManager.default.removeItem(at: trashDir.appendingPathComponent(item.id.uuidString))
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.items.removeAll()
            self.persist()
        }
        AppLog.log("trash", "🗑 Đã dọn sạch thùng rác")
    }

    private func uniquedName(for name: String, in parent: [String]) -> String {
        let store = FileSystemStore.shared
        let index = IndexStore.shared
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        for i in 2...999 {
            let candidate = ext.isEmpty ? "\(base) (\(i))" : "\(base) (\(i)).\(ext)"
            let p = (parent + [candidate]).joined(separator: "/")
            if !store.exists(at: parent + [candidate]) && index.node(at: p) == nil {
                return candidate
            }
        }
        return UUID().uuidString + "." + ext
    }
}
