import Foundation

/// Ảnh RGBA để đo nền bong bóng quanh dòng chữ. Chỉ dùng Foundation: `tools/native-harness`
/// biên dịch đúng file này trên Linux.
final class PixelGrid {
    let width: Int
    let height: Int
    private let data: UnsafeRawPointer
    private let bytesPerRow: Int
    /// Giữ bộ nhớ `data` sống cùng grid (CGContext trên iOS, mảng byte trong harness).
    private let owner: AnyObject

    /// `data`: RGBA 8 bit mỗi kênh, hàng đầu tiên là mép trên ảnh.
    init(width: Int, height: Int, bytesPerRow: Int, data: UnsafeRawPointer, owner: AnyObject) {
        self.width = width
        self.height = height
        self.bytesPerRow = bytesPerRow
        self.data = data
        self.owner = owner
    }

    /// Trung vị màu của viền ngoài box (viền là nền bong bóng, box là chữ).
    func borderColor(for rect: CGRect) -> String? {
        borderRGB(for: rect).map { String(format: "#%02x%02x%02x", $0.0, $0.1, $0.2) }
    }

    /// Tỉ lệ pixel trong dải ngoài box gần màu nền: bong bóng thoại gần 1, chữ đè lên tranh (SFX, chú thích) thấp.
    /// Dải rộng khoảng nửa chiều cao dòng — đủ thấy nền bong bóng mà không lấn sang bong bóng bên cạnh.
    /// `otherText`: hộp các dòng chữ khác — bỏ qua như chính box: chữ viết dày (dòng cách nhau ít hơn
    /// dải đo) không phải tranh, tính vào thì thoại thật cũng tụt dưới ngưỡng lọc.
    func backgroundFill(for rect: CGRect, near hex: String?, otherText: [CGRect] = []) -> Double? {
        guard let background = hex.flatMap(Self.rgb) else { return nil }
        let pad = max(3, min(24, Int(rect.height * 0.6)))
        let x0 = max(0, Int(rect.minX) - pad)
        let y0 = max(0, Int(rect.minY) - pad)
        let x1 = min(width - 1, Int(rect.maxX) + pad)
        let y1 = min(height - 1, Int(rect.maxY) + pad)
        guard x1 > x0, y1 > y0 else { return nil }
        let band = CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
        let skip = [rect] + otherText.filter { $0 != rect && $0.intersects(band) }

        // Viền box có thể dính chữ/đường kẻ của bong bóng → cũng nhận là nền.
        let targets = [background, borderRGB(for: rect)].compactMap { $0 }
        let stepX = max(1, (x1 - x0) / 24)
        let stepY = max(1, (y1 - y0) / 24)
        var total = 0
        var matching = 0
        for y in stride(from: y0, through: y1, by: stepY) {
            for x in stride(from: x0, through: x1, by: stepX) {
                // Bỏ pixel bên trong box: đó là chữ, cố tình khác màu nền.
                let point = CGPoint(x: x, y: y)
                if skip.contains(where: { $0.contains(point) }) { continue }
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
