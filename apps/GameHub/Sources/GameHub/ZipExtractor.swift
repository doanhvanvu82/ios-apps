import Foundation
import ZIPFoundation

/// Giải nén file zip bằng ZIPFoundation.
enum ZipExtractor {
    static func unzip(_ zipURL: URL, to destination: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        let archive = try Archive(url: zipURL, accessMode: .read)
        for entry in archive {
            _ = try archive.extract(entry, to: destination)
        }
    }

    /// Nếu zip có đúng 1 thư mục gốc thì "nâng" nội dung lên — tùy chọn.
    static func hasSingleRootFolder(_ zipURL: URL) -> Bool {
        guard let archive = try? Archive(url: zipURL, accessMode: .read) else { return false }
        var roots = Set<String>()
        for entry in archive {
            let first = entry.path.split(separator: "/").first.map(String.init) ?? ""
            if !first.isEmpty { roots.insert(first) }
        }
        return roots.count == 1
    }
}
