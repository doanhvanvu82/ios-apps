import Foundation

/// Mirror cục bộ: Documents/MyDrive/<cây thư mục>. UI đọc từ đây (tức thì),
/// SyncEngine đối chiếu với index.json để biết file nào đã sync.
final class FileSystemStore: ObservableObject {
    static let shared = FileSystemStore()

    /// Tăng mỗi lần nội dung mirror thay đổi (UI Files đăng ký để reload ngay —
    /// bản thân liệt kê thư mục không có gì để SwiftUI quan sát được).
    @Published private(set) var changeToken = 0

    let rootURL: URL
    /// Hộp thư nhập file (kéo từ máy tính qua USB File Sharing).
    let inboxURL: URL
    /// Temp các part đang tải về (nối xong thì xoá).
    let tmpURL: URL

    private let fm = FileManager.default

    init() {
        _ = AppPaths.migrated
        AppPaths.ensureDirs()
        rootURL = AppPaths.mirror
        inboxURL = AppPaths.inbox
        tmpURL = AppPaths.tmp
    }

    /// Báo cho UI biết mirror vừa thay đổi (gọi trên main queue).
    func notifyChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.changeToken &+= 1
        }
    }

    /// Đường dẫn có tồn tại (file hoặc thư mục).
    func exists(at path: [String]) -> Bool {
        fm.fileExists(atPath: url(for: path).path)
    }

    // MARK: - Đường dẫn

    /// URL local của 1 path tương đối (["Ảnh", "a.jpg"]).
    func url(for path: [String]) -> URL {
        var url = rootURL
        for comp in path where !comp.isEmpty {
            url = url.appendingPathComponent(comp)
        }
        return url
    }

    /// Path tương đối từ URL (trả nil nếu URL nằm ngoài root — an toàn).
    func relativePath(of url: URL) -> [String]? {
        let rootPath = rootURL.standardizedFileURL.path
        let p = url.standardizedFileURL.path
        guard p.hasPrefix(rootPath + "/") else { return nil }
        let rest = String(p.dropFirst(rootPath.count + 1))
        return rest.split(separator: "/").map(String.init)
    }

    // MARK: - Thao tác file (UI gọi trực tiếp — tức thì)

    /// Tạo thư mục (đệ quy theo path).
    func makeDirectory(_ path: [String]) throws {
        try fm.createDirectory(at: url(for: path), withIntermediateDirectories: true)
    }

    /// Ghi data vào file (ghi đè).
    func write(data: Data, to path: [String]) throws {
        let url = url(for: path)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        notifyChanged()
    }

    /// Ghi file từ URL (copy vào mirror).
    @discardableResult
    func copyFile(from srcURL: URL, to path: [String]) throws -> URL {
        let dest = url(for: path)
        try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
        try fm.copyItem(at: srcURL, to: dest)
        notifyChanged()
        return dest
    }

    /// Copy cả thư mục (đệ quy) vào mirror.
    @discardableResult
    func copyDirectory(from srcURL: URL, to path: [String]) throws -> URL {
        let dest = url(for: path)
        if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
        try fm.copyItem(at: srcURL, to: dest)
        notifyChanged()
        return dest
    }

    /// Di chuyển/rename (local).
    func move(from srcPath: [String], to destPath: [String]) throws {
        let src = url(for: srcPath)
        let dest = url(for: destPath)
        try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
        try fm.moveItem(at: src, to: dest)
        notifyChanged()
    }

    /// Xóa: chuyển vào "Đã xóa gần đây" (TrashStore) rồi mới khỏi mirror —
    /// còn trong thùng rác 30 ngày, khôi phục được (giống app Files).
    func remove(at path: [String]) throws {
        let target = url(for: path)
        guard target.standardizedFileURL.path.hasPrefix(rootURL.standardizedFileURL.path + "/") else { return }
        guard fm.fileExists(atPath: target.path) else { return }
        let p = path.joined(separator: "/")
        TrashStore.shared.stash(path: p)
        IndexStore.shared.remove(path: p)
        IndexStore.shared.removeTree(prefix: p)
        notifyChanged()
    }

    /// Kích thước file local (nil nếu chưa có).
    func fileSize(at path: [String]) -> Int64? {
        let attrs = try? fm.attributesOfItem(atPath: url(for: path).path)
        return (attrs?[.size] as? NSNumber)?.int64Value
    }

    /// Nội dung file (Data) — file nhỏ (preview/ghi chú).
    func readData(at path: [String]) throws -> Data {
        try Data(contentsOf: url(for: path))
    }

    /// Liệt kê entry trong 1 thư mục mirror.
    struct Entry: Identifiable, Hashable {
        var name: String
        var isDirectory: Bool
        var size: Int64
        var modified: Date
        var id: String { name }
    }

    /// Liệt kê entry trong 1 thư mục mirror (chỉ đọc khi caller quan sát changeToken).
    func listDirectory(_ path: [String]) throws -> [Entry] {
        _ = changeToken
        let dirURL = url(for: path)
        guard fm.fileExists(atPath: dirURL.path) else { return [] }
        let items = try fm.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
        return items.compactMap { item in
            guard item.lastPathComponent != "MyDrive.meta" else { return nil }
            let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
            return Entry(
                name: item.lastPathComponent,
                isDirectory: values?.isDirectory ?? false,
                size: Int64(values?.fileSize ?? 0),
                modified: values?.contentModificationDate ?? .distantPast
            )
        }
        .sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    /// Quét đệ quy toàn bộ mirror (path tương đối của file + folder).
    func scanAll() -> (files: [String], dirs: [String]) {
        var files: [String] = []
        var dirs: [String] = []
        let base = rootURL.path
        func walk(_ dir: URL, prefix: String) {
            guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
            for item in items {
                let rel = prefix.isEmpty ? item.lastPathComponent : prefix + "/" + item.lastPathComponent
                let isDir = ((try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory) ?? false
                if isDir {
                    dirs.append(rel)
                    walk(item, prefix: rel)
                } else {
                    files.append(rel)
                }
            }
        }
        walk(rootURL, prefix: "")
        return (files, dirs)
    }
}
