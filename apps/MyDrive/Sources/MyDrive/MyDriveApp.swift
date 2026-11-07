import SwiftUI

@main
struct MyDriveApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        AppLog.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    // "Copy to MyDrive" từ app khác (CFBundleDocumentTypes) → vào Inbox.
                    InboxImporter.handleIncomingURL(url)
                }
        }
    }
}

/// AppDelegate: nhận file từ share sheet/"Open in MyDrive" (nhận được trong
/// didFinishLaunching qua userActivity khi app mở lần đầu); nối transfer nền.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        return true
    }

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        InboxImporter.handleIncomingURL(url)
        return true
    }

    /// iOS đánh thức app (kể cả khi đã bị kill) khi upload nền xong — giữ
    /// completion, BackgroundUploader dựng lại session xong sẽ gọi lại.
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        BackgroundUploader.pendingCompletion = completionHandler
        _ = BackgroundUploader.shared   // ép dựng session + loadJobs
    }
}
