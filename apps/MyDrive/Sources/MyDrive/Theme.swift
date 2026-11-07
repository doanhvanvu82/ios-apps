import SwiftUI
import Foundation

/// Màu nhãn app (xanh Google Drive).
enum Theme {
    static let accent = Color(red: 0.10, green: 0.45, blue: 0.91)
}

/// Format số byte kiểu app Drive: đơn vị nhị phân (1 GB = 2³⁰) để khớp cách
/// Google đếm dung lượng (15 GB free = 16106127360 byte, không phải 15 × 10⁹).
/// ByteCountFormatter mặc định decimal sẽ hiện 15 GiB thành "16,11 GB" — sai.
enum ByteFmt {
    private static let formatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .binary
        return f
    }()

    static func string(_ bytes: Int64) -> String {
        formatter.string(fromByteCount: bytes)
    }
}
