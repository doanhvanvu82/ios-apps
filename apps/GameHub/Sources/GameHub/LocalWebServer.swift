import Foundation
import Network

/// HTTP server tĩnh tối giản chạy trên localhost để phục vụ file game cho WebView.
/// WKWebView chặn file:// cross-origin nên phải load game qua http://127.0.0.1:PORT/
///
/// File được **stream theo chunk** (không load cả file vào RAM) để chịu được
/// các file lớn (archive .rpa của Ren'Py web có thể hàng trăm MB).
///
/// ⚠️ Header được dựng bằng `Data` + `append("...\r\n")` — KHÔNG dùng multiline
/// string Swift. Lý do: interpolation `\(x)` trong multiline string chèn "\n"
/// sau biến, và nếu biến rỗng hoặc đã kết thúc bằng "\r\n" sẽ sinh ra dòng
/// trống giữa header → HTTP parser coi đó là hết header → phần còn lại
/// ("Connection: close" và cả COOP/COEP) dính vào đầu body → file JS load về
/// bắt đầu bằng "Cross-Origin-Opener-Policy:..." → SyntaxError 'Unexpected
/// token ':' (đã gặp thật trên iOS, mọi file JS của game Tyrano đều chết).
final class LocalWebServer {
    private var listener: NWListener?
    private(set) var port: UInt16 = 0

    /// Thống kê tải cho màn chơi: biết game còn đang nạp dữ liệu hay đã đứng.
    struct Activity {
        var requests = 0
        var bytes = 0
        var lastPath = ""
        var lastAt: Date?
    }
    private let activityLock = NSLock()
    private var currentActivity = Activity()
    var activity: Activity { activityLock.withLock { currentActivity } }

    private func noteRequest(_ path: String) {
        activityLock.withLock {
            currentActivity.requests += 1
            currentActivity.lastPath = path
            currentActivity.lastAt = Date()
        }
    }

    private func noteBytes(_ count: Int) {
        activityLock.withLock {
            currentActivity.bytes += count
            currentActivity.lastAt = Date()
        }
    }
    private let queue = DispatchQueue(label: "vn.vudv.gamehub.webserver")

    private let chunkSize = 256 * 1024

    private let mimeTypes: [String: String] = [
        "html": "text/html; charset=utf-8",
        "htm": "text/html; charset=utf-8",
        "js": "application/javascript; charset=utf-8",
        "mjs": "application/javascript; charset=utf-8",
        "css": "text/css; charset=utf-8",
        "json": "application/json; charset=utf-8",
        "png": "image/png",
        "jpg": "image/jpeg",
        "jpeg": "image/jpeg",
        "gif": "image/gif",
        "webp": "image/webp",
        "svg": "image/svg+xml",
        "ico": "image/x-icon",
        "ogg": "audio/ogg",
        "oga": "audio/ogg",
        "opus": "audio/ogg",
        "mp3": "audio/mpeg",
        "m4a": "audio/mp4",
        "aac": "audio/aac",
        "wav": "audio/wav",
        "webm": "video/webm",
        "mp4": "video/mp4",
        "m4v": "video/mp4",
        "ogv": "video/ogg",
        "ttf": "font/ttf",
        "otf": "font/otf",
        "woff": "font/woff",
        "woff2": "font/woff2",
        "wasm": "application/wasm",
        "swf": "application/x-shockwave-flash",   // Adobe Flash (runtime Ruffle)
        "map": "application/json",
        "data": "application/octet-stream",   // renpy.data (Ren'Py web runtime)
        "txt": "text/plain; charset=utf-8",
        "xml": "application/xml",
        "rpy": "text/plain; charset=utf-8",
        "rpa": "application/octet-stream",
        "zip": "application/zip",
        "atlas": "text/plain; charset=utf-8",
        "fnt": "application/octet-stream",
    ]

    /// Gốc tài nguyên: thư mục thường hoặc archive `.asar`.
    let root: GameResourceRoot

    init(root: GameResourceRoot) {
        self.root = root
    }

    /// Start server, trả về port đã gán (chờ tới khi listener ready).
    ///
    /// - Parameter preferredPort: port cố định theo game. localStorage/IndexedDB
    ///   tách theo origin `127.0.0.1:<port>` — port ngẫu nhiên mỗi lần mở làm
    ///   game web mất save. Port bận thì rơi về port ngẫu nhiên.
    func start(preferredPort: UInt16? = nil) throws {
        if let preferred = preferredPort, let nwPort = NWEndpoint.Port(rawValue: preferred),
           listen(on: nwPort) {
            return
        }
        if preferredPort != nil {
            AppLog.warn("Port \(preferredPort!) bận — dùng port ngẫu nhiên (save web của lần này tách riêng)")
        }
        if !listen(on: .any) {
            throw ServerError.couldNotBind
        }
    }

