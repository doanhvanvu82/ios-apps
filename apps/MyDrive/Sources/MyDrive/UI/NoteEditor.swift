import SwiftUI

/// Tạo ghi chú văn bản (.txt).
struct NoteEditor: View {
    var onSave: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Tên ghi chú", text: $name)
                Section("Nội dung") {
                    TextEditor(text: $text)
                        .frame(minHeight: 260)
                        .font(.system(.body, design: .monospaced))
                }
            }
            .navigationTitle("Ghi chú mới")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Huỷ") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") {
                        onSave(name.isEmpty ? "Ghi chú" : name, text)
                        dismiss()
                    }
                    .disabled(text.isEmpty)
                }
            }
        }
    }
}
