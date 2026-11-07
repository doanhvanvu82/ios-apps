import Foundation
import UIKit

/// Nhập file từ bên ngoài vào: share sheet "Copy to MyDrive", mở file bằng
/// "Open in MyDrive", hoặc kéo thả vào Documents/MyDrive/Inbox qua USB
/// File Sharing (app quét Inbox khi active rồi di chuyển vào mirror).
enum InboxImporter {
    /// File nhận từ app khác: copy ngay vào Inbox (an toàn — file tạm của app
    /// kia bị xoá sau khi hàm trả về).
    static func handleIncomingURL(_ url: URL) {
        let store = FileSystemStore.shared
        let inbox = store.inboxURL
        try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let dest = inbox.appendingPathComponent(url.lastPathComponent)
        do {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            // Copy (không move) để không phá file gốc của app gửi.
            try FileManager.default.copyItem(at: url, to: dest)
            FileSystemStore.shared.notifyChanged()
            AppLog.log("inbox", "✅ Nhận từ app khác: \(dest.lastPathComponent)")
            SyncEngine.triggerSyncPublic()
        } catch {
            AppLog.log("inbox", "❌ Không nhận được \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    /// Quét Inbox (gọi khi app active): file trong Inbox → nhập vào gốc mirror,
    /// đăng ký index + journal, rồi sync.
    static func processInbox() {
        let store = FileSystemStore.shared
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: store.inboxURL, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey]) else { return }
        guard !items.isEmpty else { return }

        AppLog.log("inbox", "📥 Inbox có \(items.count) mục — nhập…")
        defer { FileSystemStore.shared.notifyChanged() }
        for item in items {
            let name = item.lastPathComponent
            guard name != ".DS_Store" else { continue }
            let isDir = ((try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory) ?? false
            let destPath = [name]
            do {
                if isDir {
                    // Thư mục: copy đệ quy.
                    try FileManager.default.copyItem(at: item, to: store.url(for: destPath))
                } else {
                    let dest = store.url(for: destPath)
                    if fm.fileExists(atPath: dest.path) {
                        // Trùng tên: đổi thành "tên (2).ext".
                        let alt = uniquedName(for: name, in: store.rootURL)
                        let dest2 = store.rootURL.appendingPathComponent(alt)
                        try FileManager.default.copyItem(at: item, to: dest2)
                        register(dest2, relative: [alt])
                        try? fm.removeItem(at: item)
                        continue
                    }
                    try FileManager.default.copyItem(at: item, to: dest)
                }
                register(store.url(for: destPath), relative: destPath)
                try? fm.removeItem(at: item)   // nhập xong dọn Inbox
                AppLog.log("inbox", "✅ Đã nhập: \(name)")
            } catch {
                AppLog.log("inbox", "❌ Không nhập được \(name): \(error.localizedDescription)")
            }
        }
        SyncEngine.triggerSyncPublic()
    }

    private static func register(_ url: URL, relative: [String]) {
        let size = ((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize).map(Int64.init) ?? 0
        let p = relative.joined(separator: "/")
        let isDir = ((try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory) ?? false
        IndexStore.shared.upsert(path: p, node: .init(
            name: relative.last ?? url.lastPathComponent, isDirectory: isDir, size: size,
            modified: Date(), parts: nil, rev: 1, driveFolderId: nil
        ))
        Journal.shared.enqueue(.uploadFile(path: p))
    }

    private static func uniquedName(for name: String, in dir: URL) -> String {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        for i in 2...999 {
            let candidate = ext.isEmpty ? "\(base) (\(i))" : "\(base) (\(i)).\(ext)"
            if !FileManager.default.fileExists(atPath: dir.appendingPathComponent(candidate).path) {
                return candidate
            }
        }
        return UUID().uuidString + "." + ext
    }
}