    private func listen(on nwPort: NWEndpoint.Port) -> Bool {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        guard let listener = try? NWListener(using: params, on: nwPort) else { return false }
        self.listener = listener
        let ready = DispatchSemaphore(value: 0)

        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.queue.async {
                    self?.port = listener.port?.rawValue ?? 0
                    ready.signal()
                }
            case .failed:
                ready.signal()
            default:
                break
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        listener.start(queue: queue)

        // Chờ listener sẵn sàng (tối đa 3s)
        _ = ready.wait(timeout: .now() + 3)
        if port == 0 {
            listener.cancel()
            self.listener = nil
            return false
        }
        return true
    }

    /// `X.mp4` ↔ `X.webm`.
    static func alternateVideoPath(_ path: String) -> String? {
        let ns = path as NSString
        switch ns.pathExtension.lowercased() {
        case "mp4": return ns.deletingPathExtension + ".webm"
        case "webm": return ns.deletingPathExtension + ".mp4"
        default: return nil
        }
    }

    /// Port cố định theo tên game (FNV-1a; `hashValue` của Swift đổi mỗi lần chạy).
    static func stablePort(for key: String) -> UInt16 {
        var hash: UInt32 = 2_166_136_261
        for byte in key.utf8 {
            hash = (hash ^ UInt32(byte)) &* 16_777_619
        }
        return UInt16(20_000 + hash % 30_000)
    }

    enum ServerError: LocalizedError {
        case couldNotBind
        var errorDescription: String? { "Không thể khởi động HTTP server nội bộ." }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Connection handling

    private func handleConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { state in
            if case .failed = state { connection.cancel() }
        }
        connection.start(queue: queue)
        readRequest(connection)
    }

