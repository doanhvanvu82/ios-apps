// swift-tools-version:5.9
import PackageDescription

// Chạy EngineDetector của app trên máy Linux — tools/organize_games.py dùng để
// phân loại game. Mã nhận diện là symlink tới Sources/GameHub nên không bao giờ
// lệch với app.
let package = Package(
    name: "detector-cli",
    dependencies: [.package(path: "../../Vendor/ZIPFoundation")],
    targets: [
        .executableTarget(
            name: "detector-cli",
            dependencies: [.product(name: "ZIPFoundation", package: "ZIPFoundation")]
        )
    ]
)
