import SwiftUI
import UIKit
import WebKit

/// Bàn phím hệ thống cho game vẽ trên canvas (không có `<input>` thật nên chạm
/// vào ô nhập của game không bật bàn phím). Một ô nhập native ẩn giữ focus;
/// chữ gõ được chuyển vào trang qua `GameWebView.typeText`.
struct GameKeyboardField: UIViewRepresentable {
    @Binding var isActive: Bool
    let webView: () -> WKWebView?

    func makeUIView(context: Context) -> KeyCatcher {
        let field = KeyCatcher()
        field.alpha = 0.02
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.spellCheckingType = .no
        field.smartQuotesType = .no
        field.smartDashesType = .no
        field.smartInsertDeleteType = .no
        field.returnKeyType = .default
        field.delegate = context.coordinator
        field.onBackspace = { context.coordinator.send("\u{8}") }
        return field
    }

    func updateUIView(_ field: KeyCatcher, context: Context) {
        context.coordinator.parent = self
        DispatchQueue.main.async {
            if isActive, !field.isFirstResponder { field.becomeFirstResponder() }
            if !isActive, field.isFirstResponder { field.resignFirstResponder() }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: GameKeyboardField
        init(parent: GameKeyboardField) { self.parent = parent }

        func send(_ text: String) {
            guard let wv = parent.webView() else { return }
            GameWebView.typeText(wv, text)
        }

        // Ô luôn rỗng: mỗi lần gõ chuyển ngay vào game rồi bỏ.
        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange,
                       replacementString string: String) -> Bool {
            send(string.isEmpty ? "\u{8}" : string)
            return false
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            send("\n")
            return false
        }

        // Người dùng tự ẩn bàn phím (vuốt / nút ẩn của iPad) → tắt nút.
        func textFieldDidEndEditing(_ textField: UITextField) {
            if parent.isActive { parent.isActive = false }
        }
    }

    /// Ô rỗng không gọi `shouldChangeCharactersIn` khi bấm xoá → bắt ở đây.
    final class KeyCatcher: UITextField {
        var onBackspace: (() -> Void)?
        override func deleteBackward() {
            if text?.isEmpty ?? true { onBackspace?() }
            super.deleteBackward()
        }
    }
}
