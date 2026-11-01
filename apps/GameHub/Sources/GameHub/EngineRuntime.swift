import Foundation

/// Runtime đi kèm trong app cho các engine cần runtime riêng.
///
/// Mục tiêu: **không cần build lại game trên máy tính**. Người dùng chỉ cần
/// copy thư mục game gốc (Windows) vào app, app phục vụ file gốc kèm runtime
/// tương ứng → game chạy ngay trong WebView.
///
/// | Engine | Runtime | Cách nạp game |
/// |---|---|---|
/// | Godot 4.0–4.2 | `godot.js` + `index.wasm` (WebGL) | file `.pck` gốc (`mainPack`) |
/// | Godot 4.3+ | `index.js` + `index.wasm` (template 4.5.1) | file `.pck` gốc, hoặc pck nhúng trong `.exe` |
/// | Godot 3.x | `godot.js` + `index.wasm` (WebAssembly) | file `.pck` gốc |
/// | KiriKiri2 | `kirikiroid2-web` (WASM) | WebDAV `?webdavUrl=/` quét thư mục game |
/// | Flash | Ruffle (WASM) | file `.swf` gốc |
/// | Ren'Py 8.3 / 8.5 (PC) | runtime web Ren'Py 8.3.7 / 8.5.2 | `game.zip` dựng tại chỗ + tệp lớn lazy (`RenPyNative`) |
enum EngineRuntime {
    case godot4
    case godot45
    case godot3
    case kiriki
    case ruffle
    case renpy
    case renpy85

    /// Thư mục chứa runtime trong bundle của app.
    var directoryName: String {
        switch self {
        case .godot4: return "godot4"
        case .godot45: return "godot45"
        case .godot3: return "godot3"
        case .kiriki: return "kiriki"
        case .ruffle: return "ruffle"
        case .renpy: return "renpy"
        case .renpy85: return "renpy85"
        }
    }

