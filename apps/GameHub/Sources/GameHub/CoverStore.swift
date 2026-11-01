import SwiftUI
import ImageIO
import UniformTypeIdentifiers

/// Ảnh bìa game. Thứ tự ưu tiên:
/// 1. Ảnh chụp màn hình lần chơi gần nhất (`Documents/GameHub/Covers/`).
/// 2. `cover.jpg` / `cover.png` người dùng tự đặt trong thư mục game.
/// 3. Ảnh bìa sinh tự động (`GeneratedCover`) — view tự vẽ khi 1 và 2 không có.
@MainActor
final class CoverStore: ObservableObject {
    static let shared = CoverStore()

    /// Tăng khi ảnh bìa của 1 game đổi → `GameCoverView` nạp lại.
    @Published private(set) var revisions: [String: Int] = [:]

    private let cache = NSCache<NSString, UIImage>()
    private static let customNames = ["cover.jpg", "cover.jpeg", "cover.png", "cover.webp"]

    static var coversDirectory: URL {
        GameLibrary.hubRoot.appendingPathComponent("Covers", isDirectory: true)
    }

    private init() {
        cache.countLimit = 120
    }

    func revision(for game: GameInfo) -> Int { revisions[game.id] ?? 0 }

    private func snapshotURL(for game: GameInfo) -> URL {
        let safe = game.folderName.replacingOccurrences(of: "/", with: "_")
        return Self.coversDirectory.appendingPathComponent(safe + ".jpg")
    }

    func hasSnapshot(for game: GameInfo) -> Bool {
        FileManager.default.fileExists(atPath: snapshotURL(for: game).path)
    }

    func image(for game: GameInfo, maxPixel: CGFloat) async -> UIImage? {
        let key = "\(game.id)#\(Int(maxPixel))#\(revision(for: game))" as NSString
        if let hit = cache.object(forKey: key) { return hit }

        let candidates = [snapshotURL(for: game)]
            + Self.customNames.map { GameLibrary.shared.gameDirectory(for: game).appendingPathComponent($0) }
        let image = await Task.detached(priority: .userInitiated) {
            candidates.lazy.compactMap { Self.downsample($0, maxPixel: maxPixel) }.first
        }.value
        if let image { cache.setObject(image, forKey: key) }
        return image
    }

    /// Lưu ảnh chụp lúc thoát game. Bỏ qua ảnh gần như toàn đen (game WebGL
    /// đôi khi chụp ra khung trống). Trả `true` nếu đã lưu.
    @discardableResult
    func saveSnapshot(_ image: UIImage, for game: GameInfo) -> Bool {
        guard !Self.isMostlyDark(image) else {
            AppLog.info("Ảnh chụp \(game.folderName) quá tối — giữ ảnh bìa cũ")
            return false
        }
        let scaled = Self.resized(image, maxSide: 1280)
        guard let data = scaled.jpegData(compressionQuality: 0.82) else { return false }
        do {
            try FileManager.default.createDirectory(at: Self.coversDirectory, withIntermediateDirectories: true)
            try data.write(to: snapshotURL(for: game), options: .atomic)
            bump(game.id)
            return true
        } catch {
            AppLog.warn("Không lưu được ảnh bìa: \(error.localizedDescription)")
            return false
        }
    }

    func removeSnapshot(for game: GameInfo) {
        try? FileManager.default.removeItem(at: snapshotURL(for: game))
        bump(game.id)
    }

    func removeAllSnapshots() {
        try? FileManager.default.removeItem(at: Self.coversDirectory)
        cache.removeAllObjects()
        revisions = revisions.mapValues { $0 + 1 }
    }

    private func bump(_ id: String) {
        revisions[id, default: 0] += 1
    }

    // MARK: - Xử lý ảnh

    /// Đọc + thu nhỏ bằng ImageIO (không giải mã ảnh gốc full size vào RAM).
    nonisolated private static func downsample(_ url: URL, maxPixel: CGFloat) -> UIImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }

    private static func resized(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height) * image.scale
        guard longest > maxSide else { return image }
        let factor = maxSide / longest
        let size = CGSize(width: image.size.width * image.scale * factor,
                          height: image.size.height * image.scale * factor)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    static func isMostlyDark(_ image: UIImage) -> Bool {
        (averageBrightness(image) ?? 0) < 0.06
    }

    /// Thu ảnh về 16×16 rồi lấy độ sáng trung bình (0…1).
    private static func averageBrightness(_ image: UIImage) -> Double? {
        guard let cg = image.cgImage else { return nil }
        let side = 16
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: side, height: side,
                                      bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            ctx.interpolationQuality = .low
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }
        var total = 0.0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            total += 0.299 * Double(pixels[i]) + 0.587 * Double(pixels[i + 1]) + 0.114 * Double(pixels[i + 2])
        }
        return total / Double(side * side) / 255
    }
}

// MARK: - View

/// Ảnh bìa: luôn vẽ ảnh sinh tự động trước, ảnh thật (nếu có) fade lên trên.
struct GameCoverView: View {
    let game: GameInfo
    var maxPixel: CGFloat = 600

    @ObservedObject private var store = CoverStore.shared
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            GeneratedCover(game: game)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            }
        }
        .clipped()
        .task(id: "\(game.id)#\(store.revision(for: game))") {
            let loaded = await store.image(for: game, maxPixel: maxPixel)
            withAnimation(.easeOut(duration: 0.25)) { image = loaded }
        }
    }
}

/// Ảnh bìa sinh từ tên game + màu engine (ổn định giữa các lần mở app).
struct GeneratedCover: View {
    let game: GameInfo

    var body: some View {
        let hue = Self.hue(for: game.folderName)
        let accent = game.engine.accent
        GeometryReader { geo in
            ZStack {
                LinearGradient(
                    colors: [Color(hue: hue, saturation: 0.55, brightness: 0.42),
                             accent.opacity(0.55),
                             Color(hue: hue, saturation: 0.65, brightness: 0.16)],
                    startPoint: .topLeading, endPoint: .bottomTrailing)

                Image(systemName: game.engine.symbol)
                    .font(.system(size: geo.size.height * 0.75, weight: .bold))
                    .foregroundStyle(.white.opacity(0.07))
                    .rotationEffect(.degrees(-14))
                    .offset(x: geo.size.width * 0.3, y: geo.size.height * 0.18)

                Text(Self.monogram(for: game.folderName))
                    .font(.system(size: geo.size.height * 0.42, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    /// Hash ổn định (djb2) — `hashValue` của Swift đổi mỗi lần chạy app.
    private static func hue(for name: String) -> Double {
        var h: UInt32 = 5381
        for s in name.unicodeScalars { h = (h &<< 5) &+ h &+ s.value }
        return Double(h % 360) / 360
    }

    /// Chữ cái đầu tiên của tên (bỏ qua ký tự như `[`, `(`, số phiên bản…).
    private static func monogram(for name: String) -> String {
        name.first(where: { $0.isLetter }).map { String($0).uppercased() } ?? "#"
    }
}