    private func readRequest(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.route(data: data, connection: connection)
                // Sau khi trả response xong sẽ cancel connection — không đọc tiếp.
                return
            }
            if error != nil || isComplete {
                connection.cancel()
                return
            }
            self.readRequest(connection)
        }
    }

    private func route(data: Data, connection: NWConnection) {
        guard let requestText = String(data: data, encoding: .utf8),
              let requestLine = requestText.components(separatedBy: "\r\n").first else {
            respondText(connection: connection, status: "400 Bad Request", body: "Bad Request")
            return
        }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2, let rawPath = parts[1].removingPercentEncoding else {
            respondText(connection: connection, status: "400 Bad Request", body: "Bad Request")
            return
        }

        let method = parts[0].uppercased()

        // Bỏ query string
        let path = rawPath.split(separator: "?", omittingEmptySubsequences: false).first.map(String.init) ?? rawPath
        let queryItems = rawPath.split(separator: "?", maxSplits: 1).dropFirst().first?.split(separator: "&") ?? []

        // WebDAV PROPFIND — KiriKiri runtime dùng để quét thư mục game gốc
        // (?webdavUrl=...), đọc file lazy qua HTTP Range → không cần nén game.zip.
        if method == "PROPFIND" {
            respondPropfind(connection: connection, path: path)
            return
        }

        // Chống path traversal
        guard !path.contains("..") else {
            respondText(connection: connection, status: "403 Forbidden", body: "Forbidden")
            return
        }

        var cleanPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        if cleanPath.isEmpty || path.hasSuffix("/") { cleanPath += "index.html" }

        // HTML sinh động (runtime Godot/KiriKiri/Ruffle cần config riêng theo game).
        // Phải kèm COOP/COEP: trang chính thiếu chúng thì không cross-origin
        // isolated → mất SharedArrayBuffer → runtime đa luồng (Godot 4,
        // KiriKiri) không tạo được thread ("Internal error" / báo thiếu SAB).
        if cleanPath == "index.html", let html = root.customIndexHTML {
            respond(connection: connection, status: "200 OK", body: Data(html.utf8),
                    contentType: "text/html; charset=utf-8",
                    extraHeaders: Self.crossOriginHeaders)
            return
        }

        var source = root.source(for: cleanPath)
        var contentEncoding: String?

        if source == nil {
            // Unity WebGL (Unity 6) chỉ xuất bản nén sẵn: `<name>.data.br`,
            // `<name>.wasm.br`, `<name>.framework.js.br`… Loader yêu cầu tên
            // file KHÔNG có đuôi nén, nên server phải tự tìm bản nén và trả
            // kèm header `Content-Encoding` để trình duyệt giải nén.
            if let brSource = root.source(for: cleanPath + ".br") {
                source = brSource
                contentEncoding = "br"
            } else if let gzSource = root.source(for: cleanPath + ".gz") {
                source = gzSource
                contentEncoding = "gzip"
            } else if let alt = Self.alternateVideoPath(cleanPath),
                      let altSource = root.source(for: alt) {
                // RPG Maker MV chọn `.mp4` khi nhận là thiết bị di động, nhưng
                // nhiều game chỉ phát hành `.webm` (và ngược lại).
                source = altSource
                cleanPath = alt
            }
        }

        guard let resolved = source else {
            respondText(connection: connection, status: "404 Not Found", body: "Not found: \(path)")
            return
        }
        noteRequest(cleanPath)

        // Hỗ trợ Range request (audio/video seek trong game)
        let rangeHeader = requestText
            .components(separatedBy: "\r\n")
            .first { $0.lowercased().hasPrefix("range:") }?
            .split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)[1]
            .trimmingCharacters(in: .whitespaces)

        let fileSize = resolved.fileSize
        let ext = (cleanPath as NSString).pathExtension.lowercased()
        let mime = mimeTypes[ext] ?? "application/octet-stream"

        // ?gh_b64=1: trả đoạn Range dạng base64. Runtime Godot 4 đọc pck bằng
        // XHR đồng bộ (FS của Emscripten đồng bộ), mà XHR đồng bộ chỉ trả
        // text; dữ liệu nhị phân qua text bị hỏng khi đoạn bắt đầu bằng byte
        // giống BOM (trình duyệt giải mã theo BOM). Base64 là ASCII → an toàn.
        if let rangeHeader, queryItems.contains("gh_b64=1"),
           let (start, end) = parseByteRange(rangeHeader, fileSize: fileSize) {
            guard let data = resolved.read(offset: start, count: end - start + 1) else {
                respondText(connection: connection, status: "500 Internal Server Error", body: "Read error")
                return
            }
            respond(connection: connection, status: "200 OK", body: data.base64EncodedData(),
                    contentType: "text/plain; charset=us-ascii", extraHeaders: Self.crossOriginHeaders)
        } else if let rangeHeader, parseByteRange(rangeHeader, fileSize: fileSize) != nil {
            serveRange(
                connection: connection,
                source: resolved,
                mime: mime,
                fileSize: fileSize,
                rangeHeader: rangeHeader,
                contentEncoding: contentEncoding
            )
        } else {
            serveFullFile(
                connection: connection,
                source: resolved,
                mime: mime,
                fileSize: fileSize,
                contentEncoding: contentEncoding
            )
        }
    }

    // MARK: - Header builder (an toàn, không dùng multiline string)

    /// Dựng block header HTTP từ danh sách (name, value).
    /// Mỗi header → "Name: value\r\n". Lời gọi thêm "\r\n" cuối để kết thúc.
    private static func makeHeaders(status: String, headers: [(String, String)]) -> Data {
        var out = Data("HTTP/1.1 \(status)\r\n".utf8)
        for (name, value) in headers {
            out.append(Data("\(name): \(value)\r\n".utf8))
        }
        out.append(Data("\r\n".utf8))
        return out
    }

    /// Header bật Cross-Origin Isolation (SharedArrayBuffer cho Godot/KiriKiri WASM).
    private static let crossOriginHeaders: [(String, String)] = [
        ("Cross-Origin-Opener-Policy", "same-origin"),
        ("Cross-Origin-Embedder-Policy", "require-corp"),
        ("Cross-Origin-Resource-Policy", "same-origin"),
        ("Access-Control-Expose-Headers", "Content-Length, Content-Range, Accept-Ranges, ETag"),
    ]

    private func serveFullFile(connection: NWConnection, source: GameFileSource, mime: String, fileSize: Int, contentEncoding: String? = nil) {
        var headers: [(String, String)] = [
            ("Content-Type", mime),
            ("Content-Length", String(fileSize)),
            ("Accept-Ranges", "bytes"),
            ("Access-Control-Allow-Origin", "*"),
        ]
        if let contentEncoding {
            headers.append(("Content-Encoding", contentEncoding))
        }
        // Không có header cache → WKWebView tự đoán và giữ CSS/JS cũ sau khi chép file game đã sửa sang máy.
        // Chỉ file văn bản (nhỏ); dữ liệu lớn (.data/.wasm/.pck/media) vẫn cache được.
        if mime.hasPrefix("text/") || mime.contains("javascript") || mime.contains("json") {
            headers.append(("Cache-Control", "no-store"))
        }
        headers.append(contentsOf: Self.crossOriginHeaders)
        headers.append(("Connection", "close"))

        let prefix = Self.makeHeaders(status: "200 OK", headers: headers)
        streamFile(connection: connection, source: source, offset: 0, length: fileSize, prefixData: prefix)
    }

    private func serveRange(connection: NWConnection, source: GameFileSource, mime: String, fileSize: Int, rangeHeader: String, contentEncoding: String? = nil) {
        guard let (start, end) = parseByteRange(rangeHeader, fileSize: fileSize) else {
            respondText(connection: connection, status: "416 Range Not Satisfiable", body: "Invalid range")
            return
        }
        let length = end - start + 1
        var headers: [(String, String)] = [
            ("Content-Type", mime),
            ("Content-Length", String(length)),
            ("Content-Range", "bytes \(start)-\(end)/\(fileSize)"),
            ("Accept-Ranges", "bytes"),
            ("Access-Control-Allow-Origin", "*"),
        ]
        if let contentEncoding {
            headers.append(("Content-Encoding", contentEncoding))
        }
        headers.append(contentsOf: Self.crossOriginHeaders)
        headers.append(("Connection", "close"))

        let prefix = Self.makeHeaders(status: "206 Partial Content", headers: headers)
        streamFile(connection: connection, source: source, offset: start, length: length, prefixData: prefix)
    }

    private func respondText(connection: NWConnection, status: String, body: String,
                             contentType: String = "text/plain; charset=utf-8") {
        respond(connection: connection, status: status, body: Data(body.utf8), contentType: contentType)
    }

    /// Gửi response text/JSON — dựng header bằng Data.append (an toàn).
    private func respond(connection: NWConnection, status: String, body: Data,
                         contentType: String = "text/plain; charset=utf-8",
                         extraHeaders: [(String, String)] = []) {
        var headers: [(String, String)] = [
            ("Content-Type", contentType),
            ("Content-Length", String(body.count)),
            ("Access-Control-Allow-Origin", "*"),
        ]
        headers.append(contentsOf: extraHeaders)
        headers.append(("Connection", "close"))

        var response = Self.makeHeaders(status: status, headers: headers)
        response.append(body)
        noteBytes(body.count)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - PROPFIND (WebDAV)

    /// Trả lời PROPFIND (WebDAV level 1): liệt kê thư mục game thành XML
    /// `multistatus`. KiriKiri runtime dùng cái này để quét toàn bộ file
    /// `.xp3` của game gốc rồi đọc lazy qua HTTP Range.
    ///
    /// - Parameter path: đường dẫn yêu cầu (luôn là thư mục, kết thúc bằng "/").
    private func respondPropfind(connection: NWConnection, path: String) {
        // Chuẩn hoá: bỏ "/" đầu, bỏ "/" cuối.
        var rel = path.hasPrefix("/") ? String(path.dropFirst()) : path
        while rel.hasSuffix("/") { rel.removeLast() }
        rel = rel.isEmpty ? "" : rel

        // Thư mục tương ứng trên đĩa.
        let dirURL: URL
        if rel.isEmpty {
            dirURL = root.baseDirectory
        } else {
            // Chống path traversal.
            guard !rel.contains("..") else {
                respondText(connection: connection, status: "403 Forbidden", body: "Forbidden")
                return
            }
            dirURL = root.baseDirectory.appendingPathComponent(rel, isDirectory: true)
        }

        let fm = FileManager.default
        guard let children = try? fm.contentsOfDirectory(
            at: dirURL,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey]
        ) else {
            respondText(connection: connection, status: "404 Not Found", body: "Not found: \(path)")
            return
        }

        // URL gốc để tạo href tương đối.
        let baseURL = "http://127.0.0.1:\(port)/"

        var body = """
        <?xml version="1.0" encoding="utf-8"?>
        <D:multistatus xmlns:D="DAV:">

        """
        // Thư mục hiện tại.
        body += webDavResponse(href: baseURL + (rel.isEmpty ? "" : rel + "/"),
                               isDir: true, size: 0)
        let virtualNames = rel.isEmpty ? root.virtualFiles.keys.filter { !$0.contains("/") } : []
        for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            where !virtualNames.contains(child.lastPathComponent) {
            var isDir: ObjCBool = false
            fm.fileExists(atPath: child.path, isDirectory: &isDir)
            let size = (try? child.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let childRel = rel.isEmpty ? child.lastPathComponent : rel + "/" + child.lastPathComponent
            let href = baseURL + childRel + (isDir.boolValue ? "/" : "")
            body += webDavResponse(href: href, isDir: isDir.boolValue, size: size)
        }
        for name in virtualNames.sorted() {
            body += webDavResponse(href: baseURL + name, isDir: false, size: root.virtualFiles[name]?.count ?? 0)
        }
        body += "</D:multistatus>"

        respond(connection: connection, status: "207 Multi-Status",
                body: Data(body.utf8), contentType: "application/xml; charset=utf-8")
    }

    /// Một `<D:response>` trong multistatus.
    private func webDavResponse(href: String, isDir: Bool, size: Int) -> String {
        let resourceType = isDir ? "<D:resourcetype><D:collection/></D:resourcetype>" : "<D:resourcetype/>"
        let contentLength = isDir ? "" : "<D:getcontentlength>\(size)</D:getcontentlength>"
        return """
        <D:response>
          <D:href>\(href)</D:href>
          <D:propstat>
            <D:prop>
              \(resourceType)
              \(contentLength)
            </D:prop>
            <D:status>HTTP/1.1 200 OK</D:status>
          </D:propstat>
        </D:response>
        """
    }

    // MARK: - File streaming

    private func streamFile(connection: NWConnection, source: GameFileSource, offset: Int, length: Int, prefixData: Data) {
        FileStreamer(source: source, connection: connection, offset: offset, length: length, prefixData: prefixData,
                     onChunk: { [weak self] in self?.noteBytes($0) }).start()
    }

    /// Parse "bytes=0-1023" → (0, 1023). Trả nil nếu sai cú pháp.
    private func parseByteRange(_ header: String, fileSize: Int) -> (Int, Int)? {
        guard fileSize > 0 else { return nil }
        let trimmed = header.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("bytes=") else { return nil }
        let spec = trimmed.dropFirst("bytes=".count)
        let parts = spec.split(separator: "-")
        var start = 0
        var end = fileSize - 1
        if parts.count == 2 {
            guard let s = Int(parts[0]), let e = Int(parts[1]) else { return nil }
            start = s
            end = min(e, fileSize - 1)
        } else if parts.count == 1, spec.hasSuffix("-") {
            // bytes=N- : từ N tới cuối
            guard let s = Int(parts[0]) else { return nil }
            start = s
        } else {
            return nil
        }
        guard start <= end, start < fileSize else { return nil }
        return (start, end)
    }
}

