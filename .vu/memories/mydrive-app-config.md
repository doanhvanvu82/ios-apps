---
description: "MyDrive: worker song song + khóa IndexStore + complete trễ"
evidence:
  - path: "apps/MyDrive/Sources/MyDrive/Sync/IndexStore.swift"
    quote: "private let dictLock = NSLock()\n\n    /// Đọc snapshot an toàn trong lock.\n    private func withDict<T>(_ body: (inout [String: IndexNode]) -> T) -> T {\n        dictLock.lock()\n        defer { dictLock.unlock() }\n        return body(&index)\n    }"
  - path: "apps/MyDrive/Sources/MyDrive/Sync/SyncEngine.swift"
    quote: "if let parts = index.node(at: p)?.parts, !parts.isEmpty {\n                        isFullyUploaded = parts.allSatisfy { $0.driveFileId != nil }\n                    } else {\n                        isFullyUploaded = false\n                    }"
  - path: "apps/MyDrive/Sources/MyDrive/Sync/Journal.swift"
    quote: "func completeUpload(path: String) {\n        queue.async { [weak self] in\n            guard let self else { return }\n            self.entries.removeAll { e in\n                if case let .uploadFile(p) = e.op { return p == path }"
---
MyDrive sync: journal đẩy SONG SONG 6 worker (1.87) — do đó IndexStore PHẢI khóa dictionary (dictLock NSLock, thêm 1.89) cho MỌI đọc/ghi: 6 worker cùng mutate Dictionary không khóa = data race crash EXC_BAD_ACCESS (gặp thật khi đẩy ~700 file). Op uploadFile chỉ complete khi MỌI part có driveFileId; callback nền (finishJob) gọi Journal.completeUpload khi file đủ part — không complete ngay khi giao nền (tránh requeue trùng). adoptOrphanLocalFiles DEDUPE theo journal — cài lại + copy lại không sinh op trùng.
