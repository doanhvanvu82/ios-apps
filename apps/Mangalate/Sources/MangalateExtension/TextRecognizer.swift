import Foundation
import UIKit
import Vision

/// OCR bằng Vision chạy hoàn toàn trên máy. Ảnh lớn được cắt tile để giới hạn bộ nhớ của appex;
/// tự nhận ngôn ngữ, thử xoay 90° cho chữ dọc CJK. Trả box chuẩn hoá 0..1 (gốc trên-trái) + màu nền
/// quanh dòng chữ để JS dán đè bản dịch.
enum TextRecognizer {
    /// Ảnh rộng hơn mức này được thu nhỏ trước khi OCR (toạ độ chuẩn hoá không đổi).
    static let maxWidth: CGFloat = 1600
    static let tileHeight: CGFloat = 2000
    static let overlap: CGFloat = 0.08
    static let cjkLanguages: Set<String> = ["ja-JP", "ko-KR", "zh-Hans", "zh-Hant"]

    private struct Line {
        var text: String
        var confidence: Float
        var box: CGRect
        var bg: String
        /// Tỉ lệ pixel quanh dòng chữ trùng màu nền: bong bóng thoại ~1, chữ đè lên tranh/SFX thấp.
        var fill: Double
        /// Tỉ lệ hướng (0..1) bị nét vẽ vây quanh — ô thoại gần 1, chữ trôi trên nền trắng thấp.
        var enclose: Double
        /// Ô nền đồng nhất bao quanh dòng chữ (bong bóng) — dùng làm khung dán đè thay cho hộp chữ.
        var bubble: CGRect
        /// Đường bao vùng nền quanh chữ (đa giác phẳng [x,y,...] toạ độ ảnh chuẩn hoá) để cắt khung
        /// dán đè theo đúng hình bong bóng thay vì hình chữ nhật.
        var poly: [CGFloat]
    }

    private struct Tile {
        let image: CGImage
        let origin: CGPoint
    }

