import Foundation

/// Nguồn phục vụ file cho HTTP server nội bộ.
///
/// Game có thể nằm ở 2 dạng:
/// - **Thư mục thường** (RPG Maker, HTML5 web build) → đọc file trực tiếp từ đĩa.
/// - **`.asar` archive** (NW.js / Electron, vd TyranoBuilder) → đọc byte range
///   từ bên trong archive mà không cần giải nén.
///
/// Cả 2 dạng đều hỗ trợ **Range request** (audio/video seek trong game).
protocol GameFileSource {
    /// Đường dẫn tương đối của file, dùng dấu "/" (vd: "data/bg.png").
    var relativePath: String { get }
    /// Kích thước file (byte).
    var fileSize: Int { get }
    /// `true` nếu nguồn này hỗ trợ đọc một đoạn byte bất kỳ.
    var supportsRandomAccess: Bool { get }

    /// Đọc `count` byte bắt đầu tại `offset` (tương đối so với đầu file).
    /// - Returns: `nil` nếu đọc lỗi.
    func read(offset: Int, count: Int) -> Data?
}

// MARK: - Gốc tài nguyên

/// Gốc tài nguyên của một game: hoặc là thư mục, hoặc là archive `.asar`.
///
/// Dùng chung cho mọi game để HTTP server không cần biết game đó thuộc loại nào.
final class GameResourceRoot {
    /// Kiểu gốc tài nguyên.
    enum Kind {
        /// Game nằm trong thư mục thường (RPG Maker, HTML5).
        case directory(URL)
        /// Game nằm trong archive `.asar` (NW.js / Electron).
        case asar(AsarArchive)
        /// Game là zip gắn cuối file `.exe` (NW.js đóng gói một tệp).
        case exeZip(ExeZipArchive)
    }

    let kind: Kind

    /// Thư mục gốc trên đĩa (dùng cho WebDAV PROPFIND liệt kê file).
    var baseDirectory: URL {
        if case .directory(let url) = kind { return url }
        return URL(fileURLWithPath: "/")
    }

    /// Tạo gốc tài nguyên từ thư mục game.
    ///
    /// - Throws: `AsarArchive.AsarError` nếu thư mục chứa `.asar` hỏng.
    init(gameDirectory: URL) throws {
        if let asarURL = Self.findAsarArchive(in: gameDirectory),
           let archive = try? AsarArchive(url: asarURL) {
            self.kind = .asar(archive)
        } else {
            self.kind = .directory(gameDirectory)
        }
    }

    /// Tạo gốc tài nguyên từ archive `.asar` (dùng khi đã biết sẵn file asar).
    init(asarURL: URL) throws {
        self.kind = .asar(try AsarArchive(url: asarURL))
    }

    /// Game đóng gói: `.asar`, hoặc zip gắn trong `.exe`.
    init(packedGameIn gameDirectory: URL) throws {
        if let asarURL = Self.findAsarArchive(in: gameDirectory) {
            self.kind = .asar(try AsarArchive(url: asarURL))
        } else if let exeURL = ExeZipArchive.find(in: gameDirectory) {
            self.kind = .exeZip(try ExeZipArchive(url: exeURL))
        } else {
            throw ExeZipArchive.ZipError.notZip
        }
    }

    /// Tìm file `.asar` trong thư mục game (thường ở `resources/app.asar`).
    static func findAsarArchive(in gameDirectory: URL) -> URL? {
        let fm = FileManager.default

        // Đường dẫn quen thuộc của Electron / NW.js.
        for rel in ["resources/app.asar", "app.asar"] {
            let candidate = gameDirectory.appendingPathComponent(rel)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: candidate.path, isDirectory: &isDir), !isDir.boolValue {
                return candidate
            }
        }

        // Dò ở cấp sâu tối đa 3.
        var found: URL?
        func scan(_ dir: URL, depth: Int) {
            guard depth >= 0, found == nil else { return }
            guard let children = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.isDirectoryKey]
            ) else { return }
            for child in children {
                if found != nil { return }
                var isDir: ObjCBool = false
                fm.fileExists(atPath: child.path, isDirectory: &isDir)
                if isDir.boolValue {
                    scan(child, depth: depth - 1)
                } else if child.pathExtension.lowercased() == "asar" {
                    found = child
                    return
                }
            }
        }
        scan(gameDirectory, depth: 3)
        return found
    }

    /// Tìm nguồn file cho đường dẫn yêu cầu (vd: "data/bg.png").
    ///
    /// - Parameter path: đường dẫn tương đối, đã bỏ dấu "/" đầu.
    func source(for path: String) -> GameFileSource? {
        let clean = AsarArchive.normalize(path)
        guard !clean.isEmpty else { return nil }
        if let data = virtualFiles[clean] {
            return DataFileSource(data: data, relativePath: clean)
        }
        if let virtual = virtualSources[clean] { return virtual }

        switch kind {
        case .directory(let root):
            let fileURL = root.appendingPathComponent(clean)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDir),
                  !isDir.boolValue else {
                // Không có trong thư mục game → thử thư mục runtime đi kèm app.
                if let runtime = runtimeDirectory {
                    let runtimeURL = runtime.appendingPathComponent(clean)
                    if FileManager.default.fileExists(atPath: runtimeURL.path, isDirectory: &isDir),
                       !isDir.boolValue {
                        return DirectoryFileSource(fileURL: runtimeURL, relativePath: clean)
                    }
                }
                return nil
            }
            return DirectoryFileSource(fileURL: fileURL, relativePath: clean)

        case .asar(let archive):
            if let entry = archive.entry(at: clean), !entry.isDirectory {
                return AsarFileSource(archive: archive, entry: entry)
            }
            return nil

        case .exeZip(let archive):
            if let entry = archive.entry(at: clean), !entry.isDirectory {
                return ExeZipFileSource(archive: archive, entry: entry)
            }
            return nil
        }
    }

    /// Thư mục runtime đi kèm app (Godot / KiriKiri / Ruffle), dùng làm fallback
    /// khi file không có trong thư mục game.
    var runtimeDirectory: URL?

    /// File ảo ở gốc thư mục game (tên → nội dung), ưu tiên hơn file thật —
    /// vd `patch.xp3` giả lập plugin cho KiriKiri (`KiriKiriPatch`).
    var virtualFiles: [String: Data] = [:]

    /// File ảo trỏ vào một đoạn của tệp thật — vd pck Godot nhúng trong `.exe`.
    var virtualSources: [String: GameFileSource] = [:]

    /// HTML sinh động cho `index.html` (runtime cần config riêng, vd Godot).
    ///
    /// Khi khác nil, server phục vụ nội dung này cho đường dẫn `index.html`
    /// thay vì file thật trong thư mục game.
    var customIndexHTML: String?

    /// `true` nếu gốc này là game đóng gói (`.asar` hoặc zip trong exe).
    var isAsar: Bool {
        if case .directory = kind { return false }
        return true
    }
}

