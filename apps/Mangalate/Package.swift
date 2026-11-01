// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Mangalate",
    platforms: [
        .iOS(.v17),
    ],
    products: [
        // App chứa: hướng dẫn bật extension.
        .library(
            name: "Mangalate",
            targets: ["Mangalate"]
        ),
        // Safari Web Extension: Vision OCR + gọi Gemini. Phần chạy trong trang là JS ở WebExtension/.
        .library(
            name: "MangalateExtension",
            targets: ["MangalateExtension"]
        ),
    ],
    targets: [
        .target(
            name: "Mangalate",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "MangalateExtension",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("Vision"),
                // xtool dựng appex từ stub chỉ trỏ entry point vào _NSExtensionMain, không tham chiếu code nào
                // của target này; iOS tìm NSExtensionPrincipalClass bằng tên lúc chạy nên linker bỏ sạch code Swift
                // (appex chỉ còn 3 symbol → "Launch failed"). Ép giữ lớp principal, kéo theo mọi code nó dùng.
                .unsafeFlags(["-Xlinker", "-u", "-Xlinker", "_OBJC_CLASS_$_SafariWebExtensionHandler"]),
            ]
        ),
    ]
)
