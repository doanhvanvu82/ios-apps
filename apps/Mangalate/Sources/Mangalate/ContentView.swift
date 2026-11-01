import SwiftUI

/// iOS không cho app đọc trạng thái Safari extension, nên app chỉ hướng dẫn;
/// mọi thao tác (API key, chọn model, dịch) nằm trong popup/nút nổi của extension.
struct ContentView: View {
    private let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"

    var body: some View {
        NavigationStack {
            List {
                Section("1. Bật tiện ích trong Safari") {
                    Step(number: 1, text: "Mở **Cài đặt › Ứng dụng › Safari › Tiện ích mở rộng**.")
                    Step(number: 2, text: "Chọn **Mangalate** và bật lên.")
                    Step(number: 3, text: "Ở mục quyền, chọn **Mọi trang web › Cho phép**.")
                    Button("Mở Cài đặt") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }

                Section("2. Nhập Gemini API key") {
                    Label("Tạo API key miễn phí tại **aistudio.google.com** › Get API key.", systemImage: "key")
                    Label("Mở trang truyện › bấm biểu tượng ô ghép hình trên thanh địa chỉ › **Mangalate** › dán key, bấm **Lưu key**.", systemImage: "puzzlepiece.extension")
                    Label("Bấm **Tải danh sách model** rồi chọn model (mặc định gemini-2.5-flash).", systemImage: "gear")
                }

                Section("3. Dịch một chapter") {
                    Label("Mở chapter truyện (ảnh manga/webtoon), chờ ảnh tải xong.", systemImage: "photo.on.rectangle")
                    Label("Bấm nút **Dịch** ở góc phải dưới màn hình.", systemImage: "character.bubble")
                    Label("Extension đọc chữ ngay trên máy, chỉ gửi **phần chữ** lên Gemini rồi dán bản dịch đè lên bong bóng.", systemImage: "lock.shield")
                    Label("Bấm **Bản gốc** để xem lại; bấm **Bản dịch** để hiện lại.", systemImage: "arrow.left.arrow.right")
                }

                Section("Lưu ý") {
                    Text("Ảnh truyện không bao giờ được gửi lên AI — chỉ text OCR. API key lưu trong Keychain của máy.")
                    Text("Chữ dọc (truyện Nhật/Trung) và font cách điệu có thể nhận sai; truyện không lời sẽ không có gì để dịch.")
                }
            }
            .navigationTitle("Mangalate")
            .safeAreaInset(edge: .bottom) {
                Text("Phiên bản \(version)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
            }
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
                .background(Circle().fill(.indigo.opacity(0.2)))
            Text(text)
        }
    }
}
