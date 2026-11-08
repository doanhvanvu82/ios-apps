import Foundation

/// Client REST Google Drive v3 — không dependency ngoài (URLSession thuần).
/// Mỗi instance gắn với 1 account (token lấy qua TokenProviding theo account).
final class DriveClient {
    static let apiBase = "https://www.googleapis.com/drive/v3"
    static let uploadBase = "https://www.googleapis.com/upload/drive/v3"
    static let rootFolderID = "root"
    /// Kích thước chunk khi upload resumable (8 MB — bội số 256 KB như Google yêu cầu).
    static let chunkSize = 8 * 1024 * 1024

    private let account: DriveAccount
    private let tokens: TokenProviding
    private let session: URLSession

    /// URLSession dùng chung (không delegate, không cache mặc định).
    private static let sharedSession: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.timeoutIntervalForRequest = 120
        cfg.timeoutIntervalForResource = 60 * 30   // upload/download file lớn
        cfg.httpShouldSetCookies = false
        cfg.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: cfg)
    }()

    init(account: DriveAccount, tokens: TokenProviding) {
        self.account = account
        self.tokens = tokens
        self.session = Self.sharedSession
    }

    // MARK: - Core request

    /// GET/POST/PATCH/DELETE API thường (JSON body hoặc data thô).
    private func request(
        _ method: String,
        _ path: String,
        query: [URLQueryItem] = [],
        jsonBody: [String: Any]? = nil,
        uploadBody: Data? = nil,
        contentType: String? = nil
    ) async throws -> Data {
        guard var comps = URLComponents(string: path.hasPrefix("http") ? path : Self.apiBase + path) else {
            throw DriveError.http(status: 0, reason: "badURL", message: path)
        }
        if !query.isEmpty {
            comps.queryItems = query
        }
        guard let url = comps.url else {
            throw DriveError.http(status: 0, reason: "badURL", message: path)
        }

        // 1 lần thử + 1 lần retry sau khi refresh token khi gặp 401.
        for attempt in 0..<2 {
            let token = try await tokens.validAccessToken(for: account)
            var req = URLRequest(url: url)
            req.httpMethod = method
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            if let jsonBody {
                req.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
                req.httpBody = try JSONSerialization.data(withJSONObject: jsonBody)
            } else if let uploadBody {
                req.setValue(contentType ?? "application/octet-stream", forHTTPHeaderField: "Content-Type")
                req.httpBody = uploadBody
            }

            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse else {
                throw DriveError.http(status: 0, reason: "noResponse", message: nil)
            }
            if http.statusCode < 300 {
                return data
            }
            let err = DriveError.parse(status: http.statusCode, data: data)
            if http.statusCode == 401 && attempt == 0 {
                // Token chết → ép refresh rồi thử lại đúng 1 lần.
                await tokens.forceRefresh(for: account)
                continue
            }
            throw err
        }
        throw DriveError.noToken
    }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        do {
            return try dec.decode(type, from: data)
        } catch {
            throw DriveError.http(status: 0, reason: "badJSON", message: String(decoding: data.prefix(300), as: UTF8.self))
        }
    }

    // MARK: - Files: list/get

    /// Liệt kê con của 1 thư mục (q = '<id>' in parents), không lấy thùng rác.
    func listChildren(folderID: String) async throws -> [DriveFile] {
        var out: [DriveFile] = []
        var pageToken: String? = nil
        let fields = "nextPageToken, files(id,name,mimeType,size,modifiedTime,createdTime,trashed,parents,appProperties)"
        repeat {
            var query = [
                URLQueryItem(name: "q", value: "'\(folderID)' in parents and trashed = false"),
                URLQueryItem(name: "fields", value: fields),
                URLQueryItem(name: "pageSize", value: "1000"),
                URLQueryItem(name: "orderBy", value: "folder,name"),
            ]
            if let pageToken {
                query.append(URLQueryItem(name: "pageToken", value: pageToken))
            }
            let data = try await request("GET", "/files", query: query)
            let list = try decode(DriveFileList.self, data)
            out.append(contentsOf: list.files)
            pageToken = list.nextPageToken
        } while pageToken != nil
        return out
    }

    /// Tìm file theo tên trong 1 thư mục.
    func find(named name: String, in folderID: String) async throws -> DriveFile? {
        let query = [
            URLQueryItem(name: "q", value: "'\(folderID)' in parents and name = '\(name.escapingDriveQuery)' and trashed = false"),
            URLQueryItem(name: "fields", value: "files(id,name,mimeType,size,modifiedTime,appProperties)"),
            URLQueryItem(name: "pageSize", value: "10"),
        ]
        let data = try await request("GET", "/files", query: query)
        let list = try decode(DriveFileList.self, data)
        return list.files.first
    }

    /// Liệt kê MỌI file không-thùng-rác của account (1 lượt phân trang).
    /// Dùng cho đối chiếu part: Drive KHÔNG cho query theo id (q = "id = …"
    /// → 400 Invalid Value), nên phải liệt kê rồi tự suy cây từ parents.
    func listAllNonTrashed() async throws -> [DriveFile] {
        var out: [DriveFile] = []
        var pageToken: String? = nil
        // name BẮT BUỘC: DriveFile.name là non-optional — thiếu field là decode chết (bug 1.97).
        let fields = "nextPageToken, files(id,name,parents)"
        repeat {
            var query = [
                URLQueryItem(name: "q", value: "trashed = false"),
                URLQueryItem(name: "fields", value: fields),
                URLQueryItem(name: "pageSize", value: "1000"),
            ]
            if let pageToken {
                query.append(URLQueryItem(name: "pageToken", value: pageToken))
            }
            let data = try await request("GET", "/files", query: query)
            let list = try decode(DriveFileList.self, data)
            out.append(contentsOf: list.files)
            pageToken = list.nextPageToken
        } while pageToken != nil
        return out
    }

    func get(id: String) async throws -> DriveFile {
        let data = try await request("GET", "/files/\(id)", query: [
            URLQueryItem(name: "fields", value: "id,name,mimeType,size,modifiedTime,createdTime,trashed,parents,appProperties"),
        ])
        return try decode(DriveFile.self, data)
    }

    // MARK: - Thư mục gốc MyDrive

    /// Tìm/tạo thư mục `MyDrive` ở gốc Drive, đánh dấu appProperties để khôi phục.
    func ensureRootFolder() async throws -> DriveFile {
        // Thử tìm trước (marker appProperties để phân biệt với folder MyDrive thường).
        let query = [
            URLQueryItem(name: "q", value: "name = 'MyDrive' and mimeType = 'application/vnd.google-apps.folder' and trashed = false and 'root' in parents and appProperties has { key='mydFolder' and value='root' }"),
            URLQueryItem(name: "fields", value: "files(id,name,mimeType)"),
            URLQueryItem(name: "pageSize", value: "5"),
        ]
        let data = try await request("GET", "/files", query: query)
        let list = try decode(DriveFileList.self, data)
        if let found = list.files.first { return found }

        // Chưa có → tạo.
        let data2 = try await request("POST", "/files", jsonBody: [
            "name": "MyDrive",
            "mimeType": "application/vnd.google-apps.folder",
            "parents": ["root"],
            "appProperties": ["mydFolder": "root"],
        ])
        return try decode(DriveFile.self, data2)
    }

    /// Tạo/lấy cây thư mục lồng nhau (path = ["a", "b"]) dưới 1 folder, trả folder cuối.
    func ensureFolderPath(_ path: [String], under parentID: String) async throws -> DriveFile {
        var current = try await get(id: parentID)
        for component in path where !component.isEmpty {
            let children = try await listChildren(folderID: current.id)
            if let existing = children.first(where: { $0.name == component && $0.isFolder }) {
                current = existing
            } else {
                let data = try await request("POST", "/files", jsonBody: [
                    "name": component,
                    "mimeType": "application/vnd.google-apps.folder",
                    "parents": [current.id],
                ])
                current = try decode(DriveFile.self, data)
            }
        }
        return current
    }

    // MARK: - Upload

    /// Upload file nhỏ (<5 MB): 1 request multipart. existingID != nil → ghi đè (PATCH).
    func uploadSmall(
        data: Data,
        name: String,
        parentID: String,
        appProperties: [String: String]?,
        existingID: String? = nil
    ) async throws -> DriveFile {
        let boundary = "myd\(UUID().uuidString)"
        var body = Data()
        func part(_ s: String) { body.append(Data(s.utf8)) }

        part("--\(boundary)\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n")
        var meta: [String: Any] = ["name": name]
        if existingID == nil { meta["parents"] = [parentID] }
        if let appProperties { meta["appProperties"] = appProperties }
        body.append(try JSONSerialization.data(withJSONObject: meta))
        part("\r\n--\(boundary)\r\nContent-Type: application/octet-stream\r\n\r\n")
        body.append(data)
        part("\r\n--\(boundary)--\r\n")

        let method = existingID == nil ? "POST" : "PATCH"
        let path = existingID.map { "\(Self.uploadBase)/files/\($0)" } ?? "\(Self.uploadBase)/files"
        let data2 = try await request(
            method,
            path,
            query: [URLQueryItem(name: "fields", value: "id,name,mimeType,size,modifiedTime")],
            uploadBody: body,
            contentType: "multipart/related; boundary=\(boundary)"
        )
        return try decode(DriveFile.self, data2)
    }

    /// Upload lớn: resumable (mở session → đẩy chunk 8 MB tới khi server trả 200/201).
    /// Mất mạng/token giữa chừng: refresh + tiếp tục từ offset server đã nhận.
    func uploadResumable(
        fileURL: URL,
        name: String,
        parentID: String,
        appProperties: [String: String]?,
        progress: ((Int64) -> Void)? = nil
    ) async throws -> DriveFile {
        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let totalSize = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        var meta: [String: Any] = ["name": name, "parents": [parentID]]
        if let appProperties { meta["appProperties"] = appProperties }
        let metaJSON = try JSONSerialization.data(withJSONObject: meta)

        // 1) Mở session resumable → server trả upload URL qua header Location.
        var initReq = URLRequest(url: URL(string: "\(Self.uploadBase)/files?uploadType=resumable&fields=id,name,mimeType,size")!)
        let token = try await tokens.validAccessToken(for: account)
        initReq.httpMethod = "POST"
        initReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        initReq.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        initReq.setValue("\(totalSize)", forHTTPHeaderField: "X-Upload-Content-Length")
        initReq.setValue("application/octet-stream", forHTTPHeaderField: "X-Upload-Content-Type")
        initReq.httpBody = metaJSON
        let (initData, initResp) = try await session.data(for: initReq)
        guard let httpInit = initResp as? HTTPURLResponse, httpInit.statusCode == 200,
              let uploadURL = httpInit.value(forHTTPHeaderField: "Location") else {
            let status = (initResp as? HTTPURLResponse)?.statusCode ?? 0
            throw DriveError.parse(status: status, data: initData)
        }

        // 2) Đẩy từng chunk. 308 = đã nhận, tiếp tục; 401 = refresh rồi gửi lại
        //    đúng chunk đó; server trả 200/201 khi nhận đủ file.
        let fileHandle = try FileHandle(forReadingFrom: fileURL)
        defer { try? fileHandle.close() }
        var offset: Int64 = 0
        var retries = 0

        while true {
            if offset >= totalSize {
                // Đã đẩy hết → hỏi trạng thái lần cuối (server có thể chưa trả 200).
                return try await queryResumableStatus(uploadURL: uploadURL, totalSize: totalSize)
            }
            let chunk = fileHandle.readData(ofLength: Self.chunkSize)
            let isLast = (offset + Int64(chunk.count) >= totalSize)
            var req = URLRequest(url: URL(string: uploadURL)!)
            req.httpMethod = "PUT"
            req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            if chunk.isEmpty {
                req.setValue("bytes */\(totalSize)", forHTTPHeaderField: "Content-Range")
            } else {
                req.setValue("bytes \(offset)-\(offset + Int64(chunk.count) - 1)/\(totalSize)", forHTTPHeaderField: "Content-Range")
            }
            req.httpBody = chunk

            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse else {
                throw DriveError.http(status: 0, reason: "noResponse", message: nil)
            }
            switch http.statusCode {
            case 200, 201:
                progress?(totalSize)
                return try decode(DriveFile.self, data)
            case 308:
                retries = 0
                offset += Int64(chunk.count)
                progress?(offset)
            case 401:
                retries += 1
                if retries > 3 { throw DriveError.noToken }
                await tokens.forceRefresh(for: account)
                // Gửi lại đúng chunk (offset chưa tăng).
            case 500, 502, 503:
                // Lỗi server tạm thời: hỏi xem server đã nhận tới đâu rồi tiếp tục từ đó.
                retries += 1
                if retries > 5 { throw DriveError.parse(status: http.statusCode, data: data) }
                let acked = try await queryResumableAcked(uploadURL: uploadURL, totalSize: totalSize)
                if acked > offset {
                    try fileHandle.seek(toOffset: UInt64(acked))
                    offset = acked
                }
            default:
                throw DriveError.parse(status: http.statusCode, data: data)
            }
        }
    }

    /// Mở session resumable rồi GIAO file cho background URLSession (daemon
    /// nsurlsessiond upload — kill app vẫn chạy). Trả true nếu đã giao nền.
    func startBackgroundUpload(fileURL: URL, name: String, parentID: String, appProperties: [String: String]?, path: String, partIndex: Int, partSize: Int64) async throws -> Bool {
        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let totalSize = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        var meta: [String: Any] = ["name": name, "parents": [parentID]]
        if let appProperties { meta["appProperties"] = appProperties }
        let metaJSON = try JSONSerialization.data(withJSONObject: meta)

        var initReq = URLRequest(url: URL(string: "\(Self.uploadBase)/files?uploadType=resumable&fields=id,name,mimeType,size")!)
        let token = try await tokens.validAccessToken(for: account)
        initReq.httpMethod = "POST"
        initReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        initReq.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        initReq.setValue("\(totalSize)", forHTTPHeaderField: "X-Upload-Content-Length")
        initReq.setValue("application/octet-stream", forHTTPHeaderField: "X-Upload-Content-Type")
        initReq.httpBody = metaJSON
        let (initData, initResp) = try await session.data(for: initReq)
        guard let httpInit = initResp as? HTTPURLResponse, httpInit.statusCode == 200,
              let uploadURL = httpInit.value(forHTTPHeaderField: "Location") else {
            let status = (initResp as? HTTPURLResponse)?.statusCode ?? 0
            throw DriveError.parse(status: status, data: initData)
        }

        BackgroundUploader.shared.start(job: .init(
            email: account.email,
            path: path,
            partIndex: partIndex,
            partSize: totalSize,
            remoteName: name,
            uploadURL: uploadURL,
            fileURL: fileURL.path,
            createdAt: Date()
        ))
        return true
    }

    /// Hỏi trạng thái session resumable: server trả Range: bytes=0-N đã nhận.
    /// Trả -1 nếu session đã hoàn tất (server trả 200/201 kèm file JSON).
    private func queryResumableAcked(uploadURL: String, totalSize: Int64) async throws -> Int64 {
        let token = try await tokens.validAccessToken(for: account)
        var req = URLRequest(url: URL(string: uploadURL)!)
        req.httpMethod = "PUT"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("bytes */\(totalSize)", forHTTPHeaderField: "Content-Range")
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw DriveError.http(status: 0, reason: "noResponse", message: nil)
        }
        if http.statusCode == 200 || http.statusCode == 201 { return -1 }   // xong
        if http.statusCode == 308 {
            if let range = http.value(forHTTPHeaderField: "Range"),
               let last = range.split(separator: "-").last, let n = Int64(last) {
                return n + 1
            }
            return 0
        }
        throw DriveError.parse(status: http.statusCode, data: data)
    }

    /// Hoàn tất session: hỏi tới khi server trả 200/201 hoặc ném lỗi.
    private func queryResumableStatus(uploadURL: String, totalSize: Int64) async throws -> DriveFile {
        let token = try await tokens.validAccessToken(for: account)
        var req = URLRequest(url: URL(string: uploadURL)!)
        req.httpMethod = "PUT"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("bytes */\(totalSize)", forHTTPHeaderField: "Content-Range")
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw DriveError.http(status: 0, reason: "noResponse", message: nil)
        }
        if http.statusCode == 200 || http.statusCode == 201 {
            return try decode(DriveFile.self, data)
        }
        throw DriveError.parse(status: http.statusCode, data: data)
    }

    // MARK: - Update metadata / trash

    /// Đổi tên/di chuyển/thay appProperties (PATCH metadata — không re-upload).
    func updateMetadata(
        id: String,
        name: String? = nil,
        addParents: String? = nil,
        removeParents: String? = nil,
        appProperties: [String: String]? = nil
    ) async throws -> DriveFile {
        var body: [String: Any] = [:]
        if let name { body["name"] = name }
        if let appProperties { body["appProperties"] = appProperties }
        var query: [URLQueryItem] = []
        if let addParents { query.append(URLQueryItem(name: "addParents", value: addParents)) }
        if let removeParents { query.append(URLQueryItem(name: "removeParents", value: removeParents)) }
        query.append(URLQueryItem(name: "fields", value: "id,name,mimeType,parents,modifiedTime"))
        let data = try await request("PATCH", "/files/\(id)", query: query, jsonBody: body)
        return try decode(DriveFile.self, data)
    }

    /// Đưa vào thùng rác (không xoá hẳn — còn cứu được).
    func trash(id: String) async throws {
        _ = try await request("PATCH", "/files/\(id)", jsonBody: ["trashed": true])
    }

    /// Lấy khỏi thùng rác (khôi phục từ "Đã xóa gần đây").
    func untrash(id: String) async throws {
        _ = try await request("PATCH", "/files/\(id)", jsonBody: ["trashed": false])
    }

    // MARK: - Download

    /// Tải nội dung file về Data (file nhỏ).
    func download(id: String) async throws -> Data {
        try await request("GET", "/files/\(id)", query: [URLQueryItem(name: "alt", value: "media")])
    }

    /// Tải nội dung file về đĩa (stream qua URLSession.download — không giữ trong RAM).
    func downloadToFile(id: String, to destURL: URL) async throws {
        for attempt in 0..<2 {
            let token = try await tokens.validAccessToken(for: account)
            var comps = URLComponents(string: "\(Self.apiBase)/files/\(id)")!
            comps.queryItems = [URLQueryItem(name: "alt", value: "media")]
            var req = URLRequest(url: comps.url!)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (tmpLocal, resp) = try await session.download(for: req)
            guard let http = resp as? HTTPURLResponse else {
                throw DriveError.http(status: 0, reason: "noResponse", message: nil)
            }
            if http.statusCode == 401 && attempt == 0 {
                await tokens.forceRefresh(for: account)
                continue
            }
            guard http.statusCode == 200 else {
                let data = try? Data(contentsOf: tmpLocal)
                throw DriveError.parse(status: http.statusCode, data: data)
            }
            let fm = FileManager.default
            if fm.fileExists(atPath: destURL.path) { try fm.removeItem(at: destURL) }
            try fm.moveItem(at: tmpLocal, to: destURL)
            return
        }
        throw DriveError.noToken
    }

    // MARK: - Quota

    /// Dung lượng account: (giới hạn, đã dùng) theo byte.
    func storageQuota() async throws -> (limit: Int64, usage: Int64) {
        let data = try await request("GET", "/about", query: [
            URLQueryItem(name: "fields", value: "user(emailAddress,displayName),storageQuota(limit,usage,usageInDrive)"),
        ])
        let about = try decode(DriveAbout.self, data)
        let limit = about.storageQuota?.limit.flatMap { Int64($0) } ?? 0
        let usage = about.storageQuota?.usage.flatMap { Int64($0) } ?? 0
        return (limit, usage)
    }
}

// MARK: - Helpers

extension String {
    /// Escape chuỗi dùng trong q= của Drive (dấu nháy đơn, backslash).
    var escapingDriveQuery: String {
        replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
    }
}

/// DriveClient xin token qua interface này (AccountStore cài).
protocol TokenProviding: AnyObject {
    func validAccessToken(for account: DriveAccount) async throws -> String
    func forceRefresh(for account: DriveAccount) async
}
