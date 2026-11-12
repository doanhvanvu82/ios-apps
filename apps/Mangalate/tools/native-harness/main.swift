import Foundation

// Chạy phần phân tích pixel của appex (PageAnalyzer + PixelGrid, biên dịch nguyên file) trên Linux.
// OCR do harness Python làm thay Vision; CLI này nhận dòng chữ từng tile + ảnh RGBA thô của tile.
//
//   native-harness plan <width> <height>   → {"width","height","tiles":[[x,y,w,h],...]} (thu nhỏ + chia tile y như appex)
//   native-harness analyze <job.json>      → [{text, confidence, box, bg, fill, enclose, bub, poly}] y như native trả JS
//
// job.json: {"width":W,"height":H,"tiles":[{"origin":[x,y],"rgba":"tile.raw","width":w,"height":h,
//            "lines":[{"text":"…","confidence":0.9,"box":[x,y,w,h]}]}]}  (box: pixel trong tile)

final class Buffer {
    let pointer: UnsafeMutableRawPointer
    init(_ data: Data) {
        pointer = UnsafeMutableRawPointer.allocate(byteCount: max(1, data.count), alignment: 8)
        data.copyBytes(to: pointer.assumingMemoryBound(to: UInt8.self), count: data.count)
    }
    deinit { pointer.deallocate() }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(2)
}

func output(_ value: Any) {
    let data = try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
}

let args = CommandLine.arguments
guard args.count >= 3 else { fail("usage: native-harness plan <w> <h> | analyze <job.json>") }

switch args[1] {
case "plan":
    guard args.count == 4, let width = Int(args[2]), let height = Int(args[3]) else { fail("plan <w> <h>") }
    let size = PageAnalyzer.preparedSize(width: width, height: height)
    let tiles = PageAnalyzer.tileRects(width: size.width, height: size.height).map {
        [Int($0.minX), Int($0.minY), Int($0.width), Int($0.height)]
    }
    output(["width": size.width, "height": size.height, "tiles": tiles])

case "analyze":
    let jobURL = URL(fileURLWithPath: args[2])
    guard let job = try JSONSerialization.jsonObject(with: Data(contentsOf: jobURL)) as? [String: Any],
          let width = job["width"] as? Int, let height = job["height"] as? Int,
          let tiles = job["tiles"] as? [[String: Any]] else { fail("job.json sai định dạng") }
    var collector = PageAnalyzer.Collector(fullWidth: CGFloat(width), fullHeight: CGFloat(height))
    for tile in tiles {
        guard let origin = tile["origin"] as? [Double], let raw = tile["rgba"] as? String,
              let tileW = tile["width"] as? Int, let tileH = tile["height"] as? Int else { fail("tile sai định dạng") }
        let found: [PageAnalyzer.RecognizedLine] = (tile["lines"] as? [[String: Any]] ?? []).compactMap { line in
            guard let text = line["text"] as? String, let box = line["box"] as? [Double], box.count == 4 else { return nil }
            return PageAnalyzer.RecognizedLine(
                text: text,
                confidence: Float(line["confidence"] as? Double ?? 1),
                box: CGRect(x: box[0], y: box[1], width: box[2], height: box[3])
            )
        }
        guard !found.isEmpty else { continue }
        let rawURL = URL(fileURLWithPath: raw, relativeTo: jobURL.deletingLastPathComponent())
        let buffer = Buffer(try Data(contentsOf: rawURL))
        let grid = PixelGrid(width: tileW, height: tileH, bytesPerRow: tileW * 4, data: UnsafeRawPointer(buffer.pointer), owner: buffer)
        collector.add(origin: CGPoint(x: origin[0], y: origin[1]), grid: grid, found: found)
    }
    output(collector.result())

default:
    fail("lệnh không hợp lệ: \(args[1])")
}
