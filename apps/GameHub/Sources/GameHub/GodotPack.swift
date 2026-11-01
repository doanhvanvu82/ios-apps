import Foundation

/// Đọc thông tin version từ header file `.pck` của Godot.
///
/// Định dạng pack: magic `GDPC` (4 byte) | pack format version (4) |
/// engine major (4) | engine minor (4) | engine patch (4) — little-endian.
///
/// Dùng để chọn runtime web phù hợp: major >= 4 → Godot 4.x (WebGL2),
/// major 3 → Godot 3.x (WebGL1/WebGL2).
enum GodotPack {
    struct Version {
        let major: Int
        let minor: Int
        let patch: Int
    }

    /// Đọc version từ file `.pck` (hoặc pck nhúng bắt đầu tại `offset`);
    /// `nil` nếu không phải Godot pack.
    static func version(of pckURL: URL, offset: Int = 0) -> Version? {
        guard let handle = try? FileHandle(forReadingFrom: pckURL) else { return nil }
        defer { try? handle.close() }
        try? handle.seek(toOffset: UInt64(offset))
        guard let header = try? handle.read(upToCount: 20), header.count == 20 else { return nil }
        guard header.prefix(4) == Data("GDPC".utf8) else { return nil }

        func u32(_ range: Range<Int>) -> Int {
            header[range].withUnsafeBytes { Int(UInt32(littleEndian: $0.load(as: UInt32.self))) }
        }
        return Version(major: u32(8..<12), minor: u32(12..<16), patch: u32(16..<20))
    }

    /// Pck nhúng cuối `.exe` (export "Embed PCK"): 12 byte cuối là
    /// `kích thước pck (UInt64 LE)` + `"GDPC"`; pck nằm ngay trước đó.
    static func embeddedPack(in exeURL: URL) -> (offset: Int, size: Int)? {
        guard let handle = try? FileHandle(forReadingFrom: exeURL),
              let fileSize = try? Int(handle.seekToEnd()), fileSize > 32 else { return nil }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: UInt64(fileSize - 12))) != nil,
              let trailer = try? handle.read(upToCount: 12), trailer.count == 12,
              trailer.suffix(4) == Data("GDPC".utf8) else { return nil }
        let size = trailer.prefix(8).enumerated().reduce(0) { $0 | Int($1.element) << (8 * $1.offset) }
        let offset = fileSize - 12 - size
        guard size > 0, offset >= 0, version(of: exeURL, offset: offset) != nil else { return nil }
        return (offset, size)
    }

    /// Runtime web phù hợp: pack 4.3+ (pack v3) cần template 4.5.
    static func runtime(for version: Version?) -> EngineRuntime {
        guard let version, version.major >= 4 else { return version == nil ? .godot4 : .godot3 }
        return version.minor >= 3 ? .godot45 : .godot4
    }
}
