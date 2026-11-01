import Foundation

/// Bản build Windows của TyranoBuilder thường đặt `;configSave=file` trong
/// `data/system/Config.tjs` (dòng `;key=value` là setting đang bật). Chế độ đó
/// ghi file .sav qua `require('electron').remote` + `fs` — không có trong
/// WKWebView, engine bắt lỗi rồi trả chuỗi "null" → `sf = null` → crash.
/// Phục vụ bản Config.tjs đã đổi sang `webstorage` (localStorage, bền vững vì
/// port server cố định theo game).
enum TyranoPatch {
    static let configPath = "data/system/Config.tjs"

    static func applyWebStorageSave(to root: GameResourceRoot) {
        guard let source = root.source(for: configPath),
              let data = source.read(offset: 0, count: source.fileSize),
              let patched = webStorageConfig(data) else { return }
        root.virtualFiles[configPath] = patched
        AppLog.info("Tyrano: configSave=file → webstorage")
    }

    /// Trả nil nếu không cần sửa. Xử lý theo byte (Latin-1) để giữ nguyên
    /// encoding gốc (UTF-8 / Shift_JIS).
    static func webStorageConfig(_ data: Data) -> Data? {
        guard let text = String(data: data, encoding: .isoLatin1) else { return nil }
        let patched = text.replacingOccurrences(
            of: #"(?m)^(\s*;\s*configSave\s*=\s*)file(\s*)$"#,
            with: "$1webstorage$2",
            options: .regularExpression)
        return patched == text ? nil : patched.data(using: .isoLatin1)
    }
}
