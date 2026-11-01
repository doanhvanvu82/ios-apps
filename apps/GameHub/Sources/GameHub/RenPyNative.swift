import Foundation
import ZIPFoundation

/// Chạy game Ren'Py bản PC bằng runtime web Ren'Py đi kèm app (không build lại).
///
/// Runtime web (`Resources/Runtime/renpy`) chỉ có CPython + stdlib. Bản build
/// web chuẩn đóng gói `main.py` + `renpy/` + `game/` vào `game.zip` rồi giải nén
/// cả zip vào RAM — game PC 1–5 GB không thể làm vậy. Ở đây:
/// - `game.zip` dựng trong RAM khi mở game: `main.py` (= `<Tên>.py`, bản sao
///   renpy.py), `renpy/` của chính game (bỏ `.pyc` Python 3.9, web dùng 3.11
///   biên dịch lại từ `.py`) và script/tệp nhỏ trong `game/`.
/// - Tệp lớn liệt kê ở `gh_lazy.json`, `gamehub_lazyfs.js` gắn vào FS và đọc
///   theo Range (`?gh_b64=1`) khi Python mở.
/// - Video khai báo "video -" trong `renpyweb_remote_files.txt`: Ren'Py web chỉ
///   phát video qua URL; video đọc từ FS làm `video_stop` ném lỗi, treo game.
/// - `.rpa` > 2 GB được tách thành từng tệp con (RenPyArchive): runtime là wasm32,
///   offset vượt 2 GB làm Ren'Py báo "Python int too large to convert to C long".
enum RenPyNative {
    /// Runtime web đi kèm theo nhánh major.minor. Module Cython trong wasm phải
    /// khớp mã Python của `renpy/` → chỉ nhận game cùng nhánh.
    static let runtimes: [String: EngineRuntime] = ["8.3": .renpy, "8.5": .renpy85]
    static var supportedVersions: String { runtimes.keys.sorted().map { $0 + ".x" }.joined(separator: ", ") }

    static func runtime(forVersion version: String) -> EngineRuntime? {
        let branch = version.split(separator: ".").prefix(2).joined(separator: ".")
        return runtimes[branch]
    }

    private static let scriptExtensions: Set<String> = ["rpy", "rpyc", "rpym", "rpymc", "py", "txt", "json"]
    private static let videoExtensions: Set<String> = ["ogv", "webm", "mp4", "mkv", "avi"]
    /// `_unpacked_archive`: bản giải nén trùng của .rpa (unrpa/unren) — script
    /// .rpyc trùng làm Ren'Py báo trùng label.
    private static let skippedDirectories: Set<String> = ["saves", "cache", "__pycache__", "_unpacked_archive"]
    /// RPA lớn hơn mức này được tách thành từng tệp con (giới hạn offset wasm32).
    private static let rpaSplitLimit = Int(Int32.max)
    /// Tệp nhỏ hơn cho thẳng vào zip — đỡ hàng nghìn lần XHR lúc chơi.
    private static let inlineLimit = 64 * 1024

    enum SetupError: LocalizedError {
        case notRenPy
        case unsupportedVersion(String)
        case noPythonSources

        var errorDescription: String? {
            switch self {
            case .notRenPy:
                return "Không tìm thấy renpy/, game/ và tệp .py khởi động của game Ren'Py."
            case .unsupportedVersion(let version):
                return "Game dùng Ren'Py \(version), app chỉ có runtime Ren'Py \(supportedVersions)."
            case .noPythonSources:
                return "Thư mục renpy/ của game không kèm mã nguồn .py (chỉ có .pyc), runtime web không nạp được."
            }
        }
    }