// MARK: - File streaming helper

/// Gửi file theo chunk (không nạp cả file vào RAM) cho WebView.
///
/// State nằm trong class thay vì closure capture biến `var`, để tuân thủ
/// Swift 6 strict concurrency (mọi callback của `NWConnection.send` chạy
/// đồng thời).
///
/// Vòng đời: đối tượng tự giữ mình (`keepAlive`) trong lúc đang stream, và
/// thả ra khi kết thúc — nếu không, instance sẽ bị deallocate ngay lập tức
/// sau `start()` và chuỗi callback sẽ dừng ở chunk đầu tiên.
private final class FileStreamer: @unchecked Sendable {
    private let source: GameFileSource
    private let connection: NWConnection
    /// Byte bắt đầu trong file (≠ 0 với request Range).
    private let offset: Int
    private let length: Int
    private let chunkSize: Int
    private var sentTotal: Int = 0
    private var pendingPrefix: Data
    private var keepAlive: FileStreamer?
    private let onChunk: (Int) -> Void

    init(source: GameFileSource, connection: NWConnection, offset: Int, length: Int, prefixData: Data,
         chunkSize: Int = 256 * 1024, onChunk: @escaping (Int) -> Void) {
        self.onChunk = onChunk
        self.source = source
        self.connection = connection
        self.offset = offset
        self.length = length
        self.pendingPrefix = prefixData
        self.chunkSize = chunkSize
    }

    func start() {
        keepAlive = self
        sendNext()
    }

    private func sendNext() {
        if !pendingPrefix.isEmpty {
            let chunk = pendingPrefix
            pendingPrefix = Data()
            connection.send(content: chunk, completion: .contentProcessed { [self] _ in
                sendNext()
            })
            return
        }

        guard sentTotal < length else {
            finish()
            return
        }

        let toRead = min(chunkSize, length - sentTotal)
        guard let chunk = source.read(offset: offset + sentTotal, count: toRead), !chunk.isEmpty else {
            finish()
            return
        }
        sentTotal += chunk.count
        onChunk(chunk.count)
        connection.send(content: chunk, completion: .contentProcessed { [self] _ in
            sendNext()
        })
    }

    private func finish() {
        connection.cancel()
        keepAlive = nil
    }
}
