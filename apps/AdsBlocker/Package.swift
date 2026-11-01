// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AdsBlocker",
    platforms: [
        .iOS(.v17),
    ],
    products: [
        // App chứa: hướng dẫn bật extension.
        .library(
            name: "AdsBlocker",
            targets: ["AdsBlocker"]
        ),
        // Safari Web Extension: native handler (Keychain + gọi Gemini).
        // Phần chạy trong trang là JS ở WebExtension/, xtool copy vào gốc appex.
        .library(
            name: "AdsBlockerExtension",
            targets: ["AdsBlockerExtension"]
        ),
    ],
    targets: [
        .target(
            name: "AdsBlocker",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "AdsBlockerExtension",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                // xtool dựng appex từ stub chỉ trỏ entry point vào _NSExtensionMain, không tham chiếu code nào
                // của target này; iOS tìm NSExtensionPrincipalClass bằng tên lúc chạy nên linker bỏ sạch code Swift
                // (appex chỉ còn 3 symbol → "Launch failed"). Ép giữ lớp principal, kéo theo mọi code nó dùng.
                .unsafeFlags(["-Xlinker", "-u", "-Xlinker", "_OBJC_CLASS_$_SafariWebExtensionHandler"]),
            ]
        ),
    ]
)
