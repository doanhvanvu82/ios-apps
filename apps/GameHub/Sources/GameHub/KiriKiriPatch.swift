import Foundation

/// Bổ sung plugin mà runtime KiriKiri web không có, bằng `patch.xp3` ảo.
///
/// Runtime (kirikiroid2-web) giả lập sẵn ~38 plugin nhưng không có `json.dll`.
/// Game KAG gọi `Plugins.link` trong `system/PluginLoader.tjs`; KAG nạp
/// `patch.xp3`, `patch2.xp3`… cuối cùng nên file trong đó đè file cùng tên.
/// Patch chứa `PluginLoader.tjs` = polyfill (TJS) + chạy lại bản gốc trong
/// `data.xp3`.
///
/// shortcut: chỉ hỗ trợ game có `system/PluginLoader.tjs` trong `data.xp3`
/// (kiểu KAG của courreges software) và bộ lọc giải mã XOR theo hash; game khác
/// cần thêm cách móc khác khi gặp.
enum KiriKiriPatch {
    /// File ảo cần thêm vào thư mục game (tên → nội dung); rỗng nếu không cần.
    static func virtualFiles(gameDir: URL, runtimeDir: URL?) -> [String: Data] {
        let fm = FileManager.default
        let pluginDir = gameDir.appendingPathComponent("plugin")
        let plugins = (try? fm.contentsOfDirectory(atPath: pluginDir.path)) ?? []
        guard plugins.contains(where: { $0.lowercased() == "json.dll" }),
              let runtimeDir,
              let polyfill = try? String(contentsOf: runtimeDir.appendingPathComponent("json_polyfill.tjs"),
                                         encoding: .utf8)
        else { return [:] }

        let loader = polyfill + """

        var __ghOriginalLoader = System.exePath + "data.xp3>system/PluginLoader.tjs";
        if (Storages.isExistentStorage(__ghOriginalLoader)) Scripts.execStorage(__ghOriginalLoader);

        """
        let filter = (try? String(contentsOf: gameDir.appendingPathComponent("xp3filter.tjs"), encoding: .utf8)) ?? ""
        let xorByHash = filter.replacingOccurrences(of: " ", with: "").contains("b.xor(0,l,h)")

        var name = "patch.xp3"
        var n = 2
        while fm.fileExists(atPath: gameDir.appendingPathComponent(name).path) {
            name = "patch\(n).xp3"
            n += 1
        }
        AppLog.info("KiriKiri: thêm \(name) ảo (giả lập json.dll\(xorByHash ? ", XOR theo hash" : ""))")
        return [name: archive(files: [("PluginLoader.tjs", Data(loader.utf8))], xorByHash: xorByHash)]
    }

    /// XP3 không nén. `xorByHash`: lưu nội dung đã XOR với byte thấp của
    /// adler32 — bộ lọc `b.xor(0,l,h)` của game XOR lại khi đọc ra.
    static func archive(files: [(name: String, content: Data)], xorByHash: Bool) -> Data {
        let headerSize = 11 + 8
        var body = Data()
        var index = Data()
        for file in files {
            let adler = adler32(file.content)
            let key = UInt8(adler & 0xFF)
            let stored = xorByHash ? Data(file.content.map { $0 ^ key }) : file.content
            let start = UInt64(headerSize + body.count)
            let nameUnits = Array(file.name.utf16)

            var info = Data()
            info.appendLE(UInt32(0))
            info.appendLE(UInt64(file.content.count))
            info.appendLE(UInt64(stored.count))
            info.appendLE(UInt16(nameUnits.count))
            nameUnits.forEach { info.appendLE($0) }

            var segm = Data()
            segm.appendLE(UInt32(0))
            segm.appendLE(start)
            segm.appendLE(UInt64(file.content.count))
            segm.appendLE(UInt64(stored.count))

            var adlr = Data()
            adlr.appendLE(adler)

            var chunk = Data()
            for (tag, payload) in [("info", info), ("segm", segm), ("adlr", adlr)] {
                chunk.append(Data(tag.utf8))
                chunk.appendLE(UInt64(payload.count))
                chunk.append(payload)
            }
            index.append(Data("File".utf8))
            index.appendLE(UInt64(chunk.count))
            index.append(chunk)
            body.append(stored)
        }

        var out = Data([0x58, 0x50, 0x33, 0x0D, 0x0A, 0x20, 0x0A, 0x1A, 0x8B, 0x67, 0x01])
        out.appendLE(UInt64(headerSize + body.count))
        out.append(body)
        out.append(0)  // index không nén
        out.appendLE(UInt64(index.count))
        out.append(index)
        return out
    }

    static func adler32(_ data: Data) -> UInt32 {
        var a: UInt32 = 1, b: UInt32 = 0
        for byte in data {
            a = (a + UInt32(byte)) % 65521
            b = (b + a) % 65521
        }
        return (b << 16) | a
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
