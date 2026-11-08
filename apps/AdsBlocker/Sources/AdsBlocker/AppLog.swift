import Foundation
import UIKit

/// Nhật ký chẩn đoán lưu trên máy: Documents/Logs/<ngày>.log (giữ 7 ngày).
/// Xem trong app Tệp › Trên iPhone › AdsBlocker, hoặc cắm USB rồi chạy `toolkit/pull_app_logs.sh vn.vudv.adsblocker`.
/// Không gửi gì ra mạng. Ghi thẳng từng dòng xuống file để app bị iOS giết vẫn còn log tới sát lúc đó.
enum AppLog {
    static let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Logs")
    private static let queue = DispatchQueue(label: "AppLog", qos: .utility)
    private static let launchUptime = ProcessInfo.processInfo.systemUptime
    private static let keepDays = 7
    private static let maxFileBytes: UInt64 = 20 * 1024 * 1024
    private static var handle: FileHandle?
    private static var day = ""
    private static var full = false
    private static let timeFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()
    private static let dayFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Giây kể từ lúc mở app (đồng hồ đơn điệu).
    static var uptime: TimeInterval {
        ProcessInfo.processInfo.systemUptime - launchUptime
    }

    static func log(_ category: String, _ message: String) {
        let now = Date()
        let elapsed = uptime
        queue.async {
            write(String(format: "%@ %9.3f [%@] %@\n", timeFormat.string(from: now), elapsed, category, message), at: now)
        }
    }

    static func start() {
        queue.sync {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            removeOldFiles()
        }
        let info = Bundle.main.infoDictionary ?? [:]
        var system = utsname()
        uname(&system)
        let model = withUnsafeBytes(of: &system.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        log("app", "===== MỞ APP v\(info["CFBundleShortVersionString"] ?? "?") (\(info["CFBundleVersion"] ?? "?")) · \(model) · iOS \(UIDevice.current.systemVersion)")
    }

    // MARK: Ghi file (chỉ trên `queue`)

    private static func write(_ line: String, at date: Date) {
        let today = dayFormat.string(from: date)
        if today != day {
            try? handle?.close()
            handle = nil
            day = today
            full = false
            let url = directory.appendingPathComponent("\(today).log")
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            handle = try? FileHandle(forWritingTo: url)
        }
        guard let handle, !full else { return }
        guard let end = try? handle.seekToEnd(), end < maxFileBytes else {
            full = true
            try? handle.write(contentsOf: Data("… file log hôm nay đã đủ \(maxFileBytes / 1_048_576) MB, ngừng ghi tới ngày mai\n".utf8))
            return
        }
        try? handle.write(contentsOf: Data(line.utf8))
    }

    private static func removeOldFiles() {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let logs = files.filter { $0.pathExtension == "log" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
        logs.dropFirst(keepDays).forEach { try? FileManager.default.removeItem(at: $0) }
    }
}
