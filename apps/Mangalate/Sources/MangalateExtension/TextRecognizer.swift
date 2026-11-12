import Foundation
import UIKit
import Vision

/// OCR bằng Vision chạy hoàn toàn trên máy. Ảnh lớn được cắt tile để giới hạn bộ nhớ của appex;
/// tự nhận ngôn ngữ, thử xoay 90° cho chữ dọc CJK. Phần đo nền/bong bóng quanh dòng chữ nằm trong
/// `PageAnalyzer` (không phụ thuộc iOS) để harness trên Linux chạy y hệt.
enum TextRecognizer {
    static let cjkLanguages: Set<String> = ["ja-JP", "ko-KR", "zh-Hans", "zh-Hant"]

    typealias RecognizedLine = PageAnalyzer.RecognizedLine

    static func recognize(image: UIImage, languages requested: [String]?) throws -> [[String: Any]] {
        guard let source = image.cgImage else {
            throw MangalateError("Không đọc được ảnh.")
        }
        let prepared = downscaled(source)
        let languages = resolvedLanguages(requested)
        let verticalPossible = languages.contains { cjkLanguages.contains($0) }
        var collector = PageAnalyzer.Collector(fullWidth: CGFloat(prepared.width), fullHeight: CGFloat(prepared.height))

        for rect in PageAnalyzer.tileRects(width: prepared.width, height: prepared.height) {
            guard let crop = prepared.cropping(to: rect) else { continue }
            autoreleasepool {
                let tileImage = UIImage(cgImage: crop, scale: 1, orientation: .up)
                var found: [RecognizedLine] = []
                do {
                    found = try recognizeLines(tileImage, languages: languages)
                } catch {
                    ExtLog.log("OCR lỗi tile y=\(Int(rect.minY)): \(error.localizedDescription)")
                }

                if verticalPossible, shouldTryRotation(found) {
                    do {
                        let rotated = rotatedCCW(tileImage)
                        let rotatedLines = mapBackFromRotation(
                            try recognizeLines(rotated, languages: languages),
                            width: CGFloat(crop.width),
                            height: CGFloat(crop.height)
                        )
                        if score(rotatedLines) > score(found) {
                            found = rotatedLines
                        }
                    } catch {
                        ExtLog.log("OCR xoay lỗi: \(error.localizedDescription)")
                    }
                }

                guard !found.isEmpty else { return }
                collector.add(origin: rect.origin, grid: pixelGrid(crop), found: found)
            }
        }

        if collector.probeCount > 0 {
            ExtLog.log(String(format: "đường bao: %d lần dò, %.0f ms", collector.probeCount, collector.probeSeconds * 1000))
        }
        return collector.result()
    }

    // MARK: - Vision

    private static func recognizeLines(_ image: UIImage, languages: [String]) throws -> [RecognizedLine] {
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
        return (request.results ?? []).compactMap { observation -> RecognizedLine? in
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
            return RecognizedLine(text: text, confidence: candidate.confidence, box: box)
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

    private static func downscaled(_ cg: CGImage) -> CGImage {
        let target = PageAnalyzer.preparedSize(width: cg.width, height: cg.height)
        guard target.width != cg.width else { return cg }
        let size = CGSize(width: target.width, height: target.height)
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

    /// Vẽ tile ra bộ đệm RGBA để `PixelGrid` đọc pixel.
    private static func pixelGrid(_ cgImage: CGImage) -> PixelGrid? {
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
        return PixelGrid(
            width: cgImage.width,
            height: cgImage.height,
            bytesPerRow: context.bytesPerRow,
            data: UnsafeRawPointer(data),
            owner: context
        )
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

    private static func mapBackFromRotation(_ lines: [RecognizedLine], width: CGFloat, height: CGFloat) -> [RecognizedLine] {
        lines.map { line in
            let box = line.box
            let x = max(0, min(width - box.height, width - box.maxY))
            let y = max(0, min(height - box.width, box.minX))
            return RecognizedLine(
                text: line.text,
                confidence: line.confidence,
                box: CGRect(x: x, y: y, width: min(box.height, width), height: min(box.width, height))
            )
        }
    }

    // MARK: - Chọn kết quả

    private static func shouldTryRotation(_ lines: [RecognizedLine]) -> Bool {
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

    private static func score(_ lines: [RecognizedLine]) -> Int {
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
}
