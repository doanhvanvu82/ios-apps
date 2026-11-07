import SwiftUI

/// Chọn thư mục đích (di chuyển file/thư mục). Danh sách bấm để đi xuống,
/// nút "Chọn thư mục này" xác nhận.
struct FolderPicker: View {
    @StateObject var store: FileSystemStore
    let currentPath: [String]
    let title: String
    var onPick: ([String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var path: [String] = []

    var body: some View {
        NavigationStack {
            List {
                if !path.isEmpty {
                    Button {
                        _ = path.popLast()
                    } label: {
                        Label(".. Quay lại", systemImage: "chevron.left")
                            .foregroundStyle(Theme.accent)
                    }
                }
                ForEach(dirs) { entry in
                    Button {
                        path.append(entry.name)
                    } label: {
                        Label(entry.name, systemImage: "folder.fill")
                            .foregroundStyle(Theme.accent)
                    }
                }
                if dirs.isEmpty {
                    Text("(không có thư mục con)")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Huỷ") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Chọn") {
                        onPick(path)
                        dismiss()
                    }
                }
            }
            .onAppear { path = currentPath }
        }
    }

    private var dirs: [FileSystemStore.Entry] {
        ((try? store.listDirectory(path)) ?? []).filter(\.isDirectory)
    }
}
