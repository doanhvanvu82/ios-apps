import Foundation
import Combine

/// Log tập trung của app — hiển thị được ngay trên iPhone (màn Debug) để
/// gỡ lỗi khi thiết bị không cắm máy tính.
///
/// Ghi vào `Documents/GameHub/logs/app.log` + giữ vòng đệm trong RAM.
///
/// ⚠️ QUY TẮC LUỒNG (rất quan trọng — đã gây watchdog crash thật):
/// `@Published var lines` **CHỈ được mutate trên main thread**.
///
/// Crash 07:36 (v1.7): background queue mutate `lines` → Combine publish
/// từ background → SwiftUI `AttributeInvalidatingSubscriber` chạy trên
/// background nhưng cần main thread → chờ nhau → watchdog SIGKILL
/// (0x8BADF00D "scene-update watchdog transgression").
///
/// Giải pháp: background queue chỉ làm việc đĩa (append file); phần RAM +
/// publish luôn chạy trên main thread.
final class AppLog: ObservableObject {
    static let shared = AppLog()

    /// Số dòng tối đa giữ trong RAM.
    private let maxLines = 500

    /// Log hiện tại (publish để SwiftUI đọc trực tiếp).
    /// CHỈ mutate trên main thread (xem quy tắc luồng ở đầu class).
    @Published private(set) var lines: [String] = []
    /// Tổng số dòng lỗi từ lúc mở app (màn chơi lấy hiệu số để đếm lỗi của game).
    @Published private(set) var errorCount = 0

    /// Log riêng của game đang chơi (cùng quy tắc main thread như `lines`).
    @Published private(set) var gameLines: [String] = []
    /// Game đang chơi — mọi dòng log được ghi kèm vào `logs/games/<tên>.log`.
    private(set) var activeGame: String?
    /// Số dòng giữ lại trong tệp log của mỗi game (cắt bớt mỗi lần mở game).
    private let maxGameFileLines = 3000

    private let fileURL: URL
    private let gamesDir: URL
    private let ioQueue = DispatchQueue(label: "vn.vudv.gamehub.applog")

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("GameHub/logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("app.log")
        gamesDir = dir.appendingPathComponent("games", isDirectory: true)
        try? FileManager.default.createDirectory(at: gamesDir, withIntermediateDirectories: true)
        loadFromDisk()
        // LƯU Ý: KHÔNG gọi Self.info() ở đây — `shared` đang khởi tạo dở,
        // gọi lại sẽ deadlock dispatch_once. Ghi trực tiếp dòng khởi động:
        appendDirect("ℹ️ AppLog khởi động — \(AppVersion.display)")
    }

    /// Ghi thẳng vào hàng đợi mà không đi qua `shared` (an toàn trong init).
    private func appendDirect(_ line: String) {
        ioQueue.async { [weak self] in
            guard let self else { return }
            self.writeToDisk(line)
        }
        DispatchQueue.main.async { [weak self] in
            self?.appendInMemory(line)
        }
    }

    static func info(_ msg: String) { shared.append("ℹ️", msg) }
    static func ok(_ msg: String) { shared.append("✅", msg) }
    static func warn(_ msg: String) { shared.append("⚠️", msg) }
    static func error(_ msg: String) { shared.append("❌", msg) }

    private func append(_ icon: String, _ msg: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let line = "\(formatter.string(from: Date())) \(icon) \(msg)"

        // 1. Ghi đĩa trên background — không đụng state nào của SwiftUI.
        ioQueue.async { [weak self] in
            self?.writeToDisk(line)
        }
        // 2. Cập nhật RAM + publish trên main — Combine/SwiftUI an toàn tuyệt đối.
        //    Game đang chơi đọc trên main (activeGame chỉ đổi trên main).
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.appendInMemory(line)
            if let game = self.activeGame {
                self.appendGameLine(line)
                let url = self.gameLogURL(game)
                self.ioQueue.async { Self.append(line, to: url) }
            }
        }
    }

    // MARK: - Log theo game

    /// Bắt đầu phiên chơi: từ giờ log được ghi kèm vào tệp riêng của game.
    /// Chỉ gọi trên main thread.
    func beginGame(_ name: String) {
        activeGame = name
        let url = gameLogURL(name)
        let header = "\(Self.timestamp()) ▶︎ Mở game — \(AppVersion.display)"
        let keep = maxGameFileLines
        gameLines = Array((Self.readLines(url) + [header]).suffix(maxLines))
        ioQueue.async {
            // Cắt tệp về `keep` dòng cuối để không phình mãi theo số lần chơi.
            let lines = Self.readLines(url).suffix(keep - 1) + [header]
            try? (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// Kết thúc phiên chơi. Chỉ gọi trên main thread.
    func endGame() {
        activeGame = nil
    }

    /// Log đã lưu của một game (xem lại sau khi thoát).
    func savedLines(for game: String) -> [String] {
        Array(Self.readLines(gameLogURL(game)).suffix(maxLines))
    }

    func clearGameLog(_ game: String) {
        let url = gameLogURL(game)
        ioQueue.async { try? FileManager.default.removeItem(at: url) }
        if activeGame == game {
            gameLines = ["\(Self.timestamp()) 🗑 Đã xoá log của game — \(AppVersion.display)"]
        }
    }

    private func appendGameLine(_ line: String) {
        gameLines.append(line)
        if gameLines.count > maxLines {
            gameLines.removeFirst(gameLines.count - maxLines)
        }
    }

    private func gameLogURL(_ game: String) -> URL {
        let safe = game.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
        return gamesDir.appendingPathComponent(safe + ".log")
    }

    private static func readLines(_ url: URL) -> [String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").map(String.init)
    }

    private static func append(_ line: String, to url: URL) {
        if let handle = try? FileHandle(forWritingTo: url) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data((line + "\n").utf8))
            try? handle.close()
        } else {
            try? (line + "\n").write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private static func timestamp() -> String {
        Date().formatted(date: .omitted, time: .standard)
    }

    /// Append vào mảng RAM. **Chỉ gọi từ main thread.**
    private func appendInMemory(_ line: String) {
        lines.append(line)
        if line.contains(" ❌ ") { errorCount += 1 }
        if lines.count > maxLines {
            lines.removeFirst(lines.count - maxLines)
        }
    }

    /// Append file app.log. Chỉ chạy trên ioQueue (serial → không rác lẫn).
    private func writeToDisk(_ line: String) {
        Self.append(line, to: fileURL)
    }

    private func loadFromDisk() {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
        let all = text.split(separator: "\n").map(String.init)
        lines = Array(all.suffix(maxLines))
    }

    /// Xoá log (nút trong màn Debug).
    func clear() {
        ioQueue.async { [weak self] in
            try? FileManager.default.removeItem(at: self?.fileURL ?? URL(fileURLWithPath: "/dev/null"))
        }
        // Kèm version vào dòng xoá — sau khi xoá vẫn biết đang chạy bản nào
        // (dòng khởi động có version đã bị xoá mất theo).
        DispatchQueue.main.async { [weak self] in
            self?.lines = ["\(Self.timestamp()) 🗑 Đã xoá log — \(AppVersion.display)"]
        }
    }
}
