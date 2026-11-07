// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MyDrive",
    platforms: [
        .iOS(.v17),
    ],
    products: [
        // An xtool project should contain exactly one library product,
        // representing the main app.
        .library(
            name: "MyDrive",
            targets: ["MyDrive"]
        ),
    ],
    targets: [
        .target(
            name: "MyDrive",
            swiftSettings: [
                // Dùng mode 5 để tránh strict-concurrency errors với các callback
                // UIKit/URLSession.
                .swiftLanguageMode(.v5)
            ]
        ),
    ]
)