    static func recognize(image: UIImage, languages requested: [String]?) throws -> [[String: Any]] {
        guard let source = image.cgImage else {
            throw MangalateError("Không đọc được ảnh.")
        }
        let prepared = downscaled(source, maxWidth: maxWidth)
        let languages = resolvedLanguages(requested)
        let verticalPossible = languages.contains { cjkLanguages.contains($0) }
        let fullW = CGFloat(prepared.width)
        let fullH = CGFloat(prepared.height)
        var lines: [Line] = []
        var probeCount = 0
        var probeSeconds = 0.0

        for tile in tiles(of: prepared) {
            autoreleasepool {
                let tileImage = UIImage(cgImage: tile.image, scale: 1, orientation: .up)
                var found: [Line] = []
                do {
                    found = try recognizeLines(tileImage, languages: languages)
                } catch {
                    ExtLog.log("OCR lỗi tile y=\(Int(tile.origin.y)): \(error.localizedDescription)")
                }

                if verticalPossible, shouldTryRotation(found) {
                    do {
                        let rotated = rotatedCCW(tileImage)
                        let rotatedLines = mapBackFromRotation(
                            try recognizeLines(rotated, languages: languages),
                            width: CGFloat(tile.image.width),
                            height: CGFloat(tile.image.height)
                        )
                        if score(rotatedLines) > score(found) {
                            found = rotatedLines
                        }
                    } catch {
                        ExtLog.log("OCR xoay lỗi: \(error.localizedDescription)")
                    }
                }

                guard !found.isEmpty else { return }
                let grid = PixelGrid(cgImage: tile.image)
                // Mỗi bong bóng thường có vài dòng chữ: dò đường bao một lần rồi dùng lại cho các
                // dòng nằm trong đó; dòng đã dò hụt thì nhớ vùng để không dò lại.
                var solvedBubbles: [(CGRect, [CGFloat])] = []
                var failedRects: [CGRect] = []
                for line in found {
                    let box = CGRect(
                        x: (tile.origin.x + line.box.minX) / fullW,
                        y: (tile.origin.y + line.box.minY) / fullH,
                        width: line.box.width / fullW,
                        height: line.box.height / fullH
                    )
                    let background = grid?.borderColor(for: line.box)
                    let fill = grid?.backgroundFill(for: line.box, near: background) ?? 0
                    let bubble = grid?.bubbleBox(for: line.box, near: background) ?? line.box
                    // Dò đường bao đắt — chỉ chạy khi dòng còn khả năng lọt lọc nền ở JS, và chỉ
                    // một lần cho mỗi bong bóng.
                    var contour: [CGFloat]?
                    let center = CGPoint(x: line.box.midX, y: line.box.midY)
                    if let solved = solvedBubbles.first(where: { $0.0.contains(center) }) {
                        contour = solved.1
                    } else if failedRects.contains(where: { $0.contains(line.box) }) {
                        contour = nil
                    } else {
                        if fill >= 0.45 {
                            let started = Date()
                            contour = grid?.bubbleContour(for: line.box, near: background, textBoxes: found.map(\.box))
                            probeSeconds += Date().timeIntervalSince(started)
                            probeCount += 1
                        } else {
                            contour = nil
                        }
                        if fill >= 0.45 {
                            if let contour, let bounds = Self.polygonBounds(contour) {
                                solvedBubbles.append((bounds, contour))
                            } else {
                                let margin = max(20, line.box.height)
                                failedRects.append(line.box.insetBy(dx: -margin, dy: -margin))
                            }
                        }
                    }
                    lines.append(Line(
                        text: line.text,
                        confidence: line.confidence,
                        box: box,
                        bg: background ?? "#ffffff",
                        fill: fill,
                        enclose: grid?.encloseRatio(for: line.box, near: background) ?? 0,
                        bubble: CGRect(
                            x: (tile.origin.x + bubble.minX) / fullW,
                            y: (tile.origin.y + bubble.minY) / fullH,
                            width: bubble.width / fullW,
                            height: bubble.height / fullH
                        ),
                        poly: (contour ?? []).enumerated().map { index, value in
                            index % 2 == 0
                                ? (tile.origin.x + value) / fullW
                                : (tile.origin.y + value) / fullH
                        }
                    ))
                }
            }
        }

        if probeCount > 0 {
            ExtLog.log(String(format: "đường bao: %d lần dò, %.0f ms", probeCount, probeSeconds * 1000))
        }
        let cleaned = deduplicated(lines).sorted { a, b in
            abs(a.box.minY - b.box.minY) > 0.01 ? a.box.minY < b.box.minY : a.box.minX < b.box.minX
        }
        return cleaned.prefix(500).map { line in
            [
                "text": line.text,
                "confidence": Double(line.confidence),
                "box": [
                    rounded(line.box.minX), rounded(line.box.minY),
                    rounded(line.box.width), rounded(line.box.height),
                ],
                "bg": line.bg,
                "fill": (line.fill * 100).rounded() / 100,
                "enclose": (line.enclose * 100).rounded() / 100,
                "bub": [
                    rounded(line.bubble.minX), rounded(line.bubble.minY),
                    rounded(line.bubble.width), rounded(line.bubble.height),
                ],
                "poly": line.poly.map { rounded($0) },
            ]
        }
    }

    /// Hộp bao của đa giác phẳng [x, y, ...] — dùng để biết dòng khác có thuộc bong bóng đã dò không.
    private static func polygonBounds(_ poly: [CGFloat]) -> CGRect? {
        guard poly.count >= 6 else { return nil }
        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude
        for index in stride(from: 0, to: poly.count - 1, by: 2) {
            minX = Swift.min(minX, poly[index])
            maxX = Swift.max(maxX, poly[index])
            minY = Swift.min(minY, poly[index + 1])
            maxY = Swift.max(maxY, poly[index + 1])
        }
        guard maxX > minX, maxY > minY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    // MARK: - Vision

    private static func recognizeLines(_ image: UIImage, languages: [String]) throws -> [Line] {
        guard let cg = image.cgImage else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        // Truyện tranh nhiều từ không có trong từ điển, sửa lỗi sẽ làm sai.
        request.usesLanguageCorrection = false
        request.recognitionLanguages = languages
        request.revision = preferredRevision
        if #available(iOS 16.0, *) {
            request.automaticallyDetectsLanguage = true
        }
        let handler = VNImageRequestHandler(cgImage: cg, orientation: .up, options: [:])
        try handler.perform([request])

        let width = CGFloat(cg.width)
        let height = CGFloat(cg.height)
        return (request.results ?? []).compactMap { observation -> Line? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, candidate.confidence >= 0.25 else { return nil }
            let boundingBox = observation.boundingBox
            let box = CGRect(
                x: boundingBox.minX * width,
                y: (1 - boundingBox.maxY) * height,
                width: boundingBox.width * width,
                height: boundingBox.height * height
            )
            return Line(text: text, confidence: candidate.confidence, box: box, bg: "#ffffff", fill: 0, enclose: 0, bubble: box, poly: [])
        }
    }

