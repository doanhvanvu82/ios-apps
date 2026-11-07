import SwiftUI

/// Quản lý tài khoản Google: thêm (OAuth), đăng nhập lại, xoá; xem dung lượng pool.
struct AccountsView: View {
    @StateObject private var accounts = AccountStore.shared
    @State private var signingIn = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(accounts.accounts) { acc in
                        accountRow(acc)
                    }
                } header: {
                    Text("Tài khoản Google")
                } footer: {
                    Text("File được tải lên account còn trống nhiều nhất; account đầy app tự chuyển sang account kế tiếp. Pool: \(poolText).")
                }

                Section {
                    Button {
                        signIn()
                    } label: {
                        if signingIn {
                            HStack { ProgressView(); Text("Đang mở Google…") }
                        } else {
                            Label("Thêm tài khoản Google", systemImage: "plus.circle.fill")
                        }
                    }
                    .disabled(signingIn || !GoogleAuthService.isConfigured)
                    if !GoogleAuthService.isConfigured {
                        Text("Chưa cấu hình OAuth Client ID. Xem SETUP.md: tạo oauth_client.txt rồi build lại.")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("Thêm account")
                }
            }
            .navigationTitle("Tài khoản")
            .alert("Lỗi đăng nhập", isPresented: Binding(
                get: { errorText != nil },
                set: { if !$0 { errorText = nil } }
            )) {
                Button("Đã hiểu", role: .cancel) {}
            } message: {
                Text(errorText ?? "")
            }
        }
    }

    private var poolText: String {
        let limit = accounts.accounts.compactMap { $0.quotaLimit }.reduce(0, +)
        let usage = accounts.accounts.compactMap { $0.quotaUsage }.reduce(0, +)
        guard limit > 0 else { return "chưa biết" }
        return ByteCountFormatter.string(fromByteCount: usage, countStyle: .file) + " / " + ByteCountFormatter.string(fromByteCount: limit, countStyle: .file)
    }

    private func accountRow(_ acc: DriveAccount) -> some View {
        HStack {
            Image(systemName: acc.needsReauth ? "person.badge.clock" : "person.crop.circle.fill")
                .font(.title2)
                .foregroundStyle(acc.needsReauth ? .orange : Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(acc.email)
                    .font(.subheadline.weight(.medium))
                if acc.needsReauth {
                    Text("Cần đăng nhập lại")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if let limit = acc.quotaLimit, let usage = acc.quotaUsage {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(ByteCountFormatter.string(fromByteCount: usage, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: limit, countStyle: .file))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ProgressView(value: Double(usage), total: Double(limit))
                            .tint(usage > limit * 9 / 10 ? .orange : Theme.accent)
                    }
                } else {
                    Text("Đang lấy dung lượng…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if accounts.activeEmail == acc.email {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.accent)
            }
        }
        .swipeActions {
            if acc.needsReauth {
                Button("Đăng nhập lại") { signIn(email: acc.email) }
                    .tint(.orange)
            }
            Button(role: .destructive) {
                AccountStore.shared.removeAccount(acc.email)
            } label: {
                Label("Xoá", systemImage: "trash")
            }
        }
    }

    private func signIn(email: String? = nil) {
        signingIn = true
        Task {
            do {
                let result = try await GoogleAuthService.shared.signIn(presenting: .init())
                await MainActor.run {
                    AccountStore.shared.addAccount(email: result.email, tokens: result.tokens)
                    SyncEngine.syncNowPublic()
                    signingIn = false
                }
            } catch {
                await MainActor.run {
                    if !String(describing: error).contains("cancel") {
                        errorText = error.localizedDescription
                    }
                    signingIn = false
                }
            }
        }
    }
}
