import Foundation
import UIKit

/// Trạng thái sync hiển thị trên băng trạng thái.
struct SyncStatus: Equatable {
    enum Phase: Equatable {
        case idle
        case working(String)      // mô tả đang làm gì
        case error(String)
    }
    var phase: Phase = .idle
    /// Số op còn trong hàng đợi.
    var pendingCount: Int = 0
    /// Các account cần đăng nhập lại.
    var needsReauth: [String] = []

    var text: String {
        switch phase {
        case .idle:
            return pendingCount > 0 ? "\(pendingCount) thao tác chờ đồng bộ" : "Đã đồng bộ"
        case let .working(desc):
            return desc + (pendingCount > 0 ? " — còn \(pendingCount)" : "")
        case let .error(msg):
            return msg
        }
    }

    var isWorking: Bool {
        if case .working = phase { return true }
        return false
    }
}

/// Engine đồng bộ: đẩy Journal lên Drive, kéo file thiếu từ Drive về mirror,
/// mirror index.json lên mọi account, retry/backoff, chạy nền khi foreground.
final class SyncEngine: ObservableObject {
    static let shared = SyncEngine()

    @Published var status = SyncStatus()
    /// Thời điểm sync gần nhất thành công.
    @Published var lastSyncAt: Date?

    private let accounts = AccountStore.shared
    private let store = FileSystemStore.shared
    private let index = IndexStore.shared
    private let journal = Journal.shared
    private let placement = PlacementService()

    private var syncTask: Task<Void, Never>?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var debounceTimer: Timer?

