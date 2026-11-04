import Foundation

/// Đọc version app từ Info.plist.
///
/// `CFBundleShortVersionString` được `toolkit/bump_version.sh` ghi lúc build
/// (dạng major.minor, minor 2 chữ số 00–99: 1.99 → 2.00). Hiển thị trên màn
/// chính và trong AppLog để biết bản đang cài có phải mới nhất không.
enum AppVersion {
    static let short: String =
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
        ?? "?"
    static let build: String =
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
        ?? "?"

    /// "1.5 (build 5)" — dùng hiển thị.
    static let display: String = "v\(short) (build \(build))"
}
