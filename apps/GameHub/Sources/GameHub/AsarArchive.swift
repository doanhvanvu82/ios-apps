import Foundation

/// Đọc archive `.asar` (định dạng của Electron / NW.js) mà không cần giải nén ra đĩa.
///
/// # Định dạng .asar
///
/// ```
/// offset 0  : uint32 = 4                 (kích thước pickle header đầu tiên)
/// offset 4  : uint32 = headerSize        (kích thước pickle chứa JSON header)
/// offset 8  : uint32 = headerStringSize  (kích thước chuỗi JSON + padding)
/// offset 12 : uint32 = headerStringLen   (độ dài JSON thực tế)
/// offset 16 : JSON header
/// offset 8 + headerSize : dữ liệu file
/// ```
///
/// JSON header có dạng:
/// ```json
/// {"files": {"index.html": {"size": 5185, "offset": "0"},
///             "data": {"files": { ... }}}}
/// ```
/// - Node có `"files"` ⇒ thư mục
/// - `"unpacked": true` ⇒ file nằm ngoài archive, trong thư mục `*.asar.unpacked`
/// - `"offset"` là chỉ số byte tương đối so với `dataOffset`
///
/// # Vì sao cần đọc trực tiếp?
///
/// Game NW.js/Electron thường có `app.asar` nặng 700–850 MB. Giải nén ra đĩa
/// trên iPhone sẽ tốn gấp đôi dung lượng và mất thời gian. Thay vào đó app
/// đọc thẳng byte range cần thiết từ archive rồi stream ra WebView.
final class AsarArchive {

    /// Một entry trong archive (file hoặc thư mục).
    struct Entry {
        /// Đường dẫn tương đối bên trong archive, dùng dấu "/" (vd: "data/bg.png").
        let path: String
        /// Kích thước file (byte). 0 cho thư mục.
        let size: Int
        /// Offset của dữ liệu trong file .asar. `nil` cho thư mục.
        let offset: Int?
        /// `true` nếu file nằm ngoài archive (đọc từ filesystem).
        let isUnpacked: Bool
        /// `true` nếu đây là thư mục.
        let isDirectory: Bool
    }

    private struct HeaderFile: Decodable {
        var size: Int?
        var offset: String?
        var unpacked: Bool?
        var files: [String: HeaderFile]?
    }

    private struct Header: Decodable {
        var files: [String: HeaderFile]
    }

    /// URL của file `.asar`.
    let url: URL

    /// Offset bắt đầu dữ liệu file trong archive.
    let dataOffset: Int

    /// Cây thư mục của archive.
    private let root: [String: HeaderFile]

    /// Flattened index: path → Entry. Dựng 1 lần lúc mở archive.
    private var index: [String: Entry] = [:]

    /// File handle để đọc byte từ archive (mở lazily, giữ mở để tăng tốc).
    private var handle: FileHandle?

    private let lock = NSLock()

    // MARK: - Mở archive

    /// Mở archive và index toàn bộ entry bên trong.
    ///
    /// - Throws: `AsarError.invalidArchive` nếu file không phải .asar hợp lệ.
    init(url: URL) throws {
        self.url = url

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        // Đọc 16 byte header đầu.
        let prefix = try handle.read(upToCount: 16) ?? Data()
        guard prefix.count == 16 else { throw AsarError.invalidArchive }

        let headerSize = prefix.readUInt32LE(at: 4)
        let headerStringLen = prefix.readUInt32LE(at: 12)

        // Chặn header khổng lồ (phòng file hỏng).
        guard headerStringLen > 0, headerStringLen < 64 * 1024 * 1024 else {
            throw AsarError.invalidArchive
        }

        // JSON nằm ngay sau 16 byte, được padding tới `headerStringSize`.
        try handle.seek(toOffset: 16)
        guard let jsonData = try handle.read(upToCount: Int(headerStringLen)) else {
            throw AsarError.invalidArchive
        }

        let decoded = try JSONDecoder().decode(Header.self, from: jsonData)
        self.root = decoded.files
        self.dataOffset = 8 + headerSize
    }

    deinit {
        try? handle?.close()
    }

    // MARK: - Truy vấn

    /// Tất cả entry trong archive (file + thư mục), dạng flat.
    var entries: [Entry] {
        lock.lock()
        defer { lock.unlock() }
        if index.isEmpty { buildIndex() }
        return Array(index.values)
    }

