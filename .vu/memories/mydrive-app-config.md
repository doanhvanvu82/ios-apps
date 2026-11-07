---
description: "MyDrive: kiến trúc upload nền background URLSession"
evidence:
  - path: "apps/MyDrive/Sources/MyDrive/Sync/BackgroundUploader.swift"
    quote: "/// Upload nền THẬT qua **URLSession background** — daemon `nsurlsessiond` của\n/// iOS giữ luồng đẩy dữ liệu: kill app vẫn tiếp tục, mất mạng tự resume, xong\n/// hệ thống đánh thức app để ghi kết quả vào index."
  - path: "apps/MyDrive/Sources/MyDrive/MyDriveApp.swift"
    quote: "        BackgroundUploader.pendingCompletion = completionHandler\n        _ = BackgroundUploader.shared   // ép dựng session + loadJobs"
  - path: "apps/MyDrive/Sources/MyDrive/Sync/SyncEngine.swift"
    quote: "        // 1) Nếu chưa có placement (node mới HOẶC node có parts nil — UI upsert\n        //    trước khi op chạy) → đặt account(s) theo dung lượng. Trước đây chỉ\n        //    kiểm tra node == nil → parts nil thoát im lặng, op bị coi là xong"
---
MyDrive upload nền: part ≥5MB đi qua background URLSession ("vn.vudv.mydrive.upload", daemon nsurlsessiond — kill app vẫn upload). Luồng: DriveClient.startBackgroundUpload mở resumable session lấy uploadURL → BackgroundUploader.shared.start(job) với file part trên tmp → daemon PUT → didCompleteWithError đọc JSON Drive lấy fileID → IndexStore.updatePart + triggerSync. AppDelegate cài handleEventsForBackgroundURLSession (giữ completionHandler vào BackgroundUploader.pendingCompletion). Job persist ở MyDrive.meta/bg-jobs.json; loadJobs re-start job có file part còn. Part <5MB vẫn upload trong app. Bẫy: uploadFile phải đặt placement khi parts nil/rỗng (không chỉ node==nil) — UI upsert node trước khi op chạy, ngược lại op "xong" im lặng không upload gì (bug 07/11/2026).
