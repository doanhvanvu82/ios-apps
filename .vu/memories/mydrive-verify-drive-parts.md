---
description: "MyDrive: Drive API không query được theo id + fields bắt buộc name/mimeType"
evidence:
  - path: "apps/MyDrive/Sources/MyDrive/Drive/DriveClient.swift"
    quote: "        // name BẮT BUỘC: DriveFile.name là non-optional — thiếu field là decode chết (bug 1.97).\n        // mimeType cần cho isFolder (dedupe folder trùng phân biệt folder/file).\n        let fields = \"nextPageToken, files(id,name,mimeType,parents)\""
  - path: "apps/MyDrive/Sources/MyDrive/Drive/DriveClient.swift"
    quote: "    /// Dùng cho đối chiếu part: Drive KHÔNG cho query theo id (q = \"id = …\"\n    /// → 400 Invalid Value), nên phải liệt kê rồi tự suy cây từ parents."
  - path: "apps/MyDrive/Sources/MyDrive/Sync/SyncEngine.swift"
    quote: "        // 4.5) DỌN FOLDER TRÙNG: nhiều worker song song cùng ensureFolderPath\n        //      (TOCTOU: cùng thấy chưa có → cùng tạo) sinh folder trùng tên"
---
MyDrive verifyDriveParts (1.96→1.98, 08/11/2026): Drive files.list KHÔNG hỗ trợ q = "id = '…'" (400 Invalid Value) — đối chiếu driveFileId phải listAllNonTrashed (q = "trashed = false") rồi tự so id. fields bắt buộc gồm name (DriveFile.name non-optional — thiếu là decode chết "badJSON" HTTP 0) và mimeType (isFolder của dedupe). Bước verify chạy sau processJournal, lỗi mạng → coi như còn sống (đừng requeue oan). Chứng minh trên máy thật: index 3409 file tưởng "đã sync" trong khi Drive chỉ còn 2 mục — id chết do xóa trên web; 1.98 đẩy lại đủ 3409/3409.
