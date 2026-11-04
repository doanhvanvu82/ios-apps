import Foundation

struct GameInfo: Identifiable, Hashable, Codable {
    var id: String { folderName }
    let folderName: String
    let engine: EngineKind
    let entryPath: String?
    let isAsar: Bool
    var lastPlayed: Date?
    var playCount: Int

    var isPlayable: Bool { engine.isPlayable }
}

/// Quản lý thư viện game.
///
/// Người dùng **chọn một thư mục chứa game** (vd `On My iPhone/GameHub/Games`
/// hoặc bất kỳ folder nào trong Files) — thư mục đó được **lưu lại bằng
/// bookmark** (security-scoped), app tự quét và phát hiện game bên trong.
/// Khi thêm game mới vào folder, bấm nút ↻ để quét lại.
final class GameLibrary: ObservableObject {
    static let shared = GameLibrary()

    /// Thư mục gốc người dùng nhìn thấy trong Files app (vẫn giữ cho save data)
    static var hubRoot: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("GameHub", isDirectory: true)
    }

    /// Thư mục game người dùng đã chọn (bookmark). `nil` = chưa chọn.
    @Published private(set) var gamesRoot: URL?

    static var importsRoot: URL {
        hubRoot.appendingPathComponent("Imports", isDirectory: true)
    }

    @Published private(set) var games: [GameInfo] = []
    @Published var statusMessage: String?
    @Published var isImporting = false
    @Published var isScanning = false
    /// Tiến trình quét: số thư mục đã duyệt / tổng ước tính.
    @Published private(set) var scanProgress = (done: 0, total: 0)

    private struct Metadata: Codable {
        var lastPlayed: [String: Date] = [:]
        var playCount: [String: Int] = [:]
        /// Bookmark data của thư mục game người dùng chọn.
        var gamesRootBookmark: Data?
        /// Cache danh sách game đã quét — mở app hiển thị ngay, không quét lại.
        var cachedGames: [GameInfo]?
        /// Build app đã quét ra cache. Khác build hiện tại → quét lại, vì cách
        /// nhận diện engine/thư mục gốc có thể đã đổi (entryPath cũ sai).
        var cachedBuild: String?
    }

    private var metadata = Metadata()
    private let metadataFile: URL
    private let metadataQueue = DispatchQueue(label: "vn.vudv.gamehub.metadata")
    /// Token giữ quyền truy cập thư mục đã chọn (giữ mạnh để không bị thu hồi).
    private var rootAccess: NSObject?

    private init() {
        metadataFile = Self.hubRoot.appendingPathComponent("library.json")
        try? FileManager.default.createDirectory(at: Self.hubRoot, withIntermediateDirectories: true)
        loadMetadata()

        // Khôi phục thư mục đã chọn từ bookmark (nếu có).
        if let data = metadata.gamesRootBookmark {
            var stale = false
            do {
                let url = try URL(resolvingBookmarkData: data,
                                  options: [],
                                  relativeTo: nil,
                                  bookmarkDataIsStale: &stale)
                let granted = url.startAccessingSecurityScopedResource()
                if granted { rootAccess = url as NSObject }
                gamesRoot = url
                if stale {
                    // Bookmark cũ — làm mới lại.
                    saveBookmark(for: url)
                }
            } catch {
                print("[GameLibrary] Không khôi phục được bookmark: \(error)")
            }
        }
        if gamesRoot != nil, metadata.cachedBuild != AppVersion.build {
            AppLog.info("App vừa cập nhật (build \(AppVersion.build)) → quét lại thư viện")
            refresh()
        }
    }

    /// Người dùng chọn thư mục chứa game → lưu + quét NGAY.
    func setGamesRoot(_ url: URL) {
        AppLog.ok("Chọn folder: \(url.path)")
        // Nhả scope cũ (nếu có) trước khi giữ scope mới.
        if let old = rootAccess as? URL {
            old.stopAccessingSecurityScopedResource()
            rootAccess = nil
        }
        let scoped = url.startAccessingSecurityScopedResource()
        AppLog.info("startAccessingSecurityScopedResource → \(scoped)")
        if scoped { rootAccess = url as NSObject }
        if let entries = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey]) {
            AppLog.info("Đọc được thư mục: \(entries.count) mục")
        } else {
            AppLog.error("Không đọc được thư mục \(url.lastPathComponent) (sandbox/scope)")
        }
        gamesRoot = url
        saveBookmark(for: url)
        statusMessage = "Đã chọn thư mục: \(url.lastPathComponent) — đang quét…"
        refresh()
    }

    /// Kết quả từ `FolderPicker` chọn thư mục game (màn chính + Cài đặt).
    func handleFolderPick(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                AppLog.warn("Picker trả về danh sách rỗng")
                statusMessage = "Không nhận được thư mục nào."
                return
            }
            setGamesRoot(url)
        case .failure(let error):
            if (error as? CocoaError)?.code == .userCancelled { return }
            AppLog.error("Lỗi chọn thư mục: \(error)")
            statusMessage = "Không chọn được thư mục: \(error.localizedDescription)"
        }
    }

    private func saveBookmark(for url: URL) {
        do {
            // bookmark creation cần security scope đang bật; giữ token trong rootAccess.
            let data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            metadata.gamesRootBookmark = data
            saveMetadata()
            AppLog.ok("Lưu bookmark OK (\(data.count) bytes)")
        } catch {
            AppLog.error("Không tạo được bookmark: \(error)")
        }
    }

    // MARK: - Quét thư viện (background + tiến trình)

    /// Quét game trong thư mục đã chọn (chạy trên background queue).
    /// Game có thể nằm trực tiếp trong đó hoặc trong 1 thư mục con (2 cấp).
    ///
    /// Tiến trình được cập nhật qua `scanProgress` (done/total) — UI đọc để
    /// hiển thị thanh tiến trình.
    func refresh() {
        guard let root = gamesRoot else {
            games = []
            return
        }
        guard !isScanning else { return }
        isScanning = true

        // Ước tính tổng số thư mục con trước (nhanh — chỉ liệt kê tên).
        let total = Self.estimateFolderCount(root: root)
        DispatchQueue.main.async { [weak self] in
            self?.scanProgress = (done: 0, total: total)
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            var detected: [GameInfo] = []
            var seen = Set<String>()

            // Callback cập nhật tiến trình (main thread).
            let reportProgress: (Int) -> Void = { done in
                DispatchQueue.main.async {
                    self.scanProgress = (done: done, total: total)
                }
            }

            var processed = 0
            Self.scanDir(
                root, depth: 1, seen: &seen,
                detected: &detected, metadata: self.metadata,
                onFolderProcessed: {
                    processed += 1
                    if processed % 3 == 0 { reportProgress(processed) }
                }
            )

            let sorted = detected.sorted { a, b in
                let aDate = a.lastPlayed ?? .distantPast
                let bDate = b.lastPlayed ?? .distantPast
                if aDate != bDate { return aDate > bDate }
                return a.folderName < b.folderName
            }

            DispatchQueue.main.async {
                self.games = sorted
                self.isScanning = false
                self.scanProgress = (done: total, total: total)
                // Lưu cache — mở app lần sau hiển thị ngay không cần quét lại.
                self.metadata.cachedGames = sorted
                self.metadata.cachedBuild = AppVersion.build
                self.saveMetadata()
                // Báo kết quả nếu người dùng vừa chọn folder (tránh đè thông báo import).
                if let msg = self.statusMessage, msg.contains("đang quét") {
                    let playable = sorted.filter { $0.isPlayable }.count
                    if sorted.isEmpty {
                        self.statusMessage = "Không tìm thấy game nào trong \"\(root.lastPathComponent)\"."
                    } else {
                        self.statusMessage = "Tìm thấy \(sorted.count) game (\(playable) chơi được)."
                    }
                }
            }
        }
    }

    /// Đếm sơ bộ số thư mục con (2 cấp) để làm mẫu số thanh tiến trình.
    private static func estimateFolderCount(root: URL) -> Int {
        let fm = FileManager.default
        let top = (try? fm.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        var count = 0
        for dir in top {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { continue }
            count += 1
            let sub = (try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
            for s in sub {
                var sDir: ObjCBool = false
                if fm.fileExists(atPath: s.path, isDirectory: &sDir), sDir.boolValue {
                    count += 1
                }
            }
        }
        return max(count, 1)
    }

    /// Quét đệ quy một thư mục (tĩnh, chạy trên background thread).
    private static func scanDir(_ dir: URL, depth: Int, seen: inout Set<String>,
                                detected: inout [GameInfo], metadata: Metadata,
                                onFolderProcessed: @escaping () -> Void) {
        guard depth >= 0 else { return }
        let fm = FileManager.default
        let children = (try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey]
        )) ?? []

        for child in children {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: child.path, isDirectory: &isDir),
                  isDir.boolValue else { continue }
            if child.lastPathComponent.hasPrefix(".") { continue }
            if seen.contains(child.lastPathComponent) { continue }
            seen.insert(child.lastPathComponent)

            let game = EngineDetector.detect(in: child)
            if game.engine != .unknown {
                detected.append(GameInfo(
                    folderName: game.folderName,
                    engine: game.engine,
                    entryPath: game.entryPath,
                    isAsar: game.isAsar,
                    lastPlayed: metadata.lastPlayed[game.folderName],
                    playCount: metadata.playCount[game.folderName] ?? 0
                ))
                onFolderProcessed()
            } else if depth > 0 {
                // Thư mục phân loại → quét tiếp bên trong.
                scanDir(child, depth: depth - 1, seen: &seen,
                        detected: &detected, metadata: metadata,
                        onFolderProcessed: onFolderProcessed)
                onFolderProcessed()
            } else {
                onFolderProcessed()
            }
        }
    }

    // MARK: - Import (background, không đơ UI)

    /// Quét Imports/, giải nén zip / dời thư mục vào thư mục game đã chọn.
    /// Chạy trên background queue. Nếu chưa chọn thư mục game thì bỏ qua.
    func importPendingItems() {
        guard !isImporting, let gamesRoot else { return }
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: Self.importsRoot, includingPropertiesForKeys: [.isDirectoryKey]),
              !items.isEmpty else { return }

        isImporting = true
        statusMessage = "Đang import…"

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let fm = FileManager.default

            var imported = 0
            for item in items {
                if item.lastPathComponent.hasPrefix(".") { continue }
                do {
                    var isDir: ObjCBool = false
                    fm.fileExists(atPath: item.path, isDirectory: &isDir)

                    let name = item.deletingPathExtension().lastPathComponent
                    var finalDest = gamesRoot.appendingPathComponent(name)
                    var counter = 2
                    while fm.fileExists(atPath: finalDest.path) {
                        finalDest = gamesRoot.appendingPathComponent("\(name) (\(counter))")
                        counter += 1
                    }

                    if isDir.boolValue {
                        // Thư mục game: dời vào Games/
                        try fm.moveItem(at: item, to: finalDest)
                        imported += 1
                        DispatchQueue.main.async {
                            self.statusMessage = "Đã import: \(finalDest.lastPathComponent)"
                        }
                    } else if item.pathExtension.lowercased() == "zip" {
                        // Zip: giải nén rồi xóa zip
                        try ZipExtractor.unzip(item, to: finalDest)
                        try fm.removeItem(at: item)
                        imported += 1
                        DispatchQueue.main.async {
                            self.statusMessage = "Đã import: \(finalDest.lastPathComponent)"
                        }
                    }
                    // Định dạng khác: bỏ qua (giữ nguyên file trong Imports/)
                } catch {
                    DispatchQueue.main.async {
                        self.statusMessage = "Lỗi import \(item.lastPathComponent): \(error.localizedDescription)"
                    }
                }
            }

            DispatchQueue.main.async {
                self.isImporting = false
                if imported > 0 {
                    self.statusMessage = "Đã import \(imported) game."
                } else if self.statusMessage == "Đang import…" {
                    self.statusMessage = nil
                }
                self.refresh()
            }
        }
    }

    // MARK: - Import bằng picker (di chuyển thật)

    /// Di chuyển item đã chọn từ Files vào thư mục game (chỉ dùng khi đã chọn
    /// thư mục gốc; luồng chính bây giờ là chọn folder rồi bấm ↻).
    func importPickedItems(_ urls: [URL]) {
        guard !urls.isEmpty, let gamesRoot else { return }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let fm = FileManager.default

            var moved: [String] = []
            var failures: [String] = []

            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }

                let isZip = url.pathExtension.lowercased() == "zip"
                // Zip đưa vào Imports/ (chờ giải nén), thư mục đưa thẳng vào Games/.
                let destDir = isZip ? Self.importsRoot : gamesRoot

                do {
                    try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
                    let dest = uniqueDestination(in: destDir, named: url.lastPathComponent)
                    try fm.moveItem(at: url, to: dest)
                    moved.append(dest.lastPathComponent)
                } catch {
                    failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
            }

            DispatchQueue.main.async {
                if !moved.isEmpty {
                    self.statusMessage = moved.count == 1
                        ? "Đã import: \(moved[0])"
                        : "Đã import \(moved.count) game: \(moved.joined(separator: ", "))"
                }
                if !failures.isEmpty {
                    self.statusMessage = (self.statusMessage.map { $0 + " — " } ?? "")
                        + "Lỗi: " + failures.joined(separator: "; ")
                }
                self.refresh()
            }
        }
    }

    /// Tạo đường dẫn đích chưa tồn tại trong `dir` (thêm "(2)", "(3)"… nếu trùng).
    private func uniqueDestination(in dir: URL, named name: String) -> URL {
        let fm = FileManager.default
        var dest = dir.appendingPathComponent(name, isDirectory: true)
        var counter = 2
        while fm.fileExists(atPath: dest.path) {
            let base = (name as NSString).deletingPathExtension
            let ext = (name as NSString).pathExtension
            let next = ext.isEmpty ? "\(base) (\(counter))" : "\(base) (\(counter)).\(ext)"
            dest = dir.appendingPathComponent(next, isDirectory: true)
            counter += 1
        }
        return dest
    }

    func delete(_ game: GameInfo) {
        // Chỉ xoá thư mục game nằm TRONG thư mục đã chọn (không xoá game ở
        // folder ngoài container của app — người dùng tự quản trong Files).
        guard let gamesRoot else { return }
        let url = gamesRoot.appendingPathComponent(game.folderName)
        guard url.path.hasPrefix(gamesRoot.path) else { return }
        try? FileManager.default.removeItem(at: url)
        games.removeAll { $0.id == game.id }
        metadata.lastPlayed[game.folderName] = nil
        metadata.playCount[game.folderName] = nil
        saveMetadata()
    }

    /// Ghi lần chơi cho đúng 1 game — không quét lại thư viện.
    func markPlayed(_ game: GameInfo) {
        let now = Date()
        if let index = games.firstIndex(where: { $0.id == game.id }) {
            games[index].lastPlayed = now
            games[index].playCount += 1
        }
        metadataQueue.sync {
            metadata.lastPlayed[game.folderName] = now
            metadata.playCount[game.folderName, default: 0] += 1
            saveMetadata()
        }
    }

    /// Thư mục gốc chứa game (trong thư mục người dùng đã chọn).
    func gameDirectory(for game: GameInfo) -> URL {
        guard let gamesRoot else {
            return Self.hubRoot.appendingPathComponent(game.folderName, isDirectory: true)
        }
        return gamesRoot.appendingPathComponent(game.folderName, isDirectory: true)
    }

    /// Tạo gốc tài nguyên để phục vụ file game cho WebView.
    ///
    /// - Game trong thư mục thường → gốc là thư mục chứa `index.html`.
    /// - Game đóng gói NW.js/Electron → gốc là archive `.asar` (đọc trực tiếp,
    ///   không giải nén 800MB ra đĩa).
    func resourceRoot(for game: GameInfo) throws -> GameResourceRoot {
        let base = gameDirectory(for: game)

        if game.isAsar {
            do {
                return try GameResourceRoot(packedGameIn: base)
            } catch {
                throw GameLibraryError.missingArchive
            }
        }

        if let entryPath = game.entryPath, entryPath != "." {
            return try GameResourceRoot(gameDirectory: base.appendingPathComponent(entryPath, isDirectory: true))
        }
        return try GameResourceRoot(gameDirectory: base)
    }

    enum GameLibraryError: LocalizedError {
        case missingArchive

        var errorDescription: String? {
            "Không tìm thấy gói game (.asar hoặc zip trong .exe)."
        }
    }

    // MARK: - Metadata + cache danh sách game (persist)

    private func loadMetadata() {
        guard let data = try? Data(contentsOf: metadataFile),
              let meta = try? JSONDecoder().decode(Metadata.self, from: data) else { return }
        metadata = meta

        // Khôi phục danh sách game đã quét từ lần trước → mở app là thấy ngay,
        // không phải quét lại.
        if let cached = meta.cachedGames {
            games = cached.sorted { a, b in
                let aDate = a.lastPlayed ?? .distantPast
                let bDate = b.lastPlayed ?? .distantPast
                if aDate != bDate { return aDate > bDate }
                return a.folderName < b.folderName
            }
        }
    }

    private func saveMetadata() {
        // Cập nhật cache danh sách hiện tại vào metadata trước khi ghi.
        metadata.cachedGames = games.isEmpty ? metadata.cachedGames : games
        guard let data = try? JSONEncoder().encode(metadata) else { return }
        try? data.write(to: metadataFile, options: .atomic)
    }
}
