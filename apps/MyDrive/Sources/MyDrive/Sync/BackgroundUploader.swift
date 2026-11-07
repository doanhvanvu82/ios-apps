import Foundation
import UIKit

/// Upload nền THẬT qua **URLSession background** — daemon `nsurlsessiond` của
/// iOS giữ luồng đẩy dữ liệu: kill app vẫn tiếp tục, mất mạng tự resume, xong
/// hệ thống đánh thức app để ghi kết quả vào index. Đây là cách app
/// Google Drive/Photos upload thật (không phải hack âm thanh/vị trí).
///
/// Chia việc: DriveClient chuẩn bị (đặt placement, tạo cây thư mục, mở resumable
/// session lấy upload URL) rồi giao **file part** cho uploader. Trạng thái job
/// persist trong MyDrive.meta/bg-jobs.json — sống qua kill app/reboot.
final class BackgroundUploader: NSObject {
    static let shared = BackgroundUploader()

    /// Một nhiệm vụ upload nền (persist JSON).
    struct Job: Codable {
        var email: String              // account upload
        var path: String               // path logic trong mirror (vd "Ảnh/a.jpg")
        var partIndex: Int
        var partSize: Int64
        var remoteName: String
        var uploadURL: String          // URL session resumable đã mở sẵn
        var fileURL: String            // file part trên đĩa (tmp, ổn định)
        var createdAt: Date
    }

    @Published private(set) var activeCount: Int = 0

    private var session: URLSession!
    /// taskIdentifier (ổn định qua các lần chạy của cùng session) → job.
    private var jobs: [Int: Job] = [:]
    /// Buffer gom response JSON của Drive cho từng task (background data delegate).
    private var buffers: [Int: Data] = [:]
    private let jobsFile: URL
    private let queue = DispatchQueue(label: "vn.vudv.mydrive.bgupload")

    private override init() {
        jobsFile = AppPaths.meta.appendingPathComponent("bg-jobs.json")
        super.init()
        let cfg = URLSessionConfiguration.background(withIdentifier: "vn.vudv.mydrive.upload")
        cfg.isDiscretionary = false
        cfg.sessionSendsLaunchEvents = true     // iOS đánh thức app khi có sự kiện
        cfg.waitsForConnectivity = true
        cfg.timeoutIntervalForResource = 24 * 3600
        session = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
        loadJobs()
    }

    // MARK: - Giao việc

    /// Bắt đầu upload 1 part nền. Trả true nếu đã giao (job mới hoặc đang có sẵn).
    @discardableResult
    func start(job: Job) -> Bool {
        queue.sync { [weak self] in
            guard let self else { return false }
            // Trùng (path, partIndex) đang chạy → bỏ qua (requeue có thể gọi lại).
            if self.jobs.values.contains(where: { $0.path == job.path && $0.partIndex == job.partIndex }) {
                AppLog.log("bgup", "⏭️ Đã có job nền cho \(job.remoteName) — bỏ qua")
                return true
            }
            var req = URLRequest(url: URL(string: job.uploadURL)!)
            req.httpMethod = "PUT"
            req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            req.setValue("bytes 0-\(job.partSize - 1)/\(job.partSize)", forHTTPHeaderField: "Content-Range")
            let task = self.session.uploadTask(with: req, fromFile: URL(fileURLWithPath: job.fileURL))
            self.jobs[task.taskIdentifier] = job
            self.persistLocked()
            self.refreshActiveCountLocked()
            task.resume()
            AppLog.log("bgup", "🚀 Nền: \(job.remoteName) (\(ByteFmt.string(job.partSize))) → \(job.email) [task \(task.taskIdentifier)]")
            return true
        }
    }

    /// Có job nền đang chạy cho (path, partIndex)?
    func hasActiveJob(path: String, partIndex: Int) -> Bool {
        queue.sync { jobs.values.contains { $0.path == path && $0.partIndex == partIndex } }
    }

    /// Tổng số job đang chạy (UI hiển thị).
    var count: Int { queue.sync { jobs.count } }

