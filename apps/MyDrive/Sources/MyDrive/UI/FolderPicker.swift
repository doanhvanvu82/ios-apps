import SwiftUI

/// Chọn thư mục trong mirror: danh sách bấm để đi xuống, nút "Chọn" xác nhận.
/// Dùng cho di chuyển file/thư mục (closure `dirs` mặc định) và mở rộng sau
/// (vd chọn đích nhập file — truyền closure riêng).
struct FolderPicker: View {
    @StateObject var store: FileSystemStore
    let currentPath: [String]
    let title: String
    var dirs: ([String]) -> [FileSystemStore.Entry]
    var onPick: ([String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var path: [String] = []

    init(
        store: FileSystemStore,
        currentPath: [String],
        title: String,
        dirs: @escaping ([String]) -> [FileSystemStore.Entry] = { path in
            ((try? FileSystemStore.shared.listDirectory(path)) ?? []).filter(\.isDirectory)
        },
        onPick: @escaping ([String]) -> Void
    ) {
        _store = StateObject(wrappedValue: store)
        self.currentPath = currentPath
        self.title = title
        self.dirs = dirs
        self.onPick = onPick
    }

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
                ForEach(self.dirs(path)) { entry in
                    Button {
                        path.append(entry.name)
                    } label: {
                        Label(entry.name, systemImage: "folder.fill")
                            .foregroundStyle(Theme.accent)
                    }
                }
                if self.dirs(path).isEmpty {
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
}