    /// Thư mục runtime trong bundle.
    static func directory(for runtime: EngineRuntime) -> URL? {
        guard let base = Bundle.module.resourceURL?
            .appendingPathComponent("Runtime", isDirectory: true) else { return nil }
        let dir = base.appendingPathComponent(runtime.directoryName, isDirectory: true)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir),
              isDir.boolValue else { return nil }
        return dir
    }

    /// Kích thước file trong runtime — dùng cho thanh tiến trình Godot.
    static func fileSize(_ name: String, in runtime: EngineRuntime) -> Int64 {
        guard let dir = directory(for: runtime) else { return 0 }
        let url = dir.appendingPathComponent(name)
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.size] as? NSNumber)?.int64Value ?? 0
    }

    /// Sinh `index.html` cho runtime, thay các placeholder `$GODOT_*`.
    ///
    /// - Parameters:
    ///   - packSize: kích thước file `.pck` của game (dùng cho progress bar).
    ///   - packName: tên file `.pck` mà runtime sẽ nạp.
    ///   - title: tiêu đề hiển thị.
    ///   - swfName: file `.swf` chính của game Flash.
    static func indexHTML(for runtime: EngineRuntime,
                          packSize: Int64,
                          packName: String = "index.pck",
                          title: String = "Game",
                          swfName: String = "game.swf") -> String? {
        switch runtime {
        case .godot4, .godot45, .godot3:
            return godotIndexHTML(runtime: runtime, packSize: packSize,
                                  packName: packName, title: title)
        case .kiriki:
            // KiriKiri dùng TRANG GỐC của kirikiroid2-web (index.html trong
            // thư mục runtime) — nó có sẵn loader UI + progress + xử lý
            // ?webdavUrl=. Trước đây sinh HTML rỗng tự chế → game đen.
            let dir = directory(for: .kiriki)
            let url = dir?.appendingPathComponent("index.html")
            if let s = url.flatMap({ try? String(contentsOf: $0, encoding: .utf8) }) {
                return s
            }
            AppLog.error("Không đọc được index.html của kiriki runtime")
            return nil
        case .ruffle:
            return ruffleIndexHTML(title: title, swfName: swfName)
        case .renpy, .renpy85:
            // RenPyNative tự đọc index.html của runtime (cần dựng game.zip trước).
            return nil
        }
    }

    // MARK: - Godot

    private static func godotIndexHTML(runtime: EngineRuntime,
                                      packSize: Int64,
                                      packName: String,
                                      title: String) -> String? {
        guard let dir = directory(for: runtime) else { return nil }
        let templateURL = dir.appendingPathComponent("godot.html")
        guard let template = try? String(contentsOf: templateURL, encoding: .utf8) else { return nil }

        let wasmSize = fileSize("index.wasm", in: runtime)

        // ⚠️ Godot dùng `executable` để suy ra cả tên file wasm LẪN tên pck:
        //   - `this.init(exe)` → tải `<exe>.wasm`
        //   - `mainPack || `${exe}.pck`` → nạp pack
        //
        // Runtime đi kèm app có file wasm tên `index.wasm`, còn file `.pck` của
        // game thì tên tuỳ ý (vd "Buchicome.pck"). Trước đây app đặt
        // `executable` = tên pack bỏ đuôi → Godot đi tìm `<tên>.wasm` không
        // tồn tại → game kẹt ở màn loading vĩnh viễn (progress bar đứng).
        //
        // Cách đúng: `executable` = "index" (khớp index.wasm), `mainPack` =
        // tên file pck thật của game.
        let executable = "index"

        let config = """
        {"args":[],"canvasResizePolicy":2,"executable":"\(executable)",\
        "mainPack":"\(packName)",\
        "experimentalVK":false,"fileSizes":{"\(packName)":\(packSize),\
        "\(executable).wasm":\(wasmSize)},"focusCanvas":true,"gdextensionLibs":[]}
        """

        return template
            .replacingOccurrences(of: "$GODOT_PROJECT_NAME", with: title)
            .replacingOccurrences(of: "$GODOT_HEAD_INCLUDE", with: "")
            // 4.5: luồng pthread nạp lại chính script chính qua `${executable}.js`
            // → script phải tên `index.js` (4.1 dùng `index.worker.js` riêng).
            .replacingOccurrences(of: "$GODOT_URL", with: runtime == .godot45 ? "index.js" : "godot.js")
            .replacingOccurrences(of: "$GODOT_CONFIG", with: config)
    }

    // MARK: - Ruffle

    private static func ruffleIndexHTML(title: String, swfName: String) -> String? {
        // swfName cần URL-encode (tên file game có dấu cách/ký tự đặc biệt).
        let encoded = swfName.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed) ?? swfName

        return """
        <!DOCTYPE html>
        <html lang="vi">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, user-scalable=no, viewport-fit=cover">
        <title>\(title)</title>
        <style>
          html, body { margin:0; padding:0; height:100%; background:#000; overflow:hidden; }
          #container { display:flex; align-items:center; justify-content:center; height:100%; }
          #flash, ruffle-player { width:100% !important; height:100% !important; }
          /* Chạm đúp trên iPhone = chọn văn bản (bôi đen) → game không dùng được bằng cảm ứng. */
          * { -webkit-user-select:none; user-select:none; -webkit-touch-callout:none; -webkit-tap-highlight-color:transparent; }
        </style>
        </head>
        <body>
        <div id="container">
          <embed id="flash" type="application/x-shockwave-flash" src="\(encoded)" width="100%" height="100%">
        </div>
        <script>
          // Nhiều SWF tự đặt noScale/exactFit → khung game lớn hơn màn điện thoại ngang, bị cắt mất đáy.
          window.RufflePlayer = { config: { scale: "showAll", forceScale: true, letterbox: "on" } };
          document.addEventListener("selectstart", function(e) { e.preventDefault(); });
        </script>
        <script src="ruffle.js"></script>
        </body>
        </html>
        """
    }
}