    /// Tìm entry theo đường dẫn tương đối (vd: "index.html", "data/bg.png").
    func entry(at path: String) -> Entry? {
        lock.lock()
        defer { lock.unlock() }
        if index.isEmpty { buildIndex() }
        return index[Self.normalize(path)]
    }

    /// Kiểm tra archive có chứa file `index.html` ở gốc hay không.
    var hasRootIndexHTML: Bool {
        entry(at: "index.html") != nil
    }

    /// Đọc `count` byte bắt đầu tại `offset` (tuyệt đối trong file .asar).
    ///
    /// - Returns: `nil` nếu đọc lỗi.
    func read(absoluteOffset: Int, count: Int) -> Data? {
        guard count > 0 else { return Data() }

        lock.lock()
        if handle == nil {
            handle = try? FileHandle(forReadingFrom: url)
        }
        guard let handle else {
            lock.unlock()
            return nil
        }
        lock.unlock()

        do {
            try handle.seek(toOffset: UInt64(absoluteOffset))
            return try handle.read(upToCount: count)
        } catch {
            return nil
        }
    }

    /// Đường dẫn tuyệt đối trong filesystem cho entry `unpacked`.
    ///
    /// File unpacked nằm trong thư mục `app.asar.unpacked` cạnh file `app.asar`,
    /// giữ nguyên cấu trúc thư mục bên trong archive.
    func unpackedURL(for entry: Entry) -> URL? {
        guard entry.isUnpacked else { return nil }
        let unpackedRoot = url.deletingLastPathComponent()
            .appendingPathComponent(url.lastPathComponent + ".unpacked", isDirectory: true)
        return unpackedRoot.appendingPathComponent(entry.path)
    }

    /// Đọc toàn bộ nội dung của một entry (dùng cho file nhỏ như html/js).
    ///
    /// - Note: File `unpacked` được đọc từ filesystem.
    func contents(of entry: Entry) -> Data? {
        if entry.isDirectory { return nil }

        if entry.isUnpacked {
            guard let fileURL = unpackedURL(for: entry) else { return nil }
            return try? Data(contentsOf: fileURL, options: .mappedIfSafe)
        }

        guard let offset = entry.offset else { return nil }
        return read(absoluteOffset: dataOffset + offset, count: entry.size)
    }

    // MARK: - Index building

    private func buildIndex() {
        var result: [String: Entry] = [:]
        for (name, meta) in root {
            Self.addEntry(name: name, meta: meta, into: &result)
        }
        index = result
    }

    /// Ghi 1 entry vào index, đồng thời đệ quy vào thư mục con.
    private static func addEntry(
        name: String,
        meta: HeaderFile,
        into result: inout [String: Entry]
    ) {
        if let children = meta.files {
            // Thư mục — index cả thư mục lẫn các entry bên trong.
            result[name] = Entry(
                path: name,
                size: 0,
                offset: nil,
                isUnpacked: meta.unpacked ?? false,
                isDirectory: true
            )
            for (childName, childMeta) in children {
                addEntry(
                    name: "\(name)/\(childName)",
                    meta: childMeta,
                    into: &result
                )
            }
        } else {
            result[name] = Entry(
                path: name,
                size: meta.size ?? 0,
                offset: meta.offset.flatMap { Int($0) },
                isUnpacked: meta.unpacked ?? false,
                isDirectory: false
            )
        }
    }

    /// Chuẩn hoá đường dẫn: bỏ dấu "/" đầu/cuối, bỏ "./" ở đầu.
    static func normalize(_ path: String) -> String {
        var parts = path.split(separator: "/").map(String.init)
        if parts.first == "." { parts.removeFirst() }
        return parts.joined(separator: "/")
    }

    // MARK: - Errors

    enum AsarError: LocalizedError {
        case invalidArchive

        var errorDescription: String? {
            "File .asar không hợp lệ hoặc bị hỏng."
        }
    }
}

// MARK: - Data helpers

private extension Data {
    /// Đọc UInt32 little-endian tại offset cho trước.
    func readUInt32LE(at offset: Int) -> Int {
        guard count >= offset + 4 else { return 0 }
        return Int(self[offset])
            | (Int(self[offset + 1]) << 8)
            | (Int(self[offset + 2]) << 16)
            | (Int(self[offset + 3]) << 24)
    }
}
