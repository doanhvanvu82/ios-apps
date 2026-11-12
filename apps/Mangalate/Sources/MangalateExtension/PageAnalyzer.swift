import Foundation

/// Phần OCR không phụ thuộc Vision/UIKit: chia tile, đo nền/độ vây/đường bao bong bóng quanh từng dòng chữ,
/// lọc trùng và xuất kết quả cho JS. Chỉ dùng Foundation để `tools/native-harness` biên dịch đúng file này
/// trên Linux — harness thay Vision bằng OCR khác nhưng phân tích pixel y hệt appex.
enum PageAnalyzer {
    /// Ảnh rộng hơn mức này được thu nhỏ trước khi OCR (toạ độ chuẩn hoá không đổi).
    static let maxWidth: CGFloat = 1600
    static let tileHeight: CGFloat = 2000
    static let overlap: CGFloat = 0.08

    /// Một dòng chữ OCR trả về, toạ độ pixel trong tile (gốc trên-trái).
    struct RecognizedLine {
        var text: String
        var confidence: Float
        var box: CGRect
    }

    fileprivate struct Line {
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

    /// Kích thước ảnh sau khi thu nhỏ về `maxWidth`.
    static func preparedSize(width: Int, height: Int) -> (width: Int, height: Int) {
        guard CGFloat(width) > maxWidth else { return (width, height) }
        let scale = maxWidth / CGFloat(width)
        return (Int(maxWidth.rounded()), Int((CGFloat(height) * scale).rounded()))
    }

    /// Dải ngang chồng lên nhau `overlap` để dòng chữ nằm ngay mép tile vẫn được đọc trọn ở tile kế.
    static func tileRects(width: Int, height: Int) -> [CGRect] {
        let maxHeight = Int(tileHeight)
        guard height > maxHeight else { return [CGRect(x: 0, y: 0, width: width, height: height)] }
        let step = max(1, Int(Double(maxHeight) * (1 - Double(overlap))))
        var result: [CGRect] = []
        var y = 0
        while y < height {
            let tileH = min(maxHeight, height - y)
            result.append(CGRect(x: 0, y: y, width: width, height: tileH))
            if y + tileH >= height { break }
            y += step
        }
        return result
    }

    /// Gom dòng chữ từng tile ngay sau khi OCR tile đó, để bộ đệm pixel của tile được giải phóng sớm
    /// (appex bị giới hạn bộ nhớ).
    struct Collector {
        let fullWidth: CGFloat
        let fullHeight: CGFloat
        private var lines: [Line] = []
        private(set) var probeCount = 0
        private(set) var probeSeconds = 0.0

        init(fullWidth: CGFloat, fullHeight: CGFloat) {
            self.fullWidth = fullWidth
            self.fullHeight = fullHeight
        }

        /// `found`: dòng chữ của tile, toạ độ pixel trong tile; `origin`: góc trên-trái tile trong ảnh.
        mutating func add(origin: CGPoint, grid: PixelGrid?, found: [RecognizedLine]) {
            // Mỗi bong bóng thường có vài dòng chữ: dò đường bao một lần rồi dùng lại cho các
            // dòng nằm trong đó; dòng đã dò hụt thì nhớ vùng để không dò lại.
            var solvedBubbles: [(CGRect, [CGFloat])] = []
            var failedRects: [CGRect] = []
            let textBoxes = found.map(\.box)
            for line in found {
                let box = CGRect(
                    x: (origin.x + line.box.minX) / fullWidth,
                    y: (origin.y + line.box.minY) / fullHeight,
                    width: line.box.width / fullWidth,
                    height: line.box.height / fullHeight
                )
                let background = grid?.borderColor(for: line.box)
                let fill = grid?.backgroundFill(for: line.box, near: background, otherText: textBoxes) ?? 0
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
                        contour = grid?.bubbleContour(for: line.box, near: background, textBoxes: textBoxes)
                        probeSeconds += Date().timeIntervalSince(started)
                        probeCount += 1
                    } else {
                        contour = nil
                    }
                    if fill >= 0.45 {
                        if let contour, let bounds = PageAnalyzer.polygonBounds(contour) {
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
                        x: (origin.x + bubble.minX) / fullWidth,
                        y: (origin.y + bubble.minY) / fullHeight,
                        width: bubble.width / fullWidth,
                        height: bubble.height / fullHeight
                    ),
                    poly: (contour ?? []).enumerated().map { index, value in
                        index % 2 == 0
                            ? (origin.x + value) / fullWidth
                            : (origin.y + value) / fullHeight
                    }
                ))
            }
        }

        /// [{text, confidence, box, bg, fill, enclose, bub, poly}] chuẩn hoá theo ảnh, theo thứ tự đọc.
        func result() -> [[String: Any]] {
            let cleaned = PageAnalyzer.deduplicated(lines).sorted { a, b in
                abs(a.box.minY - b.box.minY) > 0.01 ? a.box.minY < b.box.minY : a.box.minX < b.box.minX
            }
            return cleaned.prefix(500).map { line in
                [
                    "text": line.text,
                    "confidence": Double(line.confidence),
                    "box": PageAnalyzer.rounded(line.box),
                    "bg": line.bg,
                    "fill": (line.fill * 100).rounded() / 100,
                    "enclose": (line.enclose * 100).rounded() / 100,
                    "bub": PageAnalyzer.rounded(line.bubble),
                    "poly": line.poly.map { PageAnalyzer.rounded($0) },
                ]
            }
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

    private static func rounded(_ rect: CGRect) -> [Double] {
        [rounded(rect.minX), rounded(rect.minY), rounded(rect.width), rounded(rect.height)]
    }
}
