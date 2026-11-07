import SwiftUI

/// Tab gốc: Files / Tài khoản / Cài đặt.
struct ContentView: View {
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            FilesView()
                .tabItem { Label("Tệp", systemImage: "folder") }
                .tag(0)
            AccountsView()
                .tabItem { Label("Tài khoản", systemImage: "person.crop.circle") }
                .tag(1)
            SettingsView()
                .tabItem { Label("Cài đặt", systemImage: "gearshape") }
                .tag(2)
        }
        .onOpenURL { url in
            // "Copy to MyDrive" từ share sheet app khác: nhập ngay vào Inbox.
            InboxImporter.handleIncomingURL(url)
        }
    }
}