    /// Phiên bản Ren'Py của game, đọc từ `renpy/vc_version.py`.
    static func version(in gameDir: URL) -> String? {
        let url = gameDir.appendingPathComponent("renpy/vc_version.py")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") where line.hasPrefix("version =") {
            return line.split(separator: "'").dropFirst().first.map(String.init)
        }
        return nil
    }

    static func configure(root: GameResourceRoot, gameDir: URL, title: String) throws {
        let fm = FileManager.default
        let topLevel = (try? fm.contentsOfDirectory(atPath: gameDir.path)) ?? []
        guard let mainScript = topLevel.sorted().first(where: { $0.hasSuffix(".py") }),
              fm.fileExists(atPath: gameDir.appendingPathComponent("renpy").path),
              fm.fileExists(atPath: gameDir.appendingPathComponent("game").path) else {
            throw SetupError.notRenPy
        }
        let version = Self.version(in: gameDir) ?? "?"
        guard let runtime = runtime(forVersion: version) else { throw SetupError.unsupportedVersion(version) }
        guard fm.fileExists(atPath: gameDir.appendingPathComponent("renpy/bootstrap.py").path) else {
            throw SetupError.noPythonSources
        }

        let archive = try Archive(accessMode: .create)
        try archive.addEntry(with: "main.py", fileURL: gameDir.appendingPathComponent(mainScript), compressionMethod: .none)
        var lazy: [[Any]] = []
        var videos: [String] = []
        var zipped = 0

        for top in ["renpy", "game"] {
            let base = gameDir.appendingPathComponent(top, isDirectory: true)
            guard let walker = fm.enumerator(at: base, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey]) else { continue }
            for case let url as URL in walker {
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
                if values?.isDirectory == true {
                    if skippedDirectories.contains(url.lastPathComponent) { walker.skipDescendants() }
                    continue
                }
                let rel = top + "/" + url.path.dropFirst(base.path.count + 1)
                let ext = url.pathExtension.lowercased()
                let size = values?.fileSize ?? 0
                if ext == "pyc", fm.fileExists(atPath: url.deletingPathExtension().appendingPathExtension("py").path) {
                    continue
                }
                if top == "game", ext == "rpa", size > rpaSplitLimit,
                   let entries = try? RenPyArchive.entries(of: url) {
                    try splitArchive(url, entries: entries, into: archive, root: root,
                                     lazy: &lazy, videos: &videos, zipped: &zipped)
                    continue
                }
                if top == "game", videoExtensions.contains(ext) {
                    videos.append(String(rel.dropFirst("game/".count)))
                } else if top == "renpy" || scriptExtensions.contains(ext) || size <= inlineLimit {
                    try archive.addEntry(with: rel, fileURL: url, compressionMethod: .none)
                    zipped += size
                } else {
                    lazy.append([rel, size])
                }
            }
        }
        let remote = videos.map { "\($0)\nvideo -\n" }.joined()
        let remoteData = Data(remote.utf8)
        try archive.addEntry(with: "game/renpyweb_remote_files.txt", type: .file,
                             uncompressedSize: Int64(remoteData.count), compressionMethod: .none) { position, size in
            remoteData.subdata(in: Int(position)..<Int(position) + size)
        }

        guard let zip = archive.data,
              let runtimeDir = EngineRuntime.directory(for: runtime),
              let index = try? String(contentsOf: runtimeDir.appendingPathComponent("index.html"), encoding: .utf8)
        else { throw SetupError.notRenPy }

        root.runtimeDirectory = runtimeDir
        root.customIndexHTML = index.replacingOccurrences(of: "<title>", with: "<title>\(title) — ")
        root.virtualFiles["game.zip"] = zip
        root.virtualFiles["gh_lazy.json"] = try JSONSerialization.data(withJSONObject: lazy)
        let lazyBytes = lazy.reduce(0) { $0 + ($1[1] as? Int ?? 0) }
        AppLog.info("Ren'Py \(version) (runtime \(runtimeDir.lastPathComponent)): zip \(zipped / 1_048_576) MB, \(lazy.count) tệp lazy (\(lazyBytes / 1_048_576) MB), \(videos.count) video qua URL")
    }
}

extension RenPyNative {
    /// Mỗi tệp con của rpa: script/tệp nhỏ → vào zip; video → URL (đoạn của rpa);
    /// còn lại → tệp lazy. Mọi đoạn đều là FileSliceSource của chính tệp rpa.
    fileprivate static func splitArchive(_ url: URL, entries: [String: RenPyArchive.Entry], into archive: Archive,
                                         root: GameResourceRoot, lazy: inout [[Any]], videos: inout [String],
                                         zipped: inout Int) throws {
        for (name, entry) in entries {
            let rel = "game/" + name
            let ext = (name as NSString).pathExtension.lowercased()
            let size = entry.prefix.count + entry.length
            let slice = FileSliceSource(fileURL: url, offset: entry.offset, size: entry.length,
                                        relativePath: rel, prefix: entry.prefix)
            if videoExtensions.contains(ext) {
                root.virtualSources[rel] = slice
                videos.append(name)
            } else if scriptExtensions.contains(ext) || size <= inlineLimit {
                guard let data = slice.read(offset: 0, count: size) else { continue }
                try archive.addEntry(with: rel, type: .file, uncompressedSize: Int64(data.count),
                                     compressionMethod: .none) { position, chunk in
                    data.subdata(in: Int(position) ..< Int(position) + chunk)
                }
                zipped += size
            } else {
                root.virtualSources[rel] = slice
                lazy.append([rel, size])
            }
        }
        AppLog.info("Ren'Py: tách \(url.lastPathComponent) (\(entries.count) tệp) — rpa > 2 GB")
    }
}

private extension Archive {
    /// Tên trong zip khác đường dẫn tệp (vd `main.py`) nên tự cấp dữ liệu.
    func addEntry(with path: String, fileURL: URL, compressionMethod: CompressionMethod) throws {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        let size = Int64((try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        try addEntry(with: path, type: .file, uncompressedSize: size, compressionMethod: compressionMethod) { position, chunk in
            try handle.seek(toOffset: UInt64(position))
            return try handle.read(upToCount: chunk) ?? Data()
        }
    }
}
