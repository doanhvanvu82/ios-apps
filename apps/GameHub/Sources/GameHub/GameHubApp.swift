import SwiftUI
import UIKit

/// Khoá hướng màn hình toàn cục — AppDelegate đọc cái này khi iOS hỏi
/// "app cho phép xoay hướng nào?".
enum OrientationLock {
    static var mask: UIInterfaceOrientationMask = .portrait
}

/// AppDelegate bắt buộc phải có để `requestGeometryUpdate` hoạt động:
/// iOS sẽ hỏi hàm này "giờ được phép xoay hướng nào?" mỗi khi có yêu cầu.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        OrientationLock.mask
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // App luôn khởi động ở hướng dọc. Nếu app bị kill lúc đang chơi game
        // (mask = landscape-only), lần mở lại iPhone có thể giữ hướng ngang
        // hoặc kẹt — reset cho chắc.
        OrientationLock.mask = .portrait
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        AppLog.info("App active — mask hiện tại = \(OrientationManager.name(OrientationLock.mask))")
    }
}

@main
struct GameHubApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}
