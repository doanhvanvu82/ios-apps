import SwiftUI

/// Tab gốc: Files / Tài khoản / Cài đặt.
struct ContentView: View {
    @State private var tab = 0

    var body: some View {
        TabView(selection: tabSelection) {
            FilesView()
                .tabItem { Label("Tệp", systemImage: "folder") }
                .tag(0)
            SharedTabView()
                .tabItem { Label("Được chia sẻ", systemImage: "person.2") }
                .tag(1)
            AccountsView()
                .tabItem { Label("Tài khoản", systemImage: "person.crop.circle") }
                .tag(2)
            SettingsView()
                .tabItem { Label("Cài đặt", systemImage: "gearshape") }
                .tag(3)
        }
        .onOpenURL { url in
            // "Copy to MyDrive" từ share sheet app khác: nhập ngay vào Inbox.
            InboxImporter.handleIncomingURL(url)
        }
    }

    /// Binding tùy biến: bấm LẠI tab đang mở (giá trị trùng) vẫn đi qua setter —
    /// phát thông báo để màn đang mở pop về root (giống app Files); onChange
    /// thường không bắn khi giá trị không đổi nên phải can thiệp ở đây.
    private var tabSelection: Binding<Int> {
        Binding(
            get: { tab },
            set: { newValue in
                if newValue == tab {
                    NotificationCenter.default.post(name: .myDriveTabRetapped, object: newValue)
                }
                tab = newValue
            }
        )
    }
}

extension Notification.Name {
    /// Bấm lại tab đang mở — tham số object = index của tab bị bấm lại.
    static let myDriveTabRetapped = Notification.Name("myDriveTabRetapped")
}
