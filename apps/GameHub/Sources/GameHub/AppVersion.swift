import Foundation

/// Đọc version app từ Info.plist.
///
/// `CFBundleShortVersionString` được `toolkit/bump_version.sh` ghi lúc build
/// (dạng "1.5" = tính năng 1, lần build thứ 5). Hiển thị trên màn chính
/// và trong AppLog để biết bản đang cài có phải mới nhất không.
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
