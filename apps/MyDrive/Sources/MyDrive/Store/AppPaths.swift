import Foundation

/// Đường dẫn dữ liệu app.
///
/// Kho mirror + metadata + thùng rác nằm trong **Application Support** — vùng
/// sandbox mà app Files KHÔNG liệt kê (không lọt vào "On My iPhone" hay
/// "Gần đây"; yêu cầu tách riêng của người dùng). Chỉ `Documents/Inbox`
/// (kéo thả USB File Sharing) và `Documents/Logs` (lấy log qua ifuse) còn lộ.
enum AppPaths {
    static let fm = FileManager.default
    static let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
    static let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]

    static let mirror = support.appendingPathComponent("MyDrive", isDirectory: true)
    static let meta = support.appendingPathComponent("MyDrive.meta", isDirectory: true)
    static let trash = support.appendingPathComponent("MyDrive.trash", isDirectory: true)
    static let tmp = support.appendingPathComponent("MyDrive.tmp", isDirectory: true)
    static let inbox = docs.appendingPathComponent("Inbox", isDirectory: true)

    /// Chuyển dữ liệu từ layout cũ (Documents/MyDrive + Documents/.myd-*) sang
    /// layout mới. Chạy đúng 1 lần (static let = atomic once), idempotent.
    static let migrated: Bool = {
        try? fm.createDirectory(at: support, withIntermediateDirectories: true)
        moveLegacy(docs.appendingPathComponent("MyDrive"), to: mirror)
        moveLegacy(docs.appendingPathComponent(".myd-meta"), to: meta)
        moveLegacy(docs.appendingPathComponent(".myd-trash"), to: trash)
        try? fm.removeItem(at: docs.appendingPathComponent(".myd-tmp"))   // tạm — bỏ
        // Inbox cũ nằm trong mirror (Documents/MyDrive/Inbox) → chuyển ra Documents/Inbox.
        let legacyInbox = mirror.appendingPathComponent("Inbox", isDirectory: true)
        if fm.fileExists(atPath: legacyInbox.path) {
            try? fm.createDirectory(at: inbox, withIntermediateDirectories: true)
            if let items = try? fm.contentsOfDirectory(at: legacyInbox, includingPropertiesForKeys: nil) {
                for item in items {
                    let dest = inbox.appendingPathComponent(item.lastPathComponent)
                    if fm.fileExists(atPath: dest.path) { try? fm.removeItem(at: dest) }
                    try? fm.moveItem(at: item, to: dest)
                }
            }
            try? fm.removeItem(at: legacyInbox)
        }
        return true
    }()

    private static func moveLegacy(_ src: URL, to dst: URL) {
        guard fm.fileExists(atPath: src.path) else { return }
        if fm.fileExists(atPath: dst.path) {
            // Đích đã có — gộp: chuyển từng con vào đích (đè trùng tên).
            if let items = try? fm.contentsOfDirectory(at: src, includingPropertiesForKeys: nil) {
                for item in items {
                    let dest = dst.appendingPathComponent(item.lastPathComponent)
                    if fm.fileExists(atPath: dest.path) { try? fm.removeItem(at: dest) }
                    try? fm.moveItem(at: item, to: dest)
                }
            }
            try? fm.removeItem(at: src)
        } else {
            try? fm.moveItem(at: src, to: dst)
        }
    }

    static func ensureDirs() {
        for url in [mirror, meta, trash, tmp, inbox] {
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}
