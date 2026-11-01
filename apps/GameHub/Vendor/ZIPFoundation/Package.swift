// swift-tools-version:5.9
import PackageDescription

// Bản vendor của ZIPFoundation (MIT — xem LICENSE).
//
// Thay đổi so với upstream: manifest gốc chọn nhánh `CZLib` (system library
// `zlib`) khi `Compression` không import được — điều luôn xảy ra vì manifest
// được evaluate trên máy Linux, kể cả khi đang cross-compile cho iOS.
//
// Hậu quả: SwiftPM thêm `-L/usr/lib/x86_64-linux-gnu -lz` vào link line của
// app iOS, và ld64.lld không thể link file ELF của Linux vào binary Mach-O
// ("unhandled file type").
//
// Trên iOS, ZIPFoundation vốn đã dùng framework `Compression` của Apple
// (xem `Data+Compression.swift`: nhánh `#if os(iOS)`), nên hoàn toàn không cần
// zlib. CZLib chỉ được nối khi build cho Linux (`tools/detector-cli` chạy trên
// máy) — điều kiện theo nền tảng đích nên app iOS không bị thêm `-lz`.
let targets: [Target] = [
    .systemLibrary(name: "CZLib", path: "Sources/CZLib"),
    .target(
        name: "ZIPFoundation",
        dependencies: [.target(name: "CZLib", condition: .when(platforms: [.linux]))],
        resources: [
            .copy("Resources/PrivacyInfo.xcprivacy")
        ]
    )
]

let package = Package(
    name: "ZIPFoundation",
    platforms: [
        .macOS(.v10_13), .iOS(.v12), .tvOS(.v12), .watchOS(.v4), .visionOS(.v1)
    ],
    products: [
        .library(name: "ZIPFoundation", targets: ["ZIPFoundation"])
    ],
    targets: targets,
    swiftLanguageVersions: [.v4, .v4_2, .v5]
)