    // MARK: - Persist

    private func loadJobs() {
        guard let data = try? Data(contentsOf: jobsFile),
              let list = try? JSONDecoder().decode([Job].self, from: data) else { return }
        for j in list {
            // Job cũ chưa có task (app chết trước khi start) — file part còn thì
            // giao lại nền, không còn thì bỏ (requeue của engine sẽ mở lại).
            if FileManager.default.fileExists(atPath: j.fileURL) {
                _ = start(job: j)
            }
        }
        if !list.isEmpty {
            AppLog.log("bgup", "📂 Xử lý \(list.count) job nền từ phiên trước")
        }
    }

    /// Gọi trong queue.sync.
    private func persistLocked() {
        let list = Array(jobs.values)
        if let data = try? JSONEncoder().encode(list) {
            try? data.write(to: jobsFile, options: .atomic)
        }
    }

    private func refreshActiveCountLocked() {
        let n = jobs.count
        DispatchQueue.main.async { [weak self] in
            self?.activeCount = n
        }
    }

    private func finishJob(taskID: Int, fileID: String?, error: String?) {
        queue.sync { [weak self] in
            guard let self, let job = self.jobs.removeValue(forKey: taskID) else { return }
            self.persistLocked()
            self.refreshActiveCountLocked()
            self.buffers[taskID] = nil
            if let fileID {
                AppLog.log("bgup", "✅ Nền xong: \(job.remoteName) → \(fileID)")
                IndexStore.shared.updatePart(
                    path: job.path, partIndex: job.partIndex,
                    accountEmail: job.email, driveFileId: fileID
                )
            } else {
                AppLog.log("bgup", "❌ Nền lỗi: \(job.remoteName) — \(error ?? "?")")
            }
            try? FileManager.default.removeItem(atPath: job.fileURL)
            // Engine quét lại (mirror index, hoàn tất node nếu đủ part).
            SyncEngine.triggerSyncPublic()
        }
    }
}

// MARK: - URLSessionDataDelegate (background session)

extension BackgroundUploader: URLSessionDataDelegate {
    /// iOS đánh thức app (kể cả cold start) khi có sự kiện nền: app phải dựng lại
    /// session (init của singleton tự làm) rồi BÁO LẠI qua completion handler.
    static var pendingCompletion: (() -> Void)?

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let taskID = task.taskIdentifier
        let http = task.response as? HTTPURLResponse
        let body = queue.sync { buffers[taskID] } ?? Data()

        if let error {
            // Cancelled (không phải fail thật) — iOS sẽ tự nối lại khi app sống lại.
            if (error as NSError).code == NSURLErrorCancelled { return }
            finishJob(taskID: taskID, fileID: nil, error: error.localizedDescription)
            return
        }
        switch http?.statusCode ?? 0 {
        case 200, 201:
            // Đủ bytes: server trả metadata file JSON → lấy id.
            let fileID = body.count > 0
                ? (try? JSONDecoder().decode(DriveFile.self, from: body))?.id
                : nil
            finishJob(taskID: taskID, fileID: fileID, error: fileID == nil ? "200 nhưng không đọc được id" : nil)
        case 401:
            // Token hết hạn giữa chừng — engine tự xếp lại (part vẫn unfinished).
            finishJob(taskID: taskID, fileID: nil, error: "Token hết hạn (401) — sẽ thử lại")
        default:
            finishJob(taskID: taskID, fileID: nil, error: "HTTP \(http?.statusCode ?? 0): \(String(decoding: body.prefix(200), as: UTF8.self))")
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        queue.async { [weak self] in
            self?.buffers[dataTask.taskIdentifier, default: Data()].append(data)
        }
    }

    /// Cuộc đánh thức nền kết thúc — phải gọi completion iOS đã trao cho
    /// AppDelegate.application(_:handleEventsForBackgroundURLSession:).
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            BackgroundUploader.pendingCompletion?()
            BackgroundUploader.pendingCompletion = nil
        }
    }
}
