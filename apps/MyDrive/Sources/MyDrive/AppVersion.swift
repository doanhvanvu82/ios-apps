import Foundation

/// Version hiển thị = (1 + VERSION/100).(VERSION%100) — bump_version.sh ghi vào
/// Info.plist; app chỉ đọc ra.
enum AppVersion {
    static var display: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}
