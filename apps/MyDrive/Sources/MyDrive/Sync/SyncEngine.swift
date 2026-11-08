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

    /// Còn việc chưa xong (đang chạy hoặc op chờ trong journal) — banner phải hiện.
    var hasPendingWork: Bool {
        isWorking || pendingCount > 0
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
    private let placement = PlacementService.shared

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
        // Dung lượng các account (chỉ account cache cũ >10 phút mới gọi mạng).
        Task { await PlacementService.shared.refreshQuotas() }
    }

    @objc private func appWillResignActive() {
        // Flush index + journal xuống đĩa ngay trước khi nền (mọi thay đổi pending
        // của coalesce phải chắc chắn nằm trên đĩa).
        IndexStore.shared.saveNow()
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

        // 0.5) CHẨN ĐOÁN: luôn log trạng thái — sync im lặng không giải thích
        // được gì cho người dùng (bug 08/11: 3 tiếng không hiểu app đang nghĩ gì).
        let snap = index.snapshot()
        let idxFiles = snap.nodes.values.filter { !$0.isDirectory }
        let unfinished = idxFiles.filter { node in
            guard let parts = node.parts else { return true }
            return parts.isEmpty || parts.contains { $0.driveFileId == nil || $0.accountEmail.isEmpty }
        }.count
        let scanned = store.scanAll()
        AppLog.log("sync", "📊 Index \(snap.nodes.count) node (\(idxFiles.count) file, \(snap.nodes.count - idxFiles.count) thư mục, \(unfinished) file chưa upload xong) · mirror \(scanned.files.count) file · journal \(journal.count) op · rev \(snap.rev)")

        // 1) KHÔI PHỤC: nếu index rỗng local nhưng Drive có index (cài lại) → nạp.
        await restoreIndexIfNeeded(rootIDs: rootIDs)

        // 1.5) TỰ LÀNH: file đã đăng ký trong index nhưng part chưa upload xong
        //      (op upload mất do crash/migration/bug cũ) → xếp lại hàng đợi.
        //      Không có bước này, file kẹt "parts nil/unfinished" mãi mãi không lên Drive
        //      dù journal rỗng và sync báo thành công (bug thật đã gặp 07/11/2026).
        requeueUnfinishedUploads()

        // 2) Đẩy các op trong Journal (mọi thay đổi người dùng).
        await processJournal(rootIDs: rootIDs)

        // 2.5) ĐỐI CHIẾU driveFileId trong index với Drive thật: file bên Drive
        //      đã bị xóa (web/thùng rác/drive dọn) thì index vẫn ghi "đã upload"
        //      mãi mãi — sync tưởng xong trong khi Drive trống (bug thật 08/11:
        //      3409 file trong app, Drive web chỉ thấy index.json). Part chết →
        //      nil id + xếp lại op upload từ mirror.
        await verifyDriveParts(rootIDs: rootIDs)

        // 3) Kéo file thiếu (file có trong index nhưng mirror chưa có — cài lại).
        await pullMissingFiles()

        // 3.5) Nhận nuôi file có sẵn trong mirror nhưng chưa có trong index
        //      (kéo thả qua USB File Sharing / index bị mất).
        await adoptOrphanLocalFiles()

        // 4) Mirror index.json lên MỌI account.
        await mirrorIndex(rootIDs: rootIDs)

        // 4.5) DỌN FOLDER TRÙNG: nhiều worker song song cùng ensureFolderPath
        //      (TOCTOU: cùng thấy chưa có → cùng tạo) sinh folder trùng tên
        //      (Manga/Color/No… x4-5 lần, bug 08/11). Drive cho phép trùng tên
        //      trong 1 thư mục. Giữ bản có driveFolderId trong index, xoá hẳn
        //      các bản cùng tên trong cùng parent KHÔNG được app tham chiếu.
        await dedupeDuplicateFolders(rootIDs: rootIDs)

        // Vẫn còn op chờ (account đầy, lỗi tạm) → KHÔNG báo idle: banner giữ
        // trạng thái "N thao tác chờ" để người dùng biết sync chưa xong.
        if journal.count == 0 {
            await setPhase(.idle)
        } else {
            await setPhase(.idle)
            await setPhase(.working("\(journal.count) thao tác chờ — sẽ thử lại"))
        }
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
        // Dọn ops chỉ tới path đã bị xóa khỏi index (file/folder xóa khi op kẹt
        // — không dọn thì vòng sau lại bỏ qua → giữ → bỏ qua… vô hạn).
        let validPaths = Set(index.allNodes().map(\.path))
        journal.purgeOrphans(validPaths: validPaths)

        let entries = journal.pending()
        guard !entries.isEmpty else { return }
        AppLog.log("sync", "▶️ Đẩy \(entries.count) thao tác…")

        // Song song hoá: các op upload chỉ chờ round-trip Drive (~2 giây/op)
        // nếu TUẦN TỰ — 3277 op sẽ mất hơn 1 tiếng mở app liên tục. Chia lô 6
        // op chạy cùng lúc (~3 op/giây) — thứ tự trong lô không quan trọng vì
        // mỗi op độc lập (file/folder riêng; part của cùng file nằm trong 1 op).
        let concurrency = 6
        // Bộ đếm op kế tiếp + cờ dừng — chia sẻ giữa 6 worker (actor-isolated).
        let counter = OperationCounter(limit: entries.count)
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<concurrency {
                group.addTask { [weak self] in
                    await self?.processJournalWorker(entries: entries, rootIDs: rootIDs, counter: counter)
                }
            }
        }
        _ = counter
    }

    /// Bộ đếm thread-safe phân phát op kế tiếp cho các worker (nonisolated class
    /// + lock — đơn giản, không vướng actor isolation).
    private final class OperationCounter: @unchecked Sendable {
        private var index = 0
        private let limit: Int
        private let lock = NSLock()
        init(limit: Int) { self.limit = limit }
        func next(_ entries: [JournalEntry]) -> JournalEntry? {
            lock.lock()
            defer { lock.unlock() }
            defer { index += 1 }
            return index < limit ? entries[index] : nil
        }
    }

    /// 1 worker: lấy op kế tiếp, xử lý, lặp. invalidGrant → return (các worker
    /// khác cũng sẽ gặp cùng token chết rồi tự dừng).
    private func processJournalWorker(
        entries: [JournalEntry],
        rootIDs: [String: String],
        counter: OperationCounter
    ) async {
        while !Task.isCancelled {
            guard let entry = counter.next(entries) else { return }
            do {
                try await processEntry(entry, rootIDs: rootIDs)
                // Op uploadFile: chỉ complete NGAY khi mọi part đã có fileID
                // (tức upload thật sự xong — gồm cả trường hợp job nền đã kịp
                // callback trước khi vòng này kiểm tra). Nếu part vẫn nil
                // (đã GIAO nền, callback chưa về) → GIỮ op: callback nền sẽ
                // gọi completeUpload khi xong; nếu nền lỗi thì op còn đó để retry.
                // Giữ op tránh requeue sinh op TRÙNG khi app đóng giữa chừng.
                var isFullyUploaded = true
                if case let .uploadFile(p) = entry.op {
                    if let parts = index.node(at: p)?.parts, !parts.isEmpty {
                        isFullyUploaded = parts.allSatisfy { $0.driveFileId != nil }
                    } else {
                        isFullyUploaded = false
                    }
                }
                if isFullyUploaded {
                    journal.complete(entry)
                }
                await setPhase(.working("Đã đẩy \(entry.op.describe)"))
            } catch let err as DriveError {
                switch err {
                case .quotaExceeded:
                    journal.recordFailure(entry, error: err.localizedDescription)
                    AppLog.log("sync", "⚠️ \(entry.op.describe): không account nào đủ chỗ — thử lại lần sau")
                    await setPhase(.working("Account đầy — thử account khác…"))
                case .invalidGrant:
                    journal.recordFailure(entry, error: err.localizedDescription)
                    await setPhase(.error("Account cần đăng nhập lại — vào tab Tài khoản."))
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
            // File không tồn tại ở mirror (đã bị xóa/người dùng dọn) — op này
            // PHẢI bị loại khỏi journal, không "bỏ qua rồi giữ" (kéo dài vòng
            // sync vô hạn: bỏ qua → giữ → bỏ qua… bug 08/11, 28.963 lần log).
            AppLog.log("sync", "🧹 Op upload \(path): file không còn ở mirror — loại op")
            index.remove(path: path)
            IndexStore.shared.removeTree(prefix: path + "/")
            Journal.shared.completeUpload(path: path)
            return
        }
        let fileName = path.components.last ?? "file"

        // 1) Nếu chưa có placement (node mới HOẶC node có parts nil — UI upsert
        //    trước khi op chạy) → đặt account(s) theo dung lượng. Trước đây chỉ
        //    kiểm tra node == nil → parts nil thoát im lặng, op bị coi là xong
        //    mà chẳng upload gì (bug "chỉ thấy folder trên Drive").
        if index.node(at: path)?.parts == nil || index.node(at: path)?.parts?.isEmpty == true {
            let partsPlan = Chunker.planParts(size: size)
            var placed = await placement.place(parts: partsPlan)
            for i in placed.indices {
                placed[i].remoteName = Chunker.partName(fileName: fileName, index: placed[i].index)
            }
            if index.node(at: path) != nil {
                index.update(path: path) { $0.parts = placed }
            } else {
                index.upsert(path: path, node: .init(name: fileName, isDirectory: false, size: size, modified: Date(), parts: placed, rev: 1, driveFolderId: nil))
            }
        }

        // 2) Upload từng part chưa xong (var parts — cập nhật sau mỗi part).
        guard var parts = index.node(at: path)?.parts, !parts.isEmpty else {
            AppLog.log("sync", "⚠️ \(fileName): không có placement sau khi đặt — bỏ qua")
            return
        }
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

            // Job nền đang chạy cho part này → không giao lại, coi op đã xong.
            if BackgroundUploader.shared.hasActiveJob(path: path, partIndex: part.index) {
                continue
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

            // appProperties TỐI ĐA 124 bytes (key+value, UTF-8) — KHÔNG chứa path
            // (path dài/Unicode vọt limit → Drive 403 propertyLengthLimitExceeded,
            // op kẹt lặp vô hạn). Path logic khi dựng lại index được suy từ CÂY
            // FOLDER trên Drive (part nằm đúng thư mục logic) + tên part.
            let props = [
                "mydPartIndex": "\(part.index)",
                "mydRev": "\(index.node(at: path)?.rev ?? 1)",
            ]

            // MỌI part đều đi NỀN (background URLSession — daemon nsurlsessiond
            // upload, app kill/đóng vẫn chạy tiếp; tự đánh thức app ghi kết quả).
            // Đường upload trong-app đã bỏ: nó chỉ sống khi app mở — với hàng trăm
            // file nhỏ là nguyên nhân "sync không chạy ngầm" (bug 08/11/2026).
            let partURL = store.tmpURL.appendingPathComponent("bgpart-\(UUID().uuidString)")
            let offset = Int64(part.index) * Chunker.partSize
            let rangeData = try Chunker.readRange(from: store.url(for: path.components), offset: offset, length: part.size)
            try rangeData.write(to: partURL, options: .atomic)
            _ = try await client.startBackgroundUpload(
                fileURL: partURL, name: part.remoteName, parentID: parentID,
                appProperties: props, path: path,
                partIndex: part.index, partSize: part.size
            )
            AppLog.log("sync", "🚀 Giao nền part \(part.index) của \(fileName) → \(part.accountEmail)")
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
        // Folder đã bị xóa khỏi index (người dùng xóa ở app trong lúc op kẹt) →
        // KHÔNG tái tạo trên Drive (đó là cách folder "Mangas" bị tạo lại 6 lần
        // dù người dùng đã xóa sạch trên Drive web — bug 08/11).
        guard index.node(at: path) != nil else {
            AppLog.log("sync", "🧹 Op createFolder \(path): node đã bị xóa khỏi index — bỏ op")
            return
        }
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
        var orphans = 0
        for (path, node) in all where !node.isDirectory {
            if store.fileSize(at: path.components) == nil {
                // Node không có part nào (dựng từ Drive nhưng part bị trash hết,
                // hoặc node mồ côi sau lỗi) — không tải được bao giờ → bỏ khỏi
                // index để không kéo-về mỗi vòng sync (nguồn “Cần tải về N” dai dẳng).
                if (node.parts ?? []).isEmpty || (node.parts ?? []).allSatisfy({ $0.driveFileId == nil }) {
                    orphans += 1
                    continue
                }
                toPull.append((path, node))
            }
        }
        if orphans > 0 {
            AppLog.log("sync", "🧹 Bỏ \(orphans) node không có part khỏi index (không thể tải về)")
            for (path, node) in all where !node.isDirectory {
                if (node.parts ?? []).isEmpty || (node.parts ?? []).allSatisfy({ $0.driveFileId == nil }) {
                    index.remove(path: path)
                }
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

    // MARK: - Dọn folder trùng (TOCTOU)

    /// Nhiều worker song song cùng ensureFolderPath (TOCTOU) tạo folder trùng
    /// tên trong cùng parent (Manga/Color/No… lặp x4-5). NHỒM THEO (parent, tên):
    /// nhóm >1 folder → chọn keeper (id mà index driveFolderId tham chiếu, nếu
    /// không thì bản già nhất), GOM file của bản kia về keeper (PATCH add/remove
    /// parents), DELETE hẳn bản trùng. Bug thật 08/11: DFS "cây hợp lệ" từ root
    /// coi NHỮNG FOLDER TRÙNG CON CỦA ROOT là hợp lệ (chúng là con chính chủ của
    /// root!) → không thấy rác nào, báo "Không có folder trùng" trong khi web
    /// đầy Manga/Color/No ×4.
    private func dedupeDuplicateFolders(rootIDs: [String: String]) async {
        var removedTotal = 0
        var movedTotal = 0
        for (email, rootID) in rootIDs {
            guard let client = accounts.client(for: email) else { continue }
            do {
                let all = try await client.listAllNonTrashed()

                // driveFolderId mà index tham chiếu (keeper ưu tiên).
                var referenced: Set<String> = []
                for node in index.allNodes().map(\.node) {
                    if let fid = node.driveFolderId { referenced.insert(fid) }
                }

                // Chỉ folder DƯỚI root MyDrive (app không đụng ngoài này).
                var foldersByParent: [String: [DriveFile]] = [:]
                var byID: [String: DriveFile] = [:]
                for f in all where f.isFolder {
                    byID[f.id] = f
                    foldersByParent[f.parents?.first ?? "", default: []].append(f)
                }

                // Scope: root + mọi con cháu của root (đi từ root xuống).
                var foldersInScope: Set<String> = [rootID]
                var queue = [rootID]
                while let pid = queue.popLast() {
                    for child in foldersByParent[pid] ?? [] where !foldersInScope.contains(child.id) {
                        foldersInScope.insert(child.id)
                        queue.append(child.id)
                    }
                }

                // File nhóm theo cha (để gom về keeper khi xoá folder trùng).
                let filesByParent: [String: [DriveFile]] = Dictionary(grouping: all.filter { !$0.isFolder }) { $0.parents?.first ?? "" }

                // NHỐM (parent, name) có >1 folder trong scope → xử lý.
                var removed = 0
                var moved = 0
                var groupsByKey: [String: [DriveFile]] = [:]
                for (parent, fs) in foldersByParent where foldersInScope.contains(parent) {
                    let byName = Dictionary(grouping: fs) { $0.name }
                    for (name, dupes) in byName where dupes.count > 1 {
                        groupsByKey["\(parent)/\(name)"] = dupes
                    }
                }
                for (_, dupes) in groupsByKey {
                    // Keeper: bản index tham chiếu; không thì bản TẠO SỚM NHẤT
                    // (createdTime — bản worker đầu tạo, thường là bản có nhiều file).
                    let keeper = dupes.first { referenced.contains($0.id) }
                        ?? dupes.min { ($0.createdTime ?? .distantPast) < ($1.createdTime ?? .distantPast) }
                        ?? dupes[0]
                    for junk in dupes where junk.id != keeper.id {
                        // Gom file của bản trùng về keeper (cùng tên cha — đúng cây).
                        for junkFile in filesByParent[junk.id] ?? [] {
                            do {
                                _ = try await client.updateMetadata(id: junkFile.id, addParents: keeper.id, removeParents: junk.id)
                                moved += 1
                            } catch {
                                AppLog.log("sync", "⚠️ Không gom được \(junkFile.name): \(error.localizedDescription) — GIỮ folder trùng \(junk.name)")
                                continue
                            }
                        }
                        // Folder con của rác: chuyển cả cụm về keeper (cùng tên cha).
                        for junkChild in foldersByParent[junk.id] ?? [] {
                            // Con trùng tên với con của keeper → gom file con nó lên keeper,
                            // xoá folder con rác; con khác tên → chuyển nguyên cụm.
                            if let canon = (foldersByParent[keeper.id] ?? []).first(where: { $0.name == junkChild.name }) {
                                for gf in filesByParent[junkChild.id] ?? [] {
                                    do {
                                        _ = try await client.updateMetadata(id: gf.id, addParents: canon.id, removeParents: junkChild.id)
                                        moved += 1
                                    } catch {
                                        AppLog.log("sync", "⚠️ Không gom được \(gf.name): \(error.localizedDescription) — giữ \(junkChild.name)")
                                        continue
                                    }
                                }
                                try? await client.delete(id: junkChild.id)
                            } else {
                                do {
                                    _ = try await client.updateMetadata(id: junkChild.id, addParents: keeper.id, removeParents: junk.id)
                                } catch {
                                    AppLog.log("sync", "⚠️ Không chuyển được \(junkChild.name) về \(keeper.name) — giữ folder trùng")
                                    continue
                                }
                            }
                        }
                        do {
                            try await client.delete(id: junk.id)
                            removed += 1
                            AppLog.log("sync", "🧹 Xoá folder trùng \(junk.name) dưới \(byID[junk.parents?.first ?? ""]?.name ?? "root") — giữ bản \(keeper.id.prefix(8))…")
                        } catch {
                            AppLog.log("sync", "⚠️ Không xoá được folder trùng \(junk.name): \(error.localizedDescription)")
                        }
                    }
                }
                if removed > 0 || moved > 0 {
                    removedTotal += removed
                    movedTotal += moved
                    AppLog.log("sync", "🧹 \(email): xoá \(removed) folder trùng, gom \(moved) file về bản chính thống")
                } else {
                    AppLog.log("sync", "🧹 Không có folder trùng nào cần dọn (\(foldersInScope.count) folder trong scope)")
                }
            } catch {
                AppLog.log("sync", "⚠️ Không dọn folder trùng trên \(email): \(error.localizedDescription)")
            }
        }
        if removedTotal == 0 && movedTotal == 0 {
            // Đã log trong vòng per-account.
        }
    }

    // MARK: - Mirror index.json

    private func mirrorIndex(rootIDs: [String: String]) async {
        index.save()
        let snapshot = index.snapshot()
        guard !snapshot.nodes.isEmpty else {
            AppLog.log("sync", "📤 Index rỗng — bỏ qua mirror index.json")
            return
        }
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(IndexPayload(nodes: snapshot.nodes, rev: snapshot.rev)) else { return }

        var pushed = 0
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
                pushed += 1
            } catch {
                AppLog.log("sync", "⚠️ Không mirror được index lên \(email): \(error.localizedDescription)")
            }
        }
        AppLog.log("sync", "📤 Mirror index.json (\(snapshot.nodes.count) node, rev \(snapshot.rev), \(ByteFmt.string(Int64(data.count)))) → \(pushed)/\(rootIDs.count) account")
    }

    // MARK: - Khôi phục index sau cài lại

    /// Nếu index local rỗng (cài lại) → tải index.json từ account nào có rev cao nhất;
    /// không index nào đọc được → dựng index từ appProperties của các part trên Drive.
    private func restoreIndexIfNeeded(rootIDs: [String: String]) async {
        guard index.snapshot().nodes.isEmpty else { return }
        let scanned = store.scanAll()
        let fileCount = scanned.files.count

        if fileCount > 0 {
            // Index mất nhưng mirror còn (index.json hỏng / xóa nhầm MyDrive.meta):
            // KHÔNG nạp index cũ đè lên — để adoptOrphanLocalFiles() nhận nuôi file local.
            AppLog.log("sync", "ℹ️ Index rỗng nhưng mirror có \(fileCount) file — sẽ nhận nuôi các file này")
            return
        }

        AppLog.log("sync", "ℹ️ Index + mirror đều trống — tìm index.json trên Drive…")
        var best: (payload: IndexPayload, email: String)?
        for (email, rootID) in rootIDs {
            guard let client = accounts.client(for: email) else { continue }
            do {
                guard let indexFile = try await client.find(named: IndexStore.indexFileName, in: rootID) else {
                    AppLog.log("sync", "ℹ️ \(email): không có index.json trên Drive")
                    continue
                }
                let data = try await client.download(id: indexFile.id)
                let dec = JSONDecoder()
                dec.dateDecodingStrategy = .iso8601
                let payload = try dec.decode(IndexPayload.self, from: data)
                AppLog.log("sync", "ℹ️ \(email): index.json có \(payload.nodes.count) node (rev \(payload.rev), \(ByteFmt.string(Int64(data.count))))")
                if best == nil || payload.rev > best!.payload.rev {
                    best = (payload, email)
                }
            } catch {
                AppLog.log("sync", "⚠️ Không đọc được index từ \(email): \(error.localizedDescription)")
            }
        }

        if let best {
            let merged = index.mergeRemote(nodes: best.payload.nodes, remoteRev: best.payload.rev)
            if merged {
                AppLog.log("sync", "✅ Khôi phục index (rev \(best.payload.rev)) từ \(best.email) — \(best.payload.nodes.count) node")
            } else {
                AppLog.log("sync", "ℹ️ Bỏ qua index trên Drive (rev không cao hơn local)")
            }
            return
        }

        // Không index nào → dựng từ appProperties trên Drive (kế hoạch B).
        AppLog.log("sync", "ℹ️ Không có index.json — dựng index từ appProperties trên Drive…")
        await rebuildIndexFromDrive(rootIDs: rootIDs)
        // GHI ĐÈ index.json mới lên Drive: bản cũ đã HỎNG (đó là lý do rơi vào
        // plan B) — không đè lại thì lần cài lại sau lại đọc bản hỏng → lại plan B.
        await mirrorIndex(rootIDs: rootIDs)
    }

    /// Dựng index từ Drive khi mất index.json. appProperties chỉ mang
    /// mydPartIndex/mydRev — path logic được SUY từ cấu trúc folder:
    /// MyDrive/<cây thư mục logic>/<tên>.myd-part-XXXX (remoteName của part
    /// là tên file gốc + đuôi part, gỡ đuôi ra được tên file gốc).
    private func rebuildIndexFromDrive(rootIDs: [String: String]) async {
        var nodes: [String: IndexNode] = [:]

        for (email, rootID) in rootIDs {
            guard let client = accounts.client(for: email) else { continue }
            do {
                let children = try await Self.listAllDescendants(client: client, folderID: rootID, currentPath: [])
                for (relPath, f) in children {
                    guard !f.isFolder else { continue }
                    let props = f.appProperties ?? [:]
                    let partIndex = Int(props["mydPartIndex"] ?? "0") ?? 0
                    // Gỡ đuôi part nếu có — còn lại là tên file logic gốc.
                    let suffix = ".myd-part-\(String(format: "%04d", partIndex))"
                    let fileName = f.name.hasSuffix(suffix) ? String(f.name.dropLast(suffix.count)) : f.name
                    let path = (relPath + [fileName]).joined(separator: "/")
                    guard !path.isEmpty else { continue }

                    var node = nodes[path] ?? IndexNode(
                        name: fileName, isDirectory: false, size: 0, modified: f.modifiedTime,
                        parts: [], rev: Int(props["mydRev"] ?? "1") ?? 1, driveFolderId: nil
                    )
                    var parts = node.parts ?? []
                    parts.append(FilePart(
                        index: partIndex, size: f.sizeBytes, accountEmail: email,
                        driveFileId: f.id,
                        remoteName: Chunker.partName(fileName: fileName, index: partIndex)
                    ))
                    parts.sort { $0.index < $1.index }
                    node.parts = parts
                    nodes[path] = node
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

    /// Quét đệ quy 1 folder trên Drive — trả (relativePath components, file/folder).
    private static func listAllDescendants(client: DriveClient, folderID: String, currentPath: [String]) async throws -> [([String], DriveFile)] {
        var out: [([String], DriveFile)] = []
        let children = try await client.listChildren(folderID: folderID)
        for child in children {
            if child.isFolder {
                out.append((currentPath + [child.name], child))
                out.append(contentsOf: try await listAllDescendants(client: client, folderID: child.id, currentPath: currentPath + [child.name]))
            } else {
                out.append((currentPath, child))
            }
        }
        return out
    }

    // MARK: - Nhận nuôi file có sẵn trong mirror (kéo thả USB / index mất)

    /// Đối chiếu mọi driveFileId trong index với Drive: id không còn tồn tại
    /// (bị xóa trên web, dọn khỏi thùng rác…) → nil đi + xếp lại op upload.
    /// Mirror giữ file gốc nên upload lại chỉ tốn băng thông, không mất dữ liệu.
    /// Cách tra: Drive KHÔNG cho query theo id (400 Invalid Value) → liệt kê 1
    /// lượt mọi file không-thùng-rác của account rồi tự suy cây từ parents:
    /// id sống = nằm dưới root MyDrive; mọi id khác = chết (shared-with-me…).
    private func verifyDriveParts(rootIDs: [String: String]) async {
        // Tập id cần tra: mọi part đang có driveFileId, nhóm theo account chứa nó.
        var checked = 0
        var byEmail: [String: [String: (path: String, part: Int)]] = [:]   // email → id → owner
        for (path, node) in index.allNodes() {
            guard let parts = node.parts else { continue }
            for (i, part) in parts.enumerated() {
                guard let fid = part.driveFileId, !part.accountEmail.isEmpty else { continue }
                byEmail[part.accountEmail, default: [:]][fid] = (path, i)
                checked += 1
            }
        }
        guard checked > 0 else { return }

        // Mỗi account: liệt kê mọi file sống, mark những id thấy được là còn sống.
        var aliveGlobal: Set<String> = []
        for (email, ids) in byEmail {
            guard let client = accounts.client(for: email) else {
                // Account không đăng nhập được → coi TẤT CẢ id của nó sống, đừng requeue oan.
                aliveGlobal.formUnion(ids.keys)
                continue
            }
            do {
                let files = try await client.listAllNonTrashed()
                let aliveHere = Set(files.map(\.id))
                let found = ids.keys.filter { aliveHere.contains($0) }
                aliveGlobal.formUnion(found)
                AppLog.log("sync", "🔍 \(email): \(found.count)/\(ids.count) part còn sống trên Drive (\(files.count) file liệt kê)")
            } catch {
                // Không tra được (mạng/lỗi tạm) → coi TẤT CẢ còn sống, đừng requeue oan.
                AppLog.log("sync", "⚠️ Không đối chiếu được part trên \(email): \(error.localizedDescription) — bỏ qua lượt này")
                aliveGlobal.formUnion(ids.keys)
            }
        }

        var deadPaths: [String: Set<Int>] = [:]
        for (_, ids) in byEmail {
            for (fid, owner) in ids where !aliveGlobal.contains(fid) {
                deadPaths[owner.path, default: []].insert(owner.part)
            }
        }
        guard !deadPaths.isEmpty else { return }

        for (path, partIdxs) in deadPaths {
            index.update(path: path) { node in
                guard var parts = node.parts else { return }
                for i in partIdxs where i < parts.count {
                    parts[i].driveFileId = nil
                }
                node.parts = parts
            }
            if !journal.pending().contains(where: { if case let .uploadFile(p) = $0.op { return p == path }; return false }) {
                journal.enqueue(.uploadFile(path: path))
            }
        }
        AppLog.log("sync", "🔁 \(deadPaths.count) file có part đã chết trên Drive — xếp lại upload (đã tra \(checked) id)")
    }

    /// File ĐÃ có trong index nhưng chưa upload xong (parts nil, hoặc có part
    /// accountEmail rỗng / driveFileId nil) mà journal KHÔNG còn op tương ứng
    /// → xếp lại op upload. Đây là lưới an toàn cho mất journal (crash, migration,
    /// bug decode) — không có nó thì file kẹt vĩnh viễn "đã đồng bộ" trên UI
    /// nhưng thực chất chưa lên Drive.
    private func requeueUnfinishedUploads() {
        let pendingOps = journal.pending()
        var queuedPaths = Set<String>()
        for e in pendingOps {
            if case let .uploadFile(p) = e.op { queuedPaths.insert(p) }
        }
        var requeued = 0
        for (path, node) in index.allNodes() {
            guard !node.isDirectory, !queuedPaths.contains(path) else { continue }
            let unfinished: Bool
            if let parts = node.parts {
                unfinished = parts.isEmpty || parts.contains { $0.driveFileId == nil || $0.accountEmail.isEmpty }
            } else {
                unfinished = true
            }
            guard unfinished else { continue }
            journal.enqueue(.uploadFile(path: path))
            requeued += 1
        }
        if requeued > 0 {
            AppLog.log("sync", "🩹 Xếp lại \(requeued) file chưa upload xong vào hàng đợi")
        }
    }

    /// File tồn tại ở mirror nhưng chưa có trong index → đăng ký upload
    /// (tự xử lý trường hợp người dùng kéo file vào mirror qua USB File Sharing).
    /// DEDUPE: file đã có op uploadFile trong journal thì KHÔNG thêm nữa —
    /// không vậy mỗi lần cài lại + copy lại là queue bành trướng (bug 08/11).
    private func adoptOrphanLocalFiles() async {
        let scanned = store.scanAll()
        var queuedPaths = Set<String>()
        for e in journal.pending() {
            switch e.op {
            case let .uploadFile(p): queuedPaths.insert(p)
            case let .createFolder(p): queuedPaths.insert(p)
            default: break
            }
        }
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
            if !queuedPaths.contains(path) {
                journal.enqueue(.uploadFile(path: path))
            }
            adopted += 1
        }
        // Thư mục mới kéo thả (không có file nào trong index).
        for rel in scanned.dirs {
            guard index.node(at: rel) == nil else { continue }
            index.upsert(path: rel, node: .init(
                name: rel.components.last ?? rel, isDirectory: true, size: 0,
                modified: Date(), parts: nil, rev: 1, driveFolderId: nil
            ))
            if !queuedPaths.contains(rel) {
                journal.enqueue(.createFolder(path: rel))
            }
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
