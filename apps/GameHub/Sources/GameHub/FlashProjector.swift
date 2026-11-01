import Foundation

/// Flash projector (.exe) = trình phát + SWF chính + 8 byte cuối:
/// `0xFA123456` (LE) rồi kích thước SWF (UInt32 LE).
/// SWF chính này là entry thật của game (nó tự nạp `data/*.swf` theo đường dẫn tương đối).
enum FlashProjector {
    static func embeddedSWF(in exeURL: URL) -> (offset: Int, size: Int)? {
        guard let handle = try? FileHandle(forReadingFrom: exeURL) else { return nil }
        defer { try? handle.close() }
        guard let fileSize = try? handle.seekToEnd(), fileSize > 8,
              (try? handle.seek(toOffset: fileSize - 8)) != nil,
              let tail = try? handle.read(upToCount: 8), tail.count == 8 else { return nil }
        let bytes = [UInt8](tail)
        guard bytes[0] == 0x56, bytes[1] == 0x34, bytes[2] == 0x12, bytes[3] == 0xFA else { return nil }
        let size = Int(bytes[4]) | Int(bytes[5]) << 8 | Int(bytes[6]) << 16 | Int(bytes[7]) << 24
        guard size > 0, UInt64(size) <= fileSize - 8 else { return nil }
        return (Int(fileSize) - 8 - size, size)
    }

    /// Projector .exe cạnh nhau trong thư mục game (nếu có).
    static func entry(in dir: URL, items: [String]) -> (exe: String, offset: Int, size: Int)? {
        for name in items where name.lowercased().hasSuffix(".exe") {
            if let swf = embeddedSWF(in: dir.appendingPathComponent(name)) {
                return (name, swf.offset, swf.size)
            }
        }
        return nil
    }
}
