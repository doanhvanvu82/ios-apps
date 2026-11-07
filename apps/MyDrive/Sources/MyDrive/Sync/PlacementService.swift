import Foundation

/// Chọn account cho file/part: account còn trống nhiều nhất (biên an toàn 5%).
/// Quyết định ghi vào index (crash-safe) TRƯỚC khi upload.
final class PlacementService {
    static let shared = PlacementService()

    /// Biên an toàn: giữ lại 5% dung lượng (Google đếm cả thứ khác ngoài app).
    static let safetyMargin: Double = 0.05
    /// Quota cache cũ hơn 10 phút → refresh trước khi quyết định.
    static let cacheTTL: TimeInterval = 600

    private let accountStore: AccountStore
    private let journal: Journal

    init(accountStore: AccountStore = .shared, journal: Journal = .shared) {
        self.accountStore = accountStore
        self.journal = journal
    }

    /// Danh sách account khả dụng (đã đăng nhập, không needsReauth).
    func availableAccounts() -> [DriveAccount] {
        accountStore.accounts.filter { !$0.needsReauth }
    }

    /// Refresh quota của các account (chỉ account nào cache cũ/hết).
    func refreshQuotas(force: Bool = false) async {
        let accounts = availableAccounts()
        await withTaskGroup(of: Void.self) { group in
            for acc in accounts {
                let fresh = acc.quotaUpdatedAt.map { Date().timeIntervalSince($0) < Self.cacheTTL } ?? false
                if fresh && !force { continue }
                guard let client = accountStore.client(for: acc.email) else { continue }
                group.addTask { @MainActor in
                    do {
                        let (limit, usage) = try await client.storageQuota()
                        self.accountStore.updateQuota(email: acc.email, limit: limit, usage: usage)
                    } catch {
                        AppLog.log("placement", "⚠️ Không lấy được quota \(acc.email): \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    /// Chọn account tốt nhất cho 1 khối dữ liệu kích thước `size`.
    /// Trả nil nếu không account nào đủ chỗ (SyncEngine báo người dùng).
    func pickAccount(for size: Int64, excluding: Set<String> = []) async -> DriveAccount? {
        await refreshQuotas()
        let candidates = availableAccounts()
            .filter { !excluding.contains($0.email) }
            .compactMap { acc -> (acc: DriveAccount, free: Int64)? in
                guard let free = acc.freeBytes else { return nil }
                let usable = Double(free) * (1 - Self.safetyMargin)
                return Double(size) <= usable ? (acc, free) : nil
            }
        // Chọn account trống nhiều nhất.
        return candidates.max { $0.free < $1.free }?.acc
    }

    /// Rải N part theo placement: mỗi part chọn account trống nhiều nhất lúc đó
    /// (loại trừ account vừa chọn cho part trước nếu không còn đủ chỗ).
    func place(parts: [(index: Int, size: Int64)]) async -> [FilePart] {
        var result: [FilePart] = []
        var usedFree: [String: Int64] = [:]
        for part in parts {
            // Chọn account có free còn lại (trừ các part đã đặt) nhiều nhất mà đủ chỗ.
            let candidates = availableAccounts().compactMap { acc -> (acc: DriveAccount, free: Int64)? in
                guard let free = acc.freeBytes else { return nil }
                let alreadyUsed = usedFree[acc.email] ?? 0
                let remaining = free - alreadyUsed
                let usable = Double(remaining) * (1 - Self.safetyMargin)
                guard Double(part.size) <= usable else { return nil }
                return (acc, remaining)
            }
            if let best = candidates.max(by: { $0.free < $1.free }) {
                usedFree[best.acc.email, default: 0] += part.size
                result.append(FilePart(
                    index: part.index,
                    size: part.size,
                    accountEmail: best.acc.email,
                    driveFileId: nil,
                    remoteName: ""   // SyncEngine điền (cần tên file gốc)
                ))
            } else {
                // Không account nào đủ cho part này → đánh dấu accountEmail rỗng;
                // SyncEngine sẽ xử lý (báo pool đầy / retry sau).
                result.append(FilePart(index: part.index, size: part.size, accountEmail: "", driveFileId: nil, remoteName: ""))
            }
        }
        return result
    }

    /// Tổng dung lượng trống của pool.
    func poolFreeBytes() -> Int64 {
        availableAccounts().compactMap { $0.freeBytes }.reduce(0, +)
    }

    /// Tổng dung lượng pool (limit).
    func poolLimitBytes() -> Int64 {
        availableAccounts().compactMap { $0.quotaLimit }.reduce(0, +)
    }
}
