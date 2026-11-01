import Foundation
import ZIPFoundation

/// Zip gắn vào cuối file `.exe` (NW.js: `copy /b nw.exe+app.nw game.exe`).
///
/// Offset trong central directory tính từ đầu phần zip, không phải đầu exe
/// → phải cộng độ lệch `prefix` (= vị trí EOCD − cỡ CD − offset CD). Đọc từng
/// tệp khi cần, không giải nén cả game (có game zip 1 GB+).
final class ExeZipArchive {
    struct Entry {
        let path: String
        let method: UInt16
        let compressedSize: Int
        let size: Int
        let localHeaderOffset: Int
        var isDirectory: Bool { path.hasSuffix("/") }
    }

    enum ZipError: Error { case notZip, corrupt }

    let url: URL
    private(set) var entries: [String: Entry] = [:]
    private let prefix: Int
    private let fileSize: Int
    private let lock = NSLock()
    private var dataOffsets: [String: Int] = [:]
    /// Tệp nén deflate: giải nén cả tệp một lần rồi cắt đoạn theo Range.
    private let inflated = NSCache<NSString, NSData>()

    init(url: URL) throws {
        self.url = url
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let size = Int(try handle.seekToEnd())
        fileSize = size

        let tailLength = min(size, 65_557)
        try handle.seek(toOffset: UInt64(size - tailLength))
        guard let tail = try handle.read(upToCount: tailLength),
              let eocd = Self.lastIndex(of: [0x50, 0x4b, 0x05, 0x06], in: tail) else { throw ZipError.notZip }
        let eocdPos = size - tailLength + eocd

        var count = Int(tail.le16(eocd + 10))
        var cdSize = Int(tail.le32(eocd + 12))
        var cdOffset = Int(tail.le32(eocd + 16))
        var cdEnd = eocdPos
        if (cdOffset == 0xFFFF_FFFF || count == 0xFFFF), eocd >= 20,
           tail.le32(eocd - 20) == 0x0706_4b50 {
            // Zip64: locator ngay trước EOCD, bản ghi EOCD64 (56 byte) ngay trước locator.
            if let record = Self.read(handle, at: eocdPos - 20 - 56, count: 56), record.le32(0) == 0x0606_4b50 {
                count = Int(record.le64(32))
                cdSize = Int(record.le64(40))
                cdOffset = Int(record.le64(48))
                cdEnd = eocdPos - 20 - 56
            }
        }
        prefix = cdEnd - cdSize - cdOffset
        guard prefix >= 0, cdSize > 0,
              let cd = Self.read(handle, at: prefix + cdOffset, count: cdSize) else { throw ZipError.corrupt }

        var pos = 0
        for _ in 0..<count {
            guard pos + 46 <= cd.count, cd.le32(pos) == 0x0201_4b50 else { throw ZipError.corrupt }
            let flags = cd.le16(pos + 8)
            let method = cd.le16(pos + 10)
            var compressed = Int(cd.le32(pos + 20))
            var uncompressed = Int(cd.le32(pos + 24))
            let nameLen = Int(cd.le16(pos + 28))
            let extraLen = Int(cd.le16(pos + 30))
            let commentLen = Int(cd.le16(pos + 32))
            var local = Int(cd.le32(pos + 42))
            guard pos + 46 + nameLen + extraLen <= cd.count else { throw ZipError.corrupt }
            let nameData = cd.subdata(in: pos + 46 ..< pos + 46 + nameLen)
            Self.applyZip64(cd.subdata(in: pos + 46 + nameLen ..< pos + 46 + nameLen + extraLen),
                            uncompressed: &uncompressed, compressed: &compressed, local: &local)
            let name = Self.decodeName(nameData, utf8Flag: flags & 0x0800 != 0)
            let path = AsarArchive.normalize(name) + (name.hasSuffix("/") ? "/" : "")
            if !path.isEmpty {
                entries[path] = Entry(path: path, method: method, compressedSize: compressed,
                                      size: uncompressed, localHeaderOffset: local)
            }
            pos += 46 + nameLen + extraLen + commentLen
        }
        inflated.totalCostLimit = 96 * 1024 * 1024
    }