    private static let preferredRevision: Int = {
        let revisions = VNRecognizeTextRequest.supportedRevisions
        return revisions.contains(VNRecognizeTextRequestRevision3) ? VNRecognizeTextRequestRevision3 : (revisions.first ?? 1)
    }()

    private static let supportedLanguages: Set<String> = {
        let languages = (try? VNRecognizeTextRequest.supportedRecognitionLanguages(
            for: .accurate,
            revision: preferredRevision
        )) ?? []
        return Set(languages)
    }()

    /// Không truyền danh sách → dùng mọi ngôn ngữ Vision hỗ trợ trên máy (càng nhiều càng tốt).
    private static func resolvedLanguages(_ requested: [String]?) -> [String] {
        let wanted = requested?.isEmpty == false ? requested! : Array(supportedLanguages)
        let filtered = wanted.filter { supportedLanguages.contains($0) }
        return filtered.isEmpty ? ["en-US"] : filtered
    }

    // MARK: - Ảnh

    private static func downscaled(_ cg: CGImage, maxWidth: CGFloat) -> CGImage {
        let width = CGFloat(cg.width)
        guard width > maxWidth else { return cg }
        let scale = maxWidth / width
        let size = CGSize(width: maxWidth.rounded(), height: (CGFloat(cg.height) * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            // Ảnh trong suốt thường là nền đen khi đổi định dạng → tô trắng cho OCR và lấy màu nền.
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIImage(cgImage: cg).draw(in: CGRect(origin: .zero, size: size))
        }
        return image.cgImage ?? cg
    }

    private static func tiles(of cg: CGImage) -> [Tile] {
        let width = cg.width
        let height = cg.height
        let maxHeight = Int(tileHeight)
        guard height > maxHeight else { return [Tile(image: cg, origin: .zero)] }
        let step = max(1, Int(Double(maxHeight) * (1 - Double(overlap))))
        var result: [Tile] = []
        var y = 0
        while y < height {
            let tileH = min(maxHeight, height - y)
            if let crop = cg.cropping(to: CGRect(x: 0, y: CGFloat(y), width: CGFloat(width), height: CGFloat(tileH))) {
                result.append(Tile(image: crop, origin: CGPoint(x: 0, y: CGFloat(y))))
            }
            if y + tileH >= height { break }
            y += step
        }
        return result
    }

    /// Xoay 90° ngược chiều kim đồng hồ: cột chữ dọc đọc trên→dưới thành dòng ngang trái→phải.
    private static func rotatedCCW(_ image: UIImage) -> UIImage {
        guard let cg = image.cgImage else { return image }
        let oriented = UIImage(cgImage: cg, scale: 1, orientation: .left)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: oriented.size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: oriented.size))
            oriented.draw(in: CGRect(origin: .zero, size: oriented.size))
        }
    }

    private static func mapBackFromRotation(_ lines: [Line], width: CGFloat, height: CGFloat) -> [Line] {
        lines.map { line in
            let box = line.box
            let x = max(0, min(width - box.height, width - box.maxY))
            let y = max(0, min(height - box.width, box.minX))
            return Line(
                text: line.text,
                confidence: line.confidence,
                box: CGRect(x: x, y: y, width: min(box.height, width), height: min(box.width, height)),
                bg: line.bg,
                fill: line.fill,
                enclose: line.enclose,
                bubble: CGRect(x: x, y: y, width: min(box.height, width), height: min(box.width, height)),
                poly: []
            )
        }
    }

    // MARK: - Chọn kết quả

    private static func shouldTryRotation(_ lines: [Line]) -> Bool {
        let text = lines.map(\.text).joined()
        var cjk = 0
        var latin = 0
        for scalar in text.unicodeScalars {
            if isCJK(scalar) { cjk += 1 }
            if scalar.isASCII, scalar.value >= 65, scalar.value <= 90 || scalar.value >= 97, scalar.value <= 122 {
                latin += 1
            }
        }
        // Ít chữ Hán/Kana/Hangul và ít chữ Latin: có thể là chữ dọc Vision đọc không ra.
        return cjk < 4 && latin < 20
    }

    private static func score(_ lines: [Line]) -> Int {
        lines.reduce(0) { total, line in
            total + line.text.unicodeScalars.reduce(0) { $0 + (isCJK($1) ? 3 : 1) }
        }
    }

    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xAC00...0xD7AF, 0xF900...0xFAFF, 0xFF66...0xFF9D:
            return true
        default:
            return false
        }
    }

    private static func deduplicated(_ lines: [Line]) -> [Line] {
        var kept: [Line] = []
        for line in lines {
            if let index = kept.firstIndex(where: { $0.text == line.text && iou($0.box, line.box) > 0.5 }) {
                if line.confidence > kept[index].confidence { kept[index] = line }
            } else {
                kept.append(line)
            }
        }
        return kept
    }

    private static func iou(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let intersection = a.intersection(b)
        guard !intersection.isNull, !intersection.isEmpty else { return 0 }
        let intersectionArea = intersection.width * intersection.height
        let union = a.width * a.height + b.width * b.height - intersectionArea
        return union > 0 ? intersectionArea / union : 0
    }

    private static func rounded(_ value: CGFloat) -> Double {
        (Double(value) * 10_000).rounded() / 10_000
    }

    // MARK: - Màu nền

    /// Ảnh RGBA đã vẽ sẵn để lấy màu viền quanh box chữ (nền bong bóng).
    private final class PixelGrid {
        let width: Int
        let height: Int
        private let context: CGContext
        private let data: UnsafeMutableRawPointer
        private let bytesPerRow: Int

        init?(cgImage: CGImage) {
            guard let context = CGContext(
                data: nil,
                width: cgImage.width,
                height: cgImage.height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ), let data = context.data else {
                return nil
            }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: CGFloat(cgImage.width), height: CGFloat(cgImage.height)))
            self.context = context
            self.data = data
            self.width = cgImage.width
            self.height = cgImage.height
            self.bytesPerRow = context.bytesPerRow
        }

        /// Trung vị màu của viền ngoài box (viền là nền bong bóng, box là chữ).
        func borderColor(for rect: CGRect) -> String? {
            borderRGB(for: rect).map { String(format: "#%02x%02x%02x", $0.0, $0.1, $0.2) }
        }

        /// Tỉ lệ pixel trong dải ngoài box gần màu nền: bong bóng thoại gần 1, chữ đè lên tranh (SFX, chú thích) thấp.
        /// Dải rộng khoảng nửa chiều cao dòng — đủ thấy nền bong bóng mà không lấn sang bong bóng bên cạnh.
        func backgroundFill(for rect: CGRect, near hex: String?) -> Double? {
            guard let background = hex.flatMap(Self.rgb) else { return nil }
            let pad = max(3, min(24, Int(rect.height * 0.6)))
            let x0 = max(0, Int(rect.minX) - pad)
            let y0 = max(0, Int(rect.minY) - pad)
            let x1 = min(width - 1, Int(rect.maxX) + pad)
            let y1 = min(height - 1, Int(rect.maxY) + pad)
            guard x1 > x0, y1 > y0 else { return nil }

            // Viền box có thể dính chữ/đường kẻ của bong bóng → cũng nhận là nền.
            let targets = [background, borderRGB(for: rect)].compactMap { $0 }
            let stepX = max(1, (x1 - x0) / 24)
            let stepY = max(1, (y1 - y0) / 24)
            var total = 0
            var matching = 0
            for y in stride(from: y0, through: y1, by: stepY) {
                for x in stride(from: x0, through: x1, by: stepX) {
                    // Bỏ pixel bên trong box: đó là chữ, cố tình khác màu nền.
                    if rect.contains(CGPoint(x: x, y: y)) { continue }
                    let offset = y * bytesPerRow + x * 4
                    let red = Int(data.load(fromByteOffset: offset, as: UInt8.self))
                    let green = Int(data.load(fromByteOffset: offset + 1, as: UInt8.self))
                    let blue = Int(data.load(fromByteOffset: offset + 2, as: UInt8.self))
                    total += 1
                    let closest = targets.map { color -> Int in
                        let dr = red - Int(color.0)
                        let dg = green - Int(color.1)
                        let db = blue - Int(color.2)
                        return dr * dr + dg * dg + db * db
                    }.min() ?? Int.max
                    if closest <= 42 * 42 { matching += 1 }
                }
            }
            return total > 0 ? Double(matching) / Double(total) : nil
        }

        /// Tỉ lệ hướng bị nét vẽ/hiệu ứng vây quanh chữ (dấu hiệu bong bóng thoại).
        /// Bắn 24 tia toả đều từ tâm chữ; tia gặp pixel khác màu nền được tính là một hướng có biên.
        /// Tia hở (xuyên qua khe giữa các nét trang trí) không tính; mép ảnh cũng không tính —
        /// nhờ vậy bong bóng trắng trên trang trắng vẫn đạt (halo vây kín) còn chữ credit trôi trên
        /// nền trắng thì trượt (phần lớn hướng đi mãi không gặp gì). Trả 0..1 để JS đặt ngưỡng.
        func encloseRatio(for rect: CGRect, near hex: String?) -> Double {
            guard let background = hex.flatMap(Self.rgb) else { return 0 }
            let limit = max(60, min(width, height) / 2)
            let rays = 24
            var hits = 0
            for index in 0..<rays {
                let angle = Double(index) * 2 * Double.pi / Double(rays)
                let dx = cos(angle) * 2
                let dy = sin(angle) * 2
                var x = Double(rect.midX)
                var y = Double(rect.midY)
                var travelled = 0.0
                while travelled < Double(limit) {
                    x += dx
                    y += dy
                    travelled += 2
                    let px = Int(x)
                    let py = Int(y)
                    if px < 0 || py < 0 || px >= width || py >= height { break }
                    // Trong box là chữ — cố tình khác nền, bỏ qua.
                    if rect.contains(CGPoint(x: x, y: y)) { continue }
                    let offset = py * bytesPerRow + px * 4
                    let red = Int(data.load(fromByteOffset: offset, as: UInt8.self))
                    let green = Int(data.load(fromByteOffset: offset + 1, as: UInt8.self))
                    let blue = Int(data.load(fromByteOffset: offset + 2, as: UInt8.self))
                    let dr = red - Int(background.0)
                    let dg = green - Int(background.1)
                    let db = blue - Int(background.2)
                    if dr * dr + dg * dg + db * db > 42 * 42 {
                        hits += 1
                        break
                    }
                }
            }
            return Double(hits) / Double(rays)
        }

        /// Đường bao lõi bong bóng để cắt khung dán đè theo đúng hình bong bóng.
        ///
        /// Mép bong bóng là vành tia/hơi rời nhau; flood thô sẽ chảy qua khe giữa các tia ra nền
        /// trang và đường bao thành hình chữ nhật. Vì vậy: đóng khe bằng morphological closing trên
        /// lưới thô (mỗi ô là tường nếu có pixel khác nền — tức đã dilate sẵn), rồi flood vùng nền
        /// từ tâm hộp chữ. Thử kernel tăng dần, nhận kết quả đầu tiên không chạm mép vùng tìm kiếm
        /// và có diện tích hợp lý; không có thì trả nil để JS dùng hình chữ nhật.
        /// Chạy trên lưới `step` px thay vì từng pixel để đủ nhanh trong appex.
        func bubbleContour(for rect: CGRect, near hex: String?, textBoxes: [CGRect] = []) -> [CGFloat]? {
            guard let background = hex.flatMap(Self.rgb) else { return nil }
            let tolerance = 28 * 28
            func isBackground(_ x: Int, _ y: Int) -> Bool {
                guard x >= 0, y >= 0, x < width, y < height else { return false }
                let offset = y * bytesPerRow + x * 4
                let red = Int(data.load(fromByteOffset: offset, as: UInt8.self))
                let green = Int(data.load(fromByteOffset: offset + 1, as: UInt8.self))
                let blue = Int(data.load(fromByteOffset: offset + 2, as: UInt8.self))
                let dr = red - Int(background.0)
                let dg = green - Int(background.1)
                let db = blue - Int(background.2)
                return dr * dr + dg * dg + db * db <= tolerance
            }

            let pad = max(80, min(400, Int(max(rect.width, rect.height) * 1.5)))
            let left = max(0, Int(rect.minX) - pad)
            let right = min(width - 1, Int(rect.maxX) + pad)
            let top = max(0, Int(rect.minY) - pad)
            let bottom = min(height - 1, Int(rect.maxY) + pad)
            guard right - left > 18, bottom - top > 18 else { return nil }
            // Lưới thô, tự nới bước khi vùng lớn để giữ chi phí cố định.
            var step = 3
            var cols = (right - left) / step + 1
            var rows = (bottom - top) / step + 1
            while cols * rows > 18_000, step < 24 {
                step += 1
                cols = (right - left) / step + 1
                rows = (bottom - top) / step + 1
            }
            guard cols * rows <= 18_000 else { return nil }

            // Tường = ô có ít nhất một pixel khác màu nền (gộp cả bước dilate).
            var wall = [Bool](repeating: false, count: cols * rows)
            for gy in 0..<rows {
                for gx in 0..<cols {
                    var hit = false
                    for dy in 0..<step where !hit {
                        for dx in 0..<step where !hit {
                            let x = left + gx * step + dx
                            let y = top + gy * step + dy
                            if x >= width || y >= height || !isBackground(x, y) { hit = true }
                        }
                    }
                    wall[gy * cols + gx] = hit
                }
            }

            /// Morphology vuông tách thành hai lượt ngang/dọc; ngoài biên coi là tường.
            func morph(_ mask: [Bool], kernel: Int, grow: Bool) -> [Bool] {
                let radius = Swift.max(0, kernel / 2)
                var mid = mask
                if radius > 0 {
                    for y in 0..<rows {
                        let base = y * cols
                        for x in 0..<cols {
                            var value = !grow
                            for d in -radius...radius {
                                let nx = x + d
                                let bit = nx < 0 || nx >= cols ? true : mask[base + nx]
                                if grow ? bit : !bit { value = grow; break }
                            }
                            mid[base + x] = value
                        }
                    }
                    var out = mid
                    for x in 0..<cols {
                        for y in 0..<rows {
                            var value = !grow
                            for d in -radius...radius {
                                let ny = y + d
                                let bit = ny < 0 || ny >= rows ? true : mid[ny * cols + x]
                                if grow ? bit : !bit { value = grow; break }
                            }
                            out[y * cols + x] = value
                        }
                    }
                    return out
                }
                return mid
            }

            func nearestFree(_ free: [Bool], from gx: Int, _ gy: Int) -> Int? {
                if free[gy * cols + gx] { return gy * cols + gx }
                let limit = Swift.max(cols, rows)
                for radius in 1..<limit {
                    var d = -radius
                    while d <= radius {
                        for (x, y) in [(gx + d, gy - radius), (gx + d, gy + radius), (gx - radius, gy + d), (gx + radius, gy + d)] {
                            guard x >= 0, y >= 0, x < cols, y < rows else { continue }
                            if free[y * cols + x] { return y * cols + x }
                        }
                        d += 1
                    }
                }
                return nil
            }

            let seedsX = (Int(rect.midX) - left) / step
            let seedsY = (Int(rect.midY) - top) / step
            let clampedX = Swift.min(cols - 1, Swift.max(0, seedsX))
            let clampedY = Swift.min(rows - 1, Swift.max(0, seedsY))

            for kernel in [3, 5, 7, 9, 11] {
                let closed = morph(morph(wall, kernel: kernel, grow: true), kernel: kernel, grow: false)
                var free = [Bool](repeating: false, count: cols * rows)
                for index in 0..<(cols * rows) { free[index] = !closed[index] }
                guard let start = nearestFree(free, from: clampedX, clampedY) else { continue }

                var visited = [Bool](repeating: false, count: cols * rows)
                var rowMin = [Int](repeating: Int.max, count: rows)
                var rowMax = [Int](repeating: -1, count: rows)
                var count = 0
                var touches = false
                var stack = [start]
                visited[start] = true
                while let index = stack.popLast() {
                    let gy = index / cols
                    let gx = index % cols
                    count += 1
                    if gx < rowMin[gy] { rowMin[gy] = gx }
                    if gx > rowMax[gy] { rowMax[gy] = gx }
                    if gx <= 0 || gy <= 0 || gx >= cols - 1 || gy >= rows - 1 { touches = true }
                    if gx > 0, !visited[index - 1], free[index - 1] { visited[index - 1] = true; stack.append(index - 1) }
                    if gx < cols - 1, !visited[index + 1], free[index + 1] { visited[index + 1] = true; stack.append(index + 1) }
                    if gy > 0, !visited[index - cols], free[index - cols] { visited[index - cols] = true; stack.append(index - cols) }
                    if gy < rows - 1, !visited[index + cols], free[index + cols] { visited[index + cols] = true; stack.append(index + cols) }
                }

                let area = Double(count) / Double(cols * rows)
                // Chạm mép ảnh KHÔNG loại: bong bóng lớn hay bị crop sát mép. Chặn bằng diện tích —
                // lõi bong bóng luôn nhỏ hơn nửa ảnh, còn "rò ra nền trang" cho vùng gần kín ảnh.
                let areaLimit = touches ? 0.50 : 0.60
                if area <= 0.03 || area >= areaLimit { continue }

                // Mở mép trái/phải cho bao trọn hộp chữ, nhưng CHỈ ở hàng flood đã có mặt: hàng
                // không có flood nghĩa là chữ nằm ngoài vùng nền (hoặc hộp chữ rộng hơn bong
                // bóng) — mở ra đó sẽ phủ trắng cả vùng tranh hai bên. Thiếu bước này, bong bóng
                // hẹp mà chữ rộng sẽ bị chính chữ chặn và nền chỉ phủ dải giữa.
                let textFirst = Swift.min(rows - 1, Swift.max(0, (Int(rect.minY) - top) / step))
                let textLast = Swift.min(rows - 1, Swift.max(0, (Int(rect.maxY) - top) / step))
                let textLeft = Swift.max(0, (Int(rect.minX) - left) / step)
                let textRight = Swift.min(cols - 1, (Int(rect.maxX) - left) / step)
                if textFirst <= textLast {
                    for row in textFirst...textLast {
                        if rowMax[row] < 0 {
                            rowMin[row] = textLeft
                            rowMax[row] = textRight
                            continue
                        }
                        // Quét tiếp ra hai phía trên đúng hàng này, BỎ QUA pixel chữ, dừng ở nét
                        // viền thật. Nhờ vậy đường bao đi theo mép bong bóng thay vì dừng ở chữ —
                        // bong bóng hẹp mà chữ rộng vẫn phủ kín chữ gốc.
                        let y = top + row * step
                        func inText(_ x: Int) -> Bool {
                            textBoxes.contains { box in
                                CGFloat(x) >= box.minX && CGFloat(x) <= box.maxX
                                    && CGFloat(y) >= box.minY && CGFloat(y) <= box.maxY
                            }
                        }
                        // Giới hạn quét: hộp chữ sai (OCR gộp nhiều dòng) không được kéo khung ra
                        // tận mép ảnh.
                        let maxScan = Swift.max(Int(rect.width), 24)
                        var cursor = left + rowMin[row] * step
                        var travelled = 0
                        while cursor > left, travelled < maxScan {
                            if !isBackground(cursor, y) && !inText(cursor) { break }
                            cursor -= step
                            travelled += step
                        }
                        rowMin[row] = Swift.min(rowMin[row], Swift.max(0, (cursor - left) / step + 1))
                        cursor = left + rowMax[row] * step
                        travelled = 0
                        while cursor < right, travelled < maxScan {
                            if !isBackground(cursor, y) && !inText(cursor) { break }
                            cursor += step
                            travelled += step
                        }
                        rowMax[row] = Swift.max(rowMax[row], Swift.min(cols - 1, (cursor - left) / step - 1))
                    }
                }

                let filled = (0..<rows).filter { rowMax[$0] >= 0 }
                guard filled.count >= 4, let first = filled.first, let last = filled.last else { continue }
                // Vùng loang không được dẹt hơn khối chữ: flood kẹt giữa các dòng chữ cho một dải
                // mỏng nằm trong bong bóng và bị nhận nhầm là đường bao.
                let spanY = CGFloat((last - first) * step)
                let spanX = CGFloat((filled.map { rowMax[$0] }.max() ?? 0) - (filled.map { rowMin[$0] }.min() ?? 0)) * CGFloat(step)
                if spanY < rect.height * 0.5 || spanX < rect.width * 0.5 { continue }
                let samples = Swift.min(28, filled.count)
                var points: [CGFloat] = []
                var rightPoints: [CGFloat] = []
                for index in 0..<samples {
                    let row = first + (last - first) * index / Swift.max(1, samples - 1)
                    guard rowMax[row] >= 0 else { continue }
                    let y = CGFloat(top + row * step)
                    points.append(CGFloat(left + rowMin[row] * step))
                    points.append(y)
                    rightPoints.insert(CGFloat(left + rowMax[row] * step), at: 0)
                    rightPoints.insert(y, at: 1)
                }
                guard points.count >= 6 else { continue }
                return points + rightPoints
            }
            return nil
        }

        /// Ô nền đồng nhất bao quanh dòng chữ (bong bóng thoại): nới box ra 4 phía chừng nào hàng/cột
        /// quanh đó còn gần như toàn màu nền. Khung dán đè nhờ vậy phủ theo bong bóng thay vì hộp chữ.
        func bubbleBox(for rect: CGRect, near hex: String?) -> CGRect {
            guard let background = hex.flatMap(Self.rgb) else { return rect }
            let tolerance = 42 * 42
            func isBackground(_ x: Int, _ y: Int) -> Bool {
                guard x >= 0, y >= 0, x < width, y < height else { return false }
                let offset = y * bytesPerRow + x * 4
                let red = Int(data.load(fromByteOffset: offset, as: UInt8.self))
                let green = Int(data.load(fromByteOffset: offset + 1, as: UInt8.self))
                let blue = Int(data.load(fromByteOffset: offset + 2, as: UInt8.self))
                let dr = red - Int(background.0)
                let dg = green - Int(background.1)
                let db = blue - Int(background.2)
                return dr * dr + dg * dg + db * db <= tolerance
            }
            /// Cột/hàng phải gần như toàn nền mới coi là còn nằm trong bong bóng. Lấy mẫu dày
            /// (≤40 điểm) để không bỏ qua viền mỏng giữa hai bong bóng sát nhau.
            func lineMostlyBackground(stepByX: Bool, _ fixed: Int, _ from: Int, _ to: Int) -> Bool {
                guard to >= from else { return false }
                let step = max(1, (to - from) / 40)
                var total = 0
                var hit = 0
                var value = from
                while value <= to {
                    total += 1
                    if stepByX ? isBackground(value, fixed) : isBackground(fixed, value) { hit += 1 }
                    value += step
                }
                return total > 0 && hit * 100 >= total * 97
            }

            var x0 = Int(rect.minX.rounded(.down))
            var x1 = Int(rect.maxX.rounded(.up))
            var y0 = Int(rect.minY.rounded(.down))
            var y1 = Int(rect.maxY.rounded(.up))
            let maxExpandX = max(24, Int(rect.width))
            let maxExpandY = max(20, Int(rect.height))
            var stepX = 0
            while stepX < maxExpandX, x0 > 0, lineMostlyBackground(stepByX: false, x0 - 1, y0, y1) { x0 -= 1; stepX += 1 }
            stepX = 0
            while stepX < maxExpandX, x1 < width - 1, lineMostlyBackground(stepByX: false, x1 + 1, y0, y1) { x1 += 1; stepX += 1 }
            var stepY = 0
            while stepY < maxExpandY, y0 > 0, lineMostlyBackground(stepByX: true, y0 - 1, x0, x1) { y0 -= 1; stepY += 1 }
            stepY = 0
            while stepY < maxExpandY, y1 < height - 1, lineMostlyBackground(stepByX: true, y1 + 1, x0, x1) { y1 += 1; stepY += 1 }
            return CGRect(x: x0, y: y0, width: max(1, x1 - x0), height: max(1, y1 - y0))
        }

        private static func rgb(_ hex: String) -> (UInt8, UInt8, UInt8)? {
            let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
            guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
            return (UInt8((value >> 16) & 255), UInt8((value >> 8) & 255), UInt8(value & 255))
        }

        private func borderRGB(for rect: CGRect) -> (UInt8, UInt8, UInt8)? {
            let pad = 3
            let x0 = max(0, Int(rect.minX) - pad)
            let y0 = max(0, Int(rect.minY) - pad)
            let x1 = min(width - 1, Int(rect.maxX) + pad)
            let y1 = min(height - 1, Int(rect.maxY) + pad)
            guard x1 > x0, y1 > y0 else { return nil }

            var reds: [UInt8] = []
            var greens: [UInt8] = []
            var blues: [UInt8] = []
            reds.reserveCapacity(420)
            greens.reserveCapacity(420)
            blues.reserveCapacity(420)

            func sample(_ x: Int, _ y: Int) {
                let offset = y * bytesPerRow + x * 4
                reds.append(data.load(fromByteOffset: offset, as: UInt8.self))
                greens.append(data.load(fromByteOffset: offset + 1, as: UInt8.self))
                blues.append(data.load(fromByteOffset: offset + 2, as: UInt8.self))
            }

            let stepX = max(1, (x1 - x0) / 24)
            let stepY = max(1, (y1 - y0) / 24)
            for x in stride(from: x0, through: x1, by: stepX) {
                sample(x, y0)
                sample(x, y1)
            }
            for y in stride(from: y0, through: y1, by: stepY) {
                sample(x0, y)
                sample(x1, y)
            }

            guard !reds.isEmpty else { return nil }
            func median(_ values: [UInt8]) -> UInt8 { values.sorted()[values.count / 2] }
            return (median(reds), median(greens), median(blues))
        }
    }
}
