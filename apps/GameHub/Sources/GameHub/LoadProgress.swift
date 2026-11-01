import SwiftUI
import WebKit

/// Theo dõi game còn đang nạp hay không, để màn chơi không chỉ là màn đen.
///
/// Nguồn tín hiệu:
/// - Lưu lượng của LocalWebServer (số tệp, số byte, tệp gần nhất).
/// - Ảnh chụp WebView thu nhỏ: hết tối = engine đã vẽ ra màn hình.
/// - Số lỗi JS mới trong AppLog từ lúc mở game.
///
/// Coi là xong khi màn hình đã sáng và server im ≥ 1.5s, hoặc server im quá
/// `maxIdle` (game có màn hình tối, hoặc WebGL chụp ra đen), hoặc quá `maxDuration`.
@MainActor
final class LoadProgress: ObservableObject {
    @Published private(set) var requests = 0
    @Published private(set) var bytes = 0
    @Published private(set) var lastFile = ""
    /// Số giây chưa có dữ liệu mới (0 khi đang tải).
    @Published private(set) var idleSeconds = 0
    @Published private(set) var errors = 0
    @Published private(set) var finished = false

    private static let tick: TimeInterval = 0.5
    private static let snapshotEvery = 4          // tick
    private static let quietAfterVisible: TimeInterval = 1.5
    private static let maxIdle: TimeInterval = 20
    private static let maxDuration: TimeInterval = 180

    private weak var server: LocalWebServer?
    private weak var webView: WKWebView?
    private var timer: Timer?
    private var startedAt = Date()
    private var errorBase = 0
    private var ticks = 0
    private var screenVisible = false
    private var snapshotPending = false

    func start(server: LocalWebServer) {
        stop()
        self.server = server
        startedAt = Date()
        errorBase = AppLog.shared.errorCount
        finished = false
        screenVisible = false
        timer = Timer.scheduledTimer(withTimeInterval: Self.tick, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.update() }
        }
    }

    func attach(_ webView: WKWebView) { self.webView = webView }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func update() {
        guard let server else { return stop() }
        let activity = server.activity
        requests = activity.requests
        bytes = activity.bytes
        if !activity.lastPath.isEmpty { lastFile = activity.lastPath }
        errors = max(0, AppLog.shared.errorCount - errorBase)

        let now = Date()
        let idle = now.timeIntervalSince(activity.lastAt ?? startedAt)
        idleSeconds = idle < 2 ? 0 : Int(idle)

        ticks += 1
        if !screenVisible, ticks % Self.snapshotEvery == 0 { checkScreen() }

        let done = (screenVisible && idle >= Self.quietAfterVisible)
            || idle >= Self.maxIdle
            || now.timeIntervalSince(startedAt) >= Self.maxDuration
        if done {
            finished = true
            stop()
            AppLog.info("Nạp xong: \(requests) tệp · \(Self.format(bytes: bytes)) trong \(Int(now.timeIntervalSince(startedAt)))s")
        }
    }

    private func checkScreen() {
        guard let webView, !snapshotPending else { return }
        snapshotPending = true
        let config = WKSnapshotConfiguration()
        config.snapshotWidth = 48
        webView.takeSnapshot(with: config) { [weak self] image, _ in
            Task { @MainActor in
                guard let self else { return }
                self.snapshotPending = false
                if let image, !CoverStore.isMostlyDark(image) { self.screenVisible = true }
            }
        }
    }

    static func format(bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

/// Dòng thống kê "128 tệp · 34 MB" dùng chung cho màn khởi động và thanh tải.
struct LoadStatsText: View {
    @ObservedObject var progress: LoadProgress

    var body: some View {
        Text(progress.requests == 0 ? "Đang chờ engine…"
             : "\(progress.requests) tệp · \(LoadProgress.format(bytes: progress.bytes))")
            .monospacedDigit()
            .contentTransition(.numericText())
            .animation(.default, value: progress.bytes)
    }
}

/// Thanh nhỏ dưới đáy màn chơi khi trang đã mở nhưng game còn nạp dữ liệu.
/// Chạm để xem log; nút ✕ để ẩn.
struct GameLoadingPill: View {
    @ObservedObject var progress: LoadProgress
    let accent: Color
    let onOpenLog: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .tint(accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(progress.idleSeconds > 0
                     ? "Đang xử lý… \(progress.idleSeconds)s chưa có dữ liệu mới"
                     : "Đang tải dữ liệu game")
                    .font(.caption.weight(.semibold))
                    .contentTransition(.numericText())
                HStack(spacing: 4) {
                    LoadStatsText(progress: progress)
                    if !progress.lastFile.isEmpty {
                        Text("· " + (progress.lastFile as NSString).lastPathComponent)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.65))
            }
            .frame(maxWidth: 300, alignment: .leading)

            if progress.errors > 0 {
                Label("\(progress.errors)", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.yellow)
                    .labelStyle(.titleAndIcon)
                    .accessibilityLabel("\(progress.errors) lỗi")
            }

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 26, height: 26)
                    .background(.white.opacity(0.12), in: Circle())
            }
            .accessibilityLabel("Ẩn thanh tải")
        }
        .foregroundStyle(.white)
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .environment(\.colorScheme, .dark)
        .contentShape(Capsule())
        .onTapGesture(perform: onOpenLog)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Chạm để xem log")
    }
}