    /// Exe ở gốc thư mục game có zip gắn kèm chứa `index.html` ở gốc.
    static func find(in gameDirectory: URL) -> URL? {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: gameDirectory, includingPropertiesForKeys: [.fileSizeKey]) else { return nil }
        return items
            .filter { $0.pathExtension.lowercased() == "exe" }
            .first { (try? ExeZipArchive(url: $0))?.entry(at: "index.html") != nil }
    }

    func entry(at path: String) -> Entry? {
        let clean = AsarArchive.normalize(path)
        if let file = entries[clean] { return file }
        if let dir = entries[clean + "/"] { return dir }
        // Thư mục không có bản ghi riêng nhưng có tệp con.
        let prefix = clean + "/"
        guard entries.keys.contains(where: { $0.hasPrefix(prefix) }) else { return nil }
        return Entry(path: prefix, method: 0, compressedSize: 0, size: 0, localHeaderOffset: 0)
    }

    func read(_ entry: Entry, offset: Int, count: Int) -> Data? {
        guard count > 0, offset < entry.size else { return Data() }
        let end = min(entry.size, offset + count)
        guard let start = dataOffset(of: entry) else { return nil }

        switch entry.method {
        case 0:
            guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
            defer { try? handle.close() }
            return Self.read(handle, at: start + offset, count: end - offset)
        case 8:
            guard let data = inflate(entry, dataStart: start) else { return nil }
            return data.subdata(in: offset..<min(end, data.count))
        default:
            return nil
        }
    }

    private func dataOffset(of entry: Entry) -> Int? {
        lock.lock()
        if let cached = dataOffsets[entry.path] { lock.unlock(); return cached }
        lock.unlock()
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let headerPos = prefix + entry.localHeaderOffset
        guard let header = Self.read(handle, at: headerPos, count: 30), header.count == 30,
              header.le32(0) == 0x0403_4b50 else { return nil }
        let start = headerPos + 30 + Int(header.le16(26)) + Int(header.le16(28))
        guard start + entry.compressedSize <= fileSize else { return nil }
        lock.lock()
        dataOffsets[entry.path] = start
        lock.unlock()
        return start
    }

    private func inflate(_ entry: Entry, dataStart: Int) -> Data? {
        let key = entry.path as NSString
        if let cached = inflated.object(forKey: key) { return cached as Data }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var output = Data(capacity: entry.size)
        do {
            _ = try Data.decompress(
                size: Int64(entry.compressedSize), bufferSize: 64 * 1024, skipCRC32: true,
                provider: { position, chunk in
                    Self.read(handle, at: dataStart + Int(position), count: chunk) ?? Data()
                },
                consumer: { output.append($0) })
        } catch {
            return nil
        }
        inflated.setObject(output as NSData, forKey: key, cost: output.count)
        return output
    }

    // MARK: - Tiện ích

    private static func read(_ handle: FileHandle, at offset: Int, count: Int) -> Data? {
        guard offset >= 0, count >= 0 else { return nil }
        do {
            try handle.seek(toOffset: UInt64(offset))
            return try handle.read(upToCount: count) ?? Data()
        } catch {
            return nil
        }
    }

    private static func lastIndex(of signature: [UInt8], in data: Data) -> Int? {
        guard data.count >= 22 else { return nil }
        let bytes = [UInt8](data)
        var i = bytes.count - 22
        while i >= 0 {
            if bytes[i] == signature[0], bytes[i + 1] == signature[1],
               bytes[i + 2] == signature[2], bytes[i + 3] == signature[3] { return i }
            i -= 1
        }
        return nil
    }

    /// Trường extra 0x0001 (zip64) thay giá trị 0xFFFFFFFF theo thứ tự cố định.
    private static func applyZip64(_ extra: Data, uncompressed: inout Int, compressed: inout Int, local: inout Int) {
        var pos = 0
        while pos + 4 <= extra.count {
            let id = extra.le16(pos), len = Int(extra.le16(pos + 2))
            if id == 0x0001 {
                var field = pos + 4
                if uncompressed == 0xFFFF_FFFF, field + 8 <= extra.count { uncompressed = Int(extra.le64(field)); field += 8 }
                if compressed == 0xFFFF_FFFF, field + 8 <= extra.count { compressed = Int(extra.le64(field)); field += 8 }
                if local == 0xFFFF_FFFF, field + 8 <= extra.count { local = Int(extra.le64(field)) }
                return
            }
            pos += 4 + len
        }
    }

    /// Tên tệp: cờ UTF-8, hoặc UTF-8 hợp lệ, hoặc Shift_JIS (zip tạo trên
    /// Windows tiếng Nhật), cuối cùng là CP437/Latin-1.
    private static func decodeName(_ data: Data, utf8Flag: Bool) -> String {
        if let s = String(data: data, encoding: .utf8) { return s }
        if !utf8Flag, let s = String(data: data, encoding: .shiftJIS) { return s }
        return String(data: data, encoding: .isoLatin1) ?? ""
    }
}

/// Một tệp trong zip gắn kèm exe.
final class ExeZipFileSource: GameFileSource {
    let relativePath: String
    let fileSize: Int
    let supportsRandomAccess = true
    private let archive: ExeZipArchive
    private let entry: ExeZipArchive.Entry

    init(archive: ExeZipArchive, entry: ExeZipArchive.Entry) {
        self.archive = archive
        self.entry = entry
        relativePath = entry.path
        fileSize = entry.size
    }

    func read(offset: Int, count: Int) -> Data? {
        archive.read(entry, offset: offset, count: count)
    }
}

private extension Data {
    func le16(_ at: Int) -> UInt16 {
        UInt16(self[startIndex + at]) | UInt16(self[startIndex + at + 1]) << 8
    }
    func le32(_ at: Int) -> UInt32 {
        UInt32(le16(at)) | UInt32(le16(at + 2)) << 16
    }
    func le64(_ at: Int) -> UInt64 {
        UInt64(le32(at)) | UInt64(le32(at + 4)) << 32
    }
}
