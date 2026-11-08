import SwiftUI

/// iOS không cho app đọc trạng thái Safari extension, nên app chỉ hướng dẫn;
/// mọi thao tác (bật/tắt theo trang, API key, quét) nằm trong popup của extension.
struct ContentView: View {
    private let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    @State private var logContent = ""
    @State private var showLog = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Xem log chẩn đoán") {
                        loadLog()
                        showLog = true
                    }
                }

                Section("1. Bật tiện ích trong Safari") {
                    Step(number: 1, text: "Mở **Cài đặt › Ứng dụng › Safari › Tiện ích mở rộng**.")
                    Step(number: 2, text: "Chọn **AdsBlocker** và bật lên.")
                    Step(number: 3, text: "Ở mục quyền, chọn **Mọi trang web › Cho phép**.")
                    Button("Mở Cài đặt") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }

                Section("2. Dùng hằng ngày") {
                    Label("Popup/tab quảng cáo mở khi bấm vào trang và lớp phủ vô hình bị chặn tự động.", systemImage: "hand.raised")
                    Label("Bấm biểu tượng ô ghép hình trên thanh địa chỉ › **AdsBlocker** để xem số lượt đã chặn, tracker trên trang và bật/tắt **Chặn quảng cáo** / **Chống theo dõi**.", systemImage: "puzzlepiece.extension")
                    Label("Xem tiếp trong cửa sổ **hình trong hình**: bật video toàn màn hình rồi vuốt về màn hình chính.", systemImage: "pip")
                    Label("Nội dung Facebook/X/Instagram/TikTok nhúng trong trang bị thay bằng ô **Chạm để tải** — chạm khi muốn xem (mạng xã hội đó sẽ theo dõi bạn trên trang ấy).", systemImage: "hand.tap")
                }

                Section("3. Quét bằng AI (khi còn sót quảng cáo)") {
                    Label("Tạo API key miễn phí tại **aistudio.google.com** › Get API key.", systemImage: "key")
                    Label("Trong popup AdsBlocker › **Cài đặt**: dán API key, bấm **Tải danh sách model** rồi chọn model.", systemImage: "gearshape")
                    Label("Trên trang còn quảng cáo: bấm **Quét trang**, xem các rule đề xuất, chọn rule đúng rồi **Áp dụng**. Lần sau trang đó tự chặn, không cần quét lại.", systemImage: "sparkle.magnifyingglass")
                    Label("Khi quét, ảnh chụp màn hình và cấu trúc các khối nghi là quảng cáo được gửi lên Google Gemini. API key chỉ lưu trong Keychain của máy.", systemImage: "lock.shield")
                }

                Section("4. Bật thêm chống theo dõi có sẵn của Safari") {
                    Text("Safari tự làm được vài việc extension không làm thay được (chặn cookie bên thứ ba, ẩn IP, chống lấy dấu vân tay). Vào **Cài đặt › Ứng dụng › Safari** và bật:")
                    Step(number: 1, text: "**Ngăn theo dõi chéo trang web** — chặn cookie bên thứ ba.")
                    Step(number: 2, text: "**Ẩn địa chỉ IP** › **Khỏi trình theo dõi và trang web**.")
                    Step(number: 3, text: "**Nâng cao › Bảo vệ nâng cao chống theo dõi và lấy dấu vân tay** › **Tất cả lượt duyệt web** (mặc định chỉ bật trong tab Riêng tư; cũng xoá tham số theo dõi trong link).")
                    Button("Mở Cài đặt") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            }
            .navigationTitle("AdsBlocker")
            .safeAreaInset(edge: .bottom) {
                Text("Phiên bản \(version)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
            }
            .sheet(isPresented: $showLog) {
                NavigationStack {
                    ScrollView {
                        Text(logContent)
                            .font(.system(.body, design: .monospaced))
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .navigationTitle("Log chẩn đoán")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Đóng") { showLog = false }
                        }
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Tải lại") { loadLog() }
                        }
                    }
                }
            }
        }
    }

    private func loadLog() {
        let logDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Logs")
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let today = dateFormatter.string(from: Date())
        let logFile = logDir.appendingPathComponent("\(today).log")
        do {
            logContent = try String(contentsOf: logFile, encoding: .utf8)
        } catch {
            logContent = "Chưa có log: \(error.localizedDescription)"
        }
    }
}

private struct Step: View {
    let number: Int
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.headline)
                .frame(width: 24, height: 24)
                .background(Circle().fill(.green.opacity(0.2)))
            Text(text)
        }
    }
}