// MARK: - File ảo trong bộ nhớ

final class DataFileSource: GameFileSource {
    let relativePath: String
    let supportsRandomAccess = true
    private let data: Data

    var fileSize: Int { data.count }

    init(data: Data, relativePath: String) {
        self.data = data
        self.relativePath = relativePath
    }

    func read(offset: Int, count: Int) -> Data? {
        guard offset >= 0, offset <= data.count else { return nil }
        return data.subdata(in: offset..<min(offset + max(count, 0), data.count))
    }
}

// MARK: - Thư mục thường

/// Đọc file trực tiếp từ thư mục game trên đĩa.
final class DirectoryFileSource: GameFileSource {
    let relativePath: String
    let fileSize: Int
    let supportsRandomAccess = true

    private let fileURL: URL

    init(fileURL: URL, relativePath: String) {
        self.fileURL = fileURL
        self.relativePath = relativePath
        let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        self.fileSize = (attrs?[.size] as? Int) ?? 0
    }

    func read(offset: Int, count: Int) -> Data? {
        guard count > 0 else { return Data() }
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? handle.close() }
        do {
            if offset > 0 { try handle.seek(toOffset: UInt64(offset)) }
            return try handle.read(upToCount: count)
        } catch {
            return nil
        }
    }
}

// MARK: - Đoạn byte trong tệp thật

/// Một đoạn `[offset, offset + size)` của tệp trên đĩa, phục vụ như tệp riêng.
/// `prefix`: byte đứng trước đoạn (tệp con trong .rpa của Ren'Py có thể có).
final class FileSliceSource: GameFileSource {
    let relativePath: String
    let fileSize: Int
    let supportsRandomAccess = true
    private let file: DirectoryFileSource
    private let offset: Int
    private let prefix: Data

    init(fileURL: URL, offset: Int, size: Int, relativePath: String, prefix: Data = Data()) {
        file = DirectoryFileSource(fileURL: fileURL, relativePath: relativePath)
        self.offset = offset
        self.prefix = prefix
        self.fileSize = prefix.count + size
        self.relativePath = relativePath
    }

    func read(offset: Int, count: Int) -> Data? {
        guard offset >= 0, offset < fileSize else { return Data() }
        let end = min(offset + count, fileSize)
        var out = Data()
        if offset < prefix.count {
            out.append(prefix.subdata(in: offset ..< min(end, prefix.count)))
        }
        let start = max(offset, prefix.count)
        if end > start {
            guard let body = file.read(offset: self.offset + start - prefix.count, count: end - start) else { return nil }
            out.append(body)
        }
        return out
    }
}

// MARK: - .asar archive

/// Đọc file từ bên trong archive `.asar` mà không cần giải nén.
final class AsarFileSource: GameFileSource {
    let relativePath: String
    let fileSize: Int
    let supportsRandomAccess = true

    private let archive: AsarArchive
    private let entry: AsarArchive.Entry

    init(archive: AsarArchive, entry: AsarArchive.Entry) {
        self.archive = archive
        self.entry = entry
        self.relativePath = entry.path
        self.fileSize = entry.size
    }

    func read(offset: Int, count: Int) -> Data? {
        guard count > 0 else { return Data() }
        guard offset >= 0, offset + count <= fileSize else {
            // Tràn vùng — chỉ lấy phần còn lại.
            guard offset < fileSize else { return Data() }
            return read(offset: offset, count: fileSize - offset)
        }

        if entry.isUnpacked {
            guard let fileURL = archive.unpackedURL(for: entry) else { return nil }
            guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
            defer { try? handle.close() }
            do {
                if offset > 0 { try handle.seek(toOffset: UInt64(offset)) }
                return try handle.read(upToCount: count)
            } catch {
                return nil
            }
        }

        guard let entryOffset = entry.offset else { return nil }
        return archive.read(
            absoluteOffset: archive.dataOffset + entryOffset + offset,
            count: count
        )
    }
}
