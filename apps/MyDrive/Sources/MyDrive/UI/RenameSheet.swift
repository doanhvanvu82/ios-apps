import SwiftUI

/// Sheet đổi tên (alert với TextField bị iOS bỏ 1 lần khi dùng động).
struct RenameSheet: View {
    let currentName: String
    var onRename: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Tên mới", text: $text)
                    .autocorrectionDisabled()
            }
            .navigationTitle("Đổi tên")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Huỷ") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Đổi") {
                        let newName = text.trimmingCharacters(in: .whitespaces)
                        guard !newName.isEmpty else { return }
                        onRename(newName)
                        dismiss()
                    }
                }
            }
            .onAppear { text = currentName }
        }
    }
}
