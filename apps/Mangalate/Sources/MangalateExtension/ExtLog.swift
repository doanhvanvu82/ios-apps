import Foundation
import os

/// Nhật ký chẩn đoán của app extension, ghi vào unified log **trên máy** (không gửi ra mạng).
///
/// Container của extension tách khỏi container app (App Group không dùng được với Apple ID miễn phí của SideStore),
/// nên log native không ghi chung file Documents/Logs của app được. Xem bằng:
///   idevicesyslog -m MangalateExtension       (cắm USB, lọc theo tên process)
/// hoặc Console.app → chọn iPhone → lọc subsystem `vn.vudv.mangalate`.
enum ExtLog {
    private static let logger = Logger(subsystem: "vn.vudv.mangalate", category: "ext")
    private static let start = Date()

    static func log(_ text: String) {
        let elapsed = Date().timeIntervalSince(start)
        logger.notice("\(elapsed, format: .fixed(precision: 2), privacy: .public) \(text, privacy: .public)")
    }
}
