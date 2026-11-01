// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "GameHub",
    platforms: [
        .iOS(.v17),
    ],
    products: [
        // An xtool project should contain exactly one library product,
        // representing the main app.
        .library(
            name: "GameHub",
            targets: ["GameHub"]
        ),
    ],
    dependencies: [
        // Giải nén zip cho tính năng import game.
        // Bản vendor trong ./Vendor (MIT) vì bản upstream khai báo system library
        // "zlib" khi manifest được evaluate trên Linux, khiến link line của app
        // iOS trỏ tới libz.so của Linux và link thất bại.
        .package(path: "Vendor/ZIPFoundation"),
    ],
    targets: [
        .target(
            name: "GameHub",
            dependencies: [
                "ZIPFoundation",
            ],
            resources: [
                // Runtime engine đi kèm app: Godot (web), KiriKiri2 (WASM), Ruffle.
                // Nhờ đó game gốc (Windows) chạy được ngay, không cần build lại.
                .copy("Resources"),
            ],
            swiftSettings: [
                // Dùng mode 5 để tránh strict-concurrency errors với Network.framework callbacks
                .swiftLanguageMode(.v5)
            ]
        ),
    ]
)
