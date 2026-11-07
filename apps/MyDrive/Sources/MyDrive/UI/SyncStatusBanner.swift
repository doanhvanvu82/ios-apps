import SwiftUI

/// Băng trạng thái sync hiển thị trên đầu màn Files.
struct SyncStatusBanner: View {
    let status: SyncStatus

    var body: some View {
        Group {
            if status.isWorking {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(status.text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(.bar)
            } else if case let .error(msg) = status.phase {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.12))
            } else if status.hasPendingWork {
                HStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                    Text(status.text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(.bar)
            } else if !status.needsReauth.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "person.badge.clock")
                        .foregroundStyle(.orange)
                    Text("Cần đăng nhập lại: \(status.needsReauth.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.12))
            }
        }
    }
}