    private init() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(appWillResignActive),
            name: UIApplication.willResignActiveNotification, object: nil
        )
    }

    // MARK: - Vòng đời app

    @objc private func appDidBecomeActive() {
        // File mới kéo vào mirror qua USB File Sharing lúc app không chạy:
        // UI đọc đĩa lúc vẽ nên phải báo đổi ngay để danh sách quét lại,
        // không chờ sync (debounce 2s) hay phải tạo thư mục mới.
        FileSystemStore.shared.notifyChanged()
        InboxImporter.processInbox()
        triggerSync()
    }

    @objc private func appWillResignActive() {
        // Hoàn tất batch đang chạy trong nền (iOS cho ~30 giây).
        if syncTask != nil {
            backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "MyDriveSync") { [weak self] in
                guard let self else { return }
                UIApplication.shared.endBackgroundTask(self.backgroundTaskID)
                self.backgroundTaskID = .invalid
            }
        }
    }

    // MARK: - Trigger

    /// Yêu cầu sync (debounce 2 giây để gom nhiều thao tác liên tiếp).
    func triggerSync() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.debounceTimer?.invalidate()
            self.debounceTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
                self?.startSync()
            }
        }
    }

    /// Sync ngay (nút ở Settings / pull-to-refresh).
    func syncNow() {
        DispatchQueue.main.async { [weak self] in
            self?.debounceTimer?.invalidate()
            self?.startSync()
        }
    }

    // MARK: - API tĩnh cho code không giữ singleton (InboxImporter, AccountsView)

    static func triggerSyncPublic() {
        shared.triggerSync()
    }

    static func syncNowPublic() {
        shared.syncNow()
    }

    private func startSync() {
        guard syncTask == nil else { return }
        guard !accounts.accounts.isEmpty else { return }
        syncTask = Task { [weak self] in
            await self?.runSync()
            await MainActor.run { [weak self] in
                self?.syncTask = nil
                self?.endBackgroundTaskIfNeeded()
            }
        }
    }

    private func endBackgroundTaskIfNeeded() {
        if backgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }
    }

    private func setPhase(_ phase: SyncStatus.Phase) {
        Task { @MainActor in
            self.status.phase = phase
            self.status.pendingCount = journal.count
            self.status.needsReauth = accounts.accounts.filter(\.needsReauth).map(\.email)
        }
    }

    // MARK: - Vòng sync chính

    private func runSync() async {
        await setPhase(.working("Đang đồng bộ…"))

        // 0) Đảm bảo mọi account có thư mục MyDrive gốc.
        let rootIDs = await ensureRootFolders()
        guard !rootIDs.isEmpty else {
            await setPhase(.error("Không đăng nhập được account nào — vào tab Tài khoản."))
            return
        }

        // 1) KHÔI PHỤC: nếu index rỗng local nhưng Drive có index (cài lại) → nạp.
        await restoreIndexIfNeeded(rootIDs: rootIDs)

        // 2) Đẩy các op trong Journal (mọi thay đổi người dùng).
        await processJournal(rootIDs: rootIDs)

        // 3) Kéo file thiếu (file có trong index nhưng mirror chưa có — cài lại).
        await pullMissingFiles()

        // 3.5) Nhận nuôi file có sẵn trong mirror nhưng chưa có trong index
        //      (kéo thả qua USB File Sharing / index bị mất).
        await adoptOrphanLocalFiles()

        // 4) Mirror index.json lên MỌI account.
        await mirrorIndex(rootIDs: rootIDs)

        await setPhase(.idle)
        await MainActor.run { self.lastSyncAt = Date() }
    }

    /// Tạo/tìm thư mục MyDrive gốc trên từng account → [email: folderID].
    private func ensureRootFolders() async -> [String: String] {
        var result: [String: String] = [:]
        for acc in accounts.accounts where !acc.needsReauth {
            guard let client = accounts.client(for: acc.email) else { continue }
            do {
                let folder = try await client.ensureRootFolder()
                result[acc.email] = folder.id
                AppLog.log("sync", "✅ Thư mục MyDrive sẵn sàng trên \(acc.email): \(folder.id)")
            } catch {
                AppLog.log("sync", "❌ Không tạo được thư mục MyDrive trên \(acc.email): \(error.localizedDescription)")
            }
        }
        return result
    }

    // MARK: - Đẩy Journal

    private func processJournal(rootIDs: [String: String]) async {
        let entries = journal.pending()
        guard !entries.isEmpty else { return }
        AppLog.log("sync", "▶️ Đẩy \(entries.count) thao tác…")

        for entry in entries {
            guard !Task.isCancelled else { return }
            do {
                try await processEntry(entry, rootIDs: rootIDs)
                journal.complete(entry)
                await setPhase(.working("Đã đẩy \(entry.op.describe)"))
            } catch let err as DriveError {
                switch err {
                case .quotaExceeded:
                    // Account đầy — op upload sẽ tự chọn account khác trong lần retry.
                    journal.recordFailure(entry, error: err.localizedDescription)
                    await setPhase(.working("Account đầy — thử account khác…"))
                    try? await processEntryRetryOtherAccount(entry, rootIDs: rootIDs)
                case .invalidGrant:
                    journal.recordFailure(entry, error: err.localizedDescription)
                    await setPhase(.error("Account cần đăng nhập lại — vào tab Tài khoản."))
                    // Không retry nữa — dừng cả vòng (các op sau cũng sẽ fail).
                    return
                case .cancelled:
                    journal.recordFailure(entry, error: err.localizedDescription)
                default:
                    journal.recordFailure(entry, error: err.localizedDescription)
                    AppLog.log("sync", "⚠️ Op \(entry.op.describe) lỗi: \(err.localizedDescription)")
                }
            } catch {
                journal.recordFailure(entry, error: error.localizedDescription)
                AppLog.log("sync", "⚠️ Op \(entry.op.describe) lỗi: \(error.localizedDescription)")
            }
        }
    }

    /// Xử lý 1 entry.
    private func processEntry(_ entry: JournalEntry, rootIDs: [String: String]) async throws {
        switch entry.op {
        case let .uploadFile(path):
            try await uploadFile(path: path)
        case let .createFolder(path):
            try await createFolder(path: path, rootIDs: rootIDs)
        case let .rename(from, to):
            try await renameOrMove(from: from, to: to, rootIDs: rootIDs)
        case let .move(from, to):
            try await renameOrMove(from: from, to: to, rootIDs: rootIDs)
        case let .delete(path, snapshot):
            try await deleteFile(path: path, snapshot: snapshot)
        case let .restoreTrash(path, node):
            try await restoreTrashed(path: path, node: node)
        }
    }

    /// Retry op upload sang account khác khi account cũ đầy.
    private func processEntryRetryOtherAccount(_ entry: JournalEntry, rootIDs: [String: String]) async throws {
        if case let .uploadFile(path) = entry.op {
            // Xoá placement cũ trong index để upload lại từ đầu.
            index.update(path: path) { node in
                node.parts = nil
            }
            try await uploadFile(path: path)
            journal.complete(entry)
        }
    }

    // MARK: - Xóa / khôi phục (Đã xóa gần đây)

    /// Xóa: trash các part của root + con trên Drive (thùng rác Drive giữ 30 ngày,
    /// khớp với thùng rác local — khôi phục sẽ untrash lại). Op không kèm snapshot
    /// (luồng xóa mới) → đọc từ TrashStore — dữ liệu local đã chuyển vào đó.
    private func deleteFile(path: String, snapshot: TrashSnapshot?) async throws {
        guard let node = snapshot?.root ?? TrashStore.shared.node(forOriginalPath: path) else { return }
        try await trashParts(of: node)
        let children = snapshot?.children.isEmpty == false
            ? snapshot!.children
            : TrashStore.shared.children(forOriginalPath: path)
        for (_, child) in children where !child.isDirectory {
            try await trashParts(of: child)
        }
    }

    private func trashParts(of node: IndexNode) async throws {
        guard let parts = node.parts else { return }
        for part in parts {
            guard let partID = part.driveFileId,
                  let client = accounts.client(for: part.accountEmail) else { continue }
            try? await client.trash(id: partID)   // trash, không delete hẳn
        }
    }

    /// Khôi phục từ "Đã xóa gần đây": untrash các part đã trash lúc xóa.
    /// Part chưa upload (driveFileId nil) bỏ qua — op uploadFile đi trước trong
    /// journal sẽ upload mới từ mirror. Part 404 (bị Drive dọn) → upload lại.
    /// Node trong index đã do UI upsert khi khôi phục — giữ nguyên.
    private func restoreTrashed(path: String, node: IndexNode) async throws {
        guard let parts = node.parts else { return }
        for part in parts {
            guard let partID = part.driveFileId,
                  let client = accounts.client(for: part.accountEmail) else { continue }
            do {
                try await client.untrash(id: partID)
                AppLog.log("sync", "♻️ Untrash part \(part.index) của \(node.name)")
            } catch let err as DriveError {
                if case .http(404, _, _) = err {
                    // Part bị dọn khỏi thùng rác (quá 30 ngày) → upload lại từ mirror.
                    index.update(path: path) { current in
                        current.parts = current.parts?.map { p in
                            var q = p
                            if q.index == part.index { q.driveFileId = nil }
                            return q
                        }
                    }
                    try await uploadFile(path: path)
                } else {
                    throw err
                }
            }
        }
    }

    // MARK: - Upload file (điều phối multi-account)

    private func uploadFile(path: String) async throws {
        let store = self.store
        guard let size = store.fileSize(at: path.components) else {
            AppLog.log("sync", "⚠️ File không tồn tại ở mirror: \(path) — bỏ qua")
            return
        }
        let fileName = path.components.last ?? "file"

        // 1) Nếu chưa có placement → đặt account(s) theo dung lượng.
        if index.node(at: path) == nil {
            let partsPlan = Chunker.planParts(size: size)
            var placed = await placement.place(parts: partsPlan)
            for i in placed.indices {
                placed[i].remoteName = Chunker.partName(fileName: fileName, index: placed[i].index)
            }
            let node = IndexNode(name: fileName, isDirectory: false, size: size, modified: Date(), parts: placed, rev: 1, driveFolderId: nil)
            index.upsert(path: path, node: node)
        }

        // 2) Upload từng part chưa xong (var parts — cập nhật sau mỗi part).
        guard var parts = index.node(at: path)?.parts else { return }
        for (i, part) in parts.enumerated() {
            guard part.driveFileId == nil else { continue }
            guard part.accountEmail != "" else {
                // Không account nào đủ chỗ → ném lỗi để vòng sau thử lại (người dùng thêm account).
                throw DriveError.quotaExceeded
            }
            guard let client = accounts.client(for: part.accountEmail) else {
                // Account chứa part bị xoá/reauth → đặt lại part này sang account khác.
                if let newAcc = await placement.pickAccount(for: part.size, excluding: []),
                   let newClient = accounts.client(for: newAcc.email) {
                    parts[i].accountEmail = newAcc.email
                    index.update(path: path) { $0.parts = parts }
                    continue
                }
                throw DriveError.quotaExceeded
            }

            await setPhase(.working("Đang tải lên \(fileName) (phần \(i + 1)/\(parts.count))…"))

            // Folder đích trên account (cây thư mục như path).
            let folderPath = Array(path.components.dropLast())
            let parentID: String
            if folderPath.isEmpty {
                parentID = try await client.ensureRootFolder().id
            } else {
                parentID = try await client.ensureFolderPath(folderPath, under: try await client.ensureRootFolder().id).id
            }

            let props = [
                "mydFileId": path,                       // path logic — khôi phục được
                "mydPartIndex": "\(part.index)",
                "mydRev": "\(index.node(at: path)?.rev ?? 1)",
            ]

            let driveFile: DriveFile
            if part.size < 5 * 1024 * 1024 {
                let data = try store.readData(at: path.components)
                // Part đơn của file nhỏ: data trọn file.
                driveFile = try await client.uploadSmall(data: data, name: part.remoteName, parentID: parentID, appProperties: props, existingID: part.driveFileId)
            } else {
                // Part lớn: upload theo range (tạo temp file chứa riêng phần này).
                let partURL = store.tmpURL.appendingPathComponent("part-\(UUID().uuidString)")
                let offset = Int64(part.index) * Chunker.partSize
                let rangeData = try Chunker.readRange(from: store.url(for: path.components), offset: offset, length: part.size)
                try rangeData.write(to: partURL, options: .atomic)
                driveFile = try await client.uploadResumable(fileURL: partURL, name: part.remoteName, parentID: parentID, appProperties: props)
                try? FileManager.default.removeItem(at: partURL)
            }

            // Part này từng bị trash lúc xóa (khôi phục sau) — PATCH trên file
            // trashed không kéo nó ra khỏi thùng rác → untrash tường minh.
            if let existingID = part.driveFileId {
                do {
                    if try await client.get(id: existingID).trashed == true {
                        try await client.untrash(id: existingID)
                    }
                } catch {
                    AppLog.log("sync", "⚠️ Không kiểm tra được trạng thái trash của part \(part.index): \(error.localizedDescription)")
                }
            }

            parts[i].driveFileId = driveFile.id
            index.update(path: path) { $0.parts = parts }
            AppLog.log("sync", "✅ Part \(part.index) của \(fileName) → \(part.accountEmail) (\(driveFile.id))")
        }

        // 3) Upload xong mọi part → cập nhật node.
        index.update(path: path) { n in
            n.parts = parts
        }
    }

    // MARK: - Tạo folder / rename / move / delete

    private func createFolder(path: String, rootIDs: [String: String]) async throws {
        let comps = path.components
        guard let last = comps.last else { return }
        // Tạo trên account đang active (folder không tốn dung lượng).
        guard let activeEmail = accounts.activeEmail ?? rootIDs.keys.first,
              let client = accounts.client(for: activeEmail),
              let rootID = rootIDs[activeEmail] else { throw DriveError.noToken }

        let folderPath = Array(comps.dropLast())
        let parent = try await client.ensureFolderPath(folderPath, under: rootID)
        let folder = try await client.ensureFolderPath([last], under: parent.id)
        index.update(path: path) { node in
            node.driveFolderId = folder.id
        }
    }

    private func renameOrMove(from: String, to: String, rootIDs: [String: String]) async throws {
        // UI đã di chuyển node trong index sang path mới TRƯỚC khi op này chạy;
        // đọc node ở path mới (path cũ chỉ dùng để đổi tên part trên Drive).
        guard var node = index.node(at: to) ?? index.node(at: from) else { return }
        let wasFolder = node.isDirectory

        if wasFolder {
            // Folder: tạo lại cây trên account active (folder không tốn dung lượng).
            guard let activeEmail = accounts.activeEmail ?? rootIDs.keys.first,
                  let client = accounts.client(for: activeEmail),
                  let rootID = rootIDs[activeEmail] else { throw DriveError.noToken }
            let parentComps = Array(to.components.dropLast())
            let parent = try await client.ensureFolderPath(parentComps, under: rootID)
            let folder = try await client.ensureFolderPath([to.components.last ?? node.name], under: parent.id)
            index.update(path: to) { n in
                n.driveFolderId = folder.id
            }
            index.remove(path: from)
        } else {
            // File: PATCH metadata từng part (đổi tên/đổi thư mục trên account chứa nó).
            if let parts = node.parts {
                for part in parts {
                    guard let partID = part.driveFileId,
                          let client = accounts.client(for: part.accountEmail) else { continue }
                    let newFolderComps = Array(to.components.dropLast())
                    // Part nằm trên account chứa nó: đảm bảo cây thư mục tồn tại trên account đó.
                    let rootOnPartAccount = try await client.ensureRootFolder()
                    let newParent = newFolderComps.isEmpty ? rootOnPartAccount : try await client.ensureFolderPath(newFolderComps, under: rootOnPartAccount.id)
                    let newName = Chunker.partName(fileName: to.components.last ?? node.name, index: part.index)
                    _ = try await client.updateMetadata(id: partID, name: newName, addParents: newParent.id, removeParents: "root")
                }
            }
            // Node đã ở path mới (UI upsert) — chỉ đảm bảoxoá node cũ nếu còn.
            index.remove(path: from)
        }
    }

    private func deleteFile(path: String, snapshot: IndexNode?) async throws {
        // UI remove node khỏi index TRƯỚC khi op chạy → snapshot node đi kèm op;
        // snapshot nil (op cũ) thì thử đọc path.
        guard let node = snapshot ?? index.node(at: path) else { return }
        if let parts = node.parts {
            for part in parts {
                guard let partID = part.driveFileId,
                      let client = accounts.client(for: part.accountEmail) else { continue }
                try? await client.trash(id: partID)   // trash, không delete hẳn
            }
        }
        if node.isDirectory {
            // Con của folder: xoá luôn node con + trash part của chúng
            // (snapshot chỉ có node gốc — con lấy từ index trước khi removeTree).
            let prefix = path + "/"
            for (childPath, childNode) in index.allNodes() where childPath.hasPrefix(prefix) {
                if let childParts = childNode.parts {
                    for part in childParts {
                        guard let partID = part.driveFileId,
                              let client = accounts.client(for: part.accountEmail) else { continue }
                        try? await client.trash(id: partID)
                    }
                }
                index.remove(path: childPath)
            }
            index.removeTree(prefix: path)
        }
    }

    // MARK: - Kéo file thiếu (khôi phục / thiết bị khác)

    private func pullMissingFiles() async {
        let all = index.allNodes()
        var toPull: [(path: String, node: IndexNode)] = []
        for (path, node) in all where !node.isDirectory {
            if store.fileSize(at: path.components) == nil {
                toPull.append((path, node))
            }
        }
        guard !toPull.isEmpty else { return }
        AppLog.log("sync", "⬇️ Cần tải về \(toPull.count) file…")

        for (i, item) in toPull.enumerated() {
            guard !Task.isCancelled else { return }
            await setPhase(.working("Đang tải về \(item.node.name) (\(i + 1)/\(toPull.count))…"))
            do {
                try await downloadFile(path: item.path, node: item.node)
                store.notifyChanged()   // UI reload để thấy file vừa tải về
            } catch {
                AppLog.log("sync", "❌ Không tải được \(item.path): \(error.localizedDescription)")
            }
        }
    }

    /// Tải 1 file (đủ parts → nối).
    private func downloadFile(path: String, node: IndexNode) async throws {
        guard let parts = node.parts, !parts.isEmpty else {
            AppLog.log("sync", "⚠️ Không có part nào cho \(path) — bỏ qua")
            return
        }
        let destURL = store.url(for: path.components)
        try FileManager.default.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        // File 1 part <5MB: tải thẳng về đích.
        if parts.count == 1, parts[0].size < 5 * 1024 * 1024,
           let client = accounts.client(for: parts[0].accountEmail), let partID = parts[0].driveFileId {
            let data = try await client.download(id: partID)
            try data.write(to: destURL, options: .atomic)
            return
        }

        // File nhiều part: tải từng part về tmp rồi nối.
        var downloaded: [(url: URL, size: Int64)] = []
        for (i, part) in parts.enumerated() {
            guard let partID = part.driveFileId else {
                throw DriveError.http(status: 0, reason: "missingPart", message: "Part \(part.index) chưa upload xong — không nối được file")
            }
            guard let client = accounts.client(for: part.accountEmail) else {
                throw DriveError.invalidGrant
            }
            await setPhase(.working("Tải phần \(i + 1)/\(parts.count) của \(node.name)…"))
            let tmpDest = store.tmpURL.appendingPathComponent("dl-\(part.index)-\(UUID().uuidString)")
            if part.size < 5 * 1024 * 1024 {
                let data = try await client.download(id: partID)
                try data.write(to: tmpDest, options: .atomic)
            } else {
                try await client.downloadToFile(id: partID, to: tmpDest)
            }
            downloaded.append((tmpDest, part.size))
        }
        try Chunker.assemble(parts: downloaded, to: destURL)
        AppLog.log("sync", "✅ Đã tải \(node.name) (\(parts.count) parts)")
    }

    // MARK: - Mirror index.json

    private func mirrorIndex(rootIDs: [String: String]) async {
        index.save()
        let snapshot = index.snapshot()
        guard !snapshot.nodes.isEmpty else { return }
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(IndexPayload(nodes: snapshot.nodes, rev: snapshot.rev)) else { return }

        for (email, _) in rootIDs {
            guard let client = accounts.client(for: email) else { continue }
            do {
                // Tìm file index cũ → ghi đè; chưa có → tạo.
                let rootID = rootIDs[email]!
                if let existing = try await client.find(named: IndexStore.indexFileName, in: rootID) {
                    if data.count < 5 * 1024 * 1024 {
                        _ = try await client.uploadSmall(data: data, name: IndexStore.indexFileName, parentID: rootID, appProperties: [IndexStore.indexMarkerKey: IndexStore.indexMarkerValue], existingID: existing.id)
                    } else {
                        // index >5MB: ghi tạm ra đĩa rồi resumable.
                        let tmp = store.tmpURL.appendingPathComponent("index-\(UUID().uuidString).json")
                        try data.write(to: tmp)
                        _ = try await client.uploadResumable(fileURL: tmp, name: IndexStore.indexFileName, parentID: rootID, appProperties: [IndexStore.indexMarkerKey: IndexStore.indexMarkerValue])
                        try? FileManager.default.removeItem(at: tmp)
                    }
                } else {
                    if data.count < 5 * 1024 * 1024 {
                        _ = try await client.uploadSmall(data: data, name: IndexStore.indexFileName, parentID: rootID, appProperties: [IndexStore.indexMarkerKey: IndexStore.indexMarkerValue])
                    } else {
                        let tmp = store.tmpURL.appendingPathComponent("index-\(UUID().uuidString).json")
                        try data.write(to: tmp)
                        _ = try await client.uploadResumable(fileURL: tmp, name: IndexStore.indexFileName, parentID: rootID, appProperties: [IndexStore.indexMarkerKey: IndexStore.indexMarkerValue])
                        try? FileManager.default.removeItem(at: tmp)
                    }
                }
            } catch {
                AppLog.log("sync", "⚠️ Không mirror được index lên \(email): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Khôi phục index sau cài lại

    /// Nếu index local rỗng (cài lại) → tải index.json từ account nào có rev cao nhất;
    /// không index nào đọc được → dựng index từ appProperties của các part trên Drive.
    private func restoreIndexIfNeeded(rootIDs: [String: String]) async {
        guard index.snapshot().nodes.isEmpty else { return }
        let scanned = store.scanAll()
        let fileCount = scanned.files.count

        if fileCount > 0 {
            // Index mất nhưng mirror còn (index.json hỏng / xóa nhầm .myd-meta):
            // KHÔNG nạp index cũ đè lên — để adoptOrphanLocalFiles() nhận nuôi file local.
            AppLog.log("sync", "ℹ️ Index rỗng nhưng mirror có \(fileCount) file — sẽ nhận nuôi các file này")
            return
        }

        var best: (payload: IndexPayload, email: String)?
        for (email, rootID) in rootIDs {
            guard let client = accounts.client(for: email) else { continue }
            do {
                guard let indexFile = try await client.find(named: IndexStore.indexFileName, in: rootID) else { continue }
                let data = try await client.download(id: indexFile.id)
                let dec = JSONDecoder()
                dec.dateDecodingStrategy = .iso8601
                let payload = try dec.decode(IndexPayload.self, from: data)
                if best == nil || payload.rev > best!.payload.rev {
                    best = (payload, email)
                }
            } catch {
                AppLog.log("sync", "⚠️ Không đọc được index từ \(email): \(error.localizedDescription)")
            }
        }

        if let best {
            _ = index.mergeRemote(nodes: best.payload.nodes, remoteRev: best.payload.rev)
            AppLog.log("sync", "✅ Khôi phục index (rev \(best.payload.rev)) từ \(best.email) — \(best.payload.nodes.count) node")
            return
        }

        // Không index nào → dựng từ appProperties trên Drive (kế hoạch B).
        AppLog.log("sync", "ℹ️ Không có index.json — dựng index từ appProperties trên Drive…")
        await rebuildIndexFromDrive(rootIDs: rootIDs)
    }

    /// Dựng index từ appProperties của part trên Drive (khi mất index.json).
    /// Part mang mydFileId = path logic; ghép các part cùng path thành file logic.
    private func rebuildIndexFromDrive(rootIDs: [String: String]) async {
        var nodes: [String: IndexNode] = [:]

        for (email, rootID) in rootIDs {
            guard let client = accounts.client(for: email) else { continue }
            do {
                let children = try await Self.listAllDescendants(client: client, folderID: rootID)
                for f in children {
                    guard let props = f.appProperties, let filePath = props["mydFileId"] else { continue }
                    // Part của 1 file logic.
                    var node = nodes[filePath] ?? IndexNode(
                        name: filePath.components.last ?? f.name,
                        isDirectory: false, size: 0, modified: f.modifiedTime,
                        parts: [], rev: Int(props["mydRev"] ?? "1") ?? 1, driveFolderId: nil
                    )
                    var parts = node.parts ?? []
                    let partIndex = Int(props["mydPartIndex"] ?? "0") ?? 0
                    parts.append(FilePart(
                        index: partIndex, size: f.sizeBytes, accountEmail: email,
                        driveFileId: f.id,
                        remoteName: Chunker.partName(fileName: filePath.components.last ?? f.name, index: partIndex)
                    ))
                    parts.sort { $0.index < $1.index }
                    node.parts = parts
                    nodes[filePath] = node
                }
            } catch {
                AppLog.log("sync", "⚠️ Dựng index từ \(email) lỗi: \(error.localizedDescription)")
            }
        }

        guard !nodes.isEmpty else {
            AppLog.log("sync", "ℹ️ Drive không có dữ liệu MyDrive nào — bắt đầu trống")
            return
        }
        let maxRev = nodes.values.map(\.rev).max() ?? 1
        index.replaceAll(nodes: nodes, rev: maxRev)
        AppLog.log("sync", "✅ Đã dựng lại index từ Drive — \(nodes.count) file (rev \(maxRev))")
    }

    /// Quét đệ quy 1 folder trên Drive.
    private static func listAllDescendants(client: DriveClient, folderID: String) async throws -> [DriveFile] {
        var out: [DriveFile] = []
        let children = try await client.listChildren(folderID: folderID)
        for child in children {
            if child.isFolder {
                out.append(child)
                out.append(contentsOf: try await listAllDescendants(client: client, folderID: child.id))
            } else {
                out.append(child)
            }
        }
        return out
    }

    // MARK: - Nhận nuôi file có sẵn trong mirror (kéo thả USB / index mất)

    /// File tồn tại ở mirror nhưng chưa có trong index → đăng ký upload
    /// (tự xử lý trường hợp người dùng kéo file vào mirror qua USB File Sharing).
    private func adoptOrphanLocalFiles() async {
        let scanned = store.scanAll()
        var adopted = 0
        for rel in scanned.files {
            let path = rel
            guard index.node(at: path) == nil else { continue }
            guard let size = store.fileSize(at: path.components) else { continue }
            let node = IndexNode(
                name: path.components.last ?? rel, isDirectory: false, size: size,
                modified: Date(), parts: nil, rev: 1, driveFolderId: nil
            )
            index.upsert(path: path, node: node)
            journal.enqueue(.uploadFile(path: path))
            adopted += 1
        }
        // Thư mục mới kéo thả (không có file nào trong index).
        for rel in scanned.dirs {
            guard index.node(at: rel) == nil else { continue }
            index.upsert(path: rel, node: .init(
                name: rel.components.last ?? rel, isDirectory: true, size: 0,
                modified: Date(), parts: nil, rev: 1, driveFolderId: nil
            ))
            journal.enqueue(.createFolder(path: rel))
            adopted += 1
        }
        if adopted > 0 {
            AppLog.log("sync", "📥 Nhận nuôi \(adopted) mục có sẵn trong mirror")
            store.notifyChanged()   // UI reload để thấy ngay các mục mới nhận nuôi
        }
    }
}

// MARK: - Helpers

/// Payload index.json (mọi account giữ bản giống nhau).
struct IndexPayload: Codable {
    var nodes: [String: IndexNode]
    var rev: Int
}

extension JournalOp {
    /// Mô tả ngắn để log/băng trạng thái.
    var describe: String {
        switch self {
        case let .uploadFile(p): return "tải lên \(p.components.last ?? p)"
        case let .createFolder(p): return "tạo thư mục \(p.components.last ?? p)"
        case let .rename(f, t): return "đổi tên \(f.components.last ?? f)"
        case let .move(f, t): return "di chuyển \(f.components.last ?? f)"
        case let .delete(p, _): return "xóa \(p.components.last ?? p)"
        case let .restoreTrash(p, _): return "khôi phục \(p.components.last ?? p)"
        }
    }
}

extension String {
    /// Tách path thành components (an toàn với "/" trong tên — app không khuyến khích).
    var components: [String] {
        split(separator: "/").map(String.init)
    }
}
