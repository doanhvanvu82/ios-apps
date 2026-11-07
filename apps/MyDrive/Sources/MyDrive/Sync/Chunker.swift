import Foundation

/// Thông tin 1 part của file lớn.
struct FilePart: Codable, Hashable {
    var index: Int              // 0-based
    var size: Int64
    var accountEmail: String    // account chứa part
    var driveFileId: String?    // nil = chưa upload xong
    var remoteName: String      // "<tên>.myd-part-0001"
}

enum Chunker {
    /// Ngưỡng chia nhỏ: file ≥ 256 MiB → chia parts.
    static let partSize: Int64 = 256 * 1024 * 1024

    /// True nếu file cần chia parts.
    static func needsChunking(size: Int64) -> Bool {
        size >= partSize
    }

    /// Danh sách part (kích thước) của file có kích thước `size`.
    static func planParts(size: Int64) -> [(index: Int, size: Int64)] {
        guard needsChunking(size: size) else { return [(0, size)] }
        var parts: [(index: Int, size: Int64)] = []
        var remaining = size
        var index = 0
        while remaining > 0 {
            let s = min(partSize, remaining)
            parts.append((index, s))
            remaining -= s
            index += 1
        }
        return parts
    }

    /// Tên Drive file của part (tên file gốc + đuôi .myd-part-XXXX).
    static func partName(fileName: String, index: Int) -> String {
        "\(fileName).myd-part-\(String(format: "%04d", index))"
    }

    /// Đọc 1 phần của file (offset, size) — dùng khi upload từng part.
    static func readRange(from fileURL: URL, offset: Int64, length: Int64) throws -> Data {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(offset))
        return handle.readData(ofLength: Int(length))
    }

    /// Nối danh sách part (từ temp file đã tải) thành file đích.
    /// Trả lỗi nếu thiếu part (không nối bừa).
    static func assemble(parts: [(url: URL, size: Int64)], to destURL: URL) throws {
        let fm = FileManager.default
        // Nếu chỉ 1 part và size khớp → move luôn.
        if parts.count == 1 {
            if fm.fileExists(atPath: destURL.path) { try fm.removeItem(at: destURL) }
            try fm.moveItem(at: parts[0].url, to: destURL)
            return
        }
        // Nhiều part: ghi tuần tự vào file đích (stream, không giữ trong RAM).
        if fm.fileExists(atPath: destURL.path) { try fm.removeItem(at: destURL) }
        fm.createFile(atPath: destURL.path, contents: nil)
        let out = try FileHandle(forWritingTo: destURL)
        defer { try? out.close() }
        for part in parts {
            let size = (try? fm.attributesOfItem(atPath: part.url.path)[.size] as? Int64) ?? 0
            guard size == part.size else {
                throw DriveError.http(status: 0, reason: "partSizeMismatch", message: "\(part.url.lastPathComponent): kỳ vọng \(part.size), thực tế \(size)")
            }
            let handle = try FileHandle(forReadingFrom: part.url)
            defer { try? handle.close() }
            // Ghi theo block 8 MB để không ăn RAM với part 256 MB.
            while let block = try? handle.readData(ofLength: 8 * 1024 * 1024), !block.isEmpty {
                try out.write(contentsOf: block)
            }
        }
        // Xoá part files sau khi nối xong.
        for part in parts {
            try? fm.removeItem(at: part.url)
            _ = part
        }
    }
}
