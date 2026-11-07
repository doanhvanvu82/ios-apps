import SwiftUI
import QuickLook
import UniformTypeIdentifiers

/// Màn chính: duyệt cây thư mục mirror. Navigation bằng state `path`
/// (không dùng NavigationLink để state không reset khi vào thư mục con).
struct FilesView: View {
    @StateObject private var store = FileSystemStore.shared
    @StateObject private var engine = SyncEngine.shared
    @StateObject private var accounts = AccountStore.shared

    @State private var path: [String] = []
    @State private var showNewFolder = false
    @State private var newFolderName = ""
    @State private var showPHPicker = false
    @State private var showCamera: CameraMode?
    @State private var showNoteEditor = false
    @State private var showDocPicker = false
    @State private var showInboxHint = false
    @State private var renameTarget: FileSystemStore.Entry?
    @State private var moveTarget: FileSystemStore.Entry?
    @State private var previewURL: URL?
    @State private var shareURL: URL?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SyncStatusBanner(status: engine.status)
                List {
                    if !path.isEmpty {
                        Button {
                            if !path.isEmpty { _ = path.popLast() }
                        } label: {
                            Label(".. Quay lại", systemImage: "chevron.left")
                                .foregroundStyle(Theme.accent)
                        }
                    }
                    ForEach(entries) { entry in
                        row(entry)
                    }
                    if entries.isEmpty {
                        Text("Thư mục trống. Nhấn + để thêm ảnh/video, ghi chú, hoặc kéo file vào Inbox qua USB File Sharing.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(path.last ?? "MyDrive")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if engine.status.isWorking { ProgressView() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Section("Thêm nội dung") {
                            Button { showPHPicker = true } label: { Label("Ảnh/Video…", systemImage: "photo.on.rectangle") }
                            Button { showCamera = .photo } label: { Label("Chụp ảnh", systemImage: "camera") }
                            Button { showCamera = .video } label: { Label("Quay video", systemImage: "video") }
                            Button { showNoteEditor = true } label: { Label("Ghi chú văn bản", systemImage: "square.and.pencil") }
                            Button { showDocPicker = true } label: { Label("Chọn tệp (thường bị iOS chặn)", systemImage: "doc") }
                            Button { showInboxHint = true } label: { Label("Hộp thư Inbox (USB)", systemImage: "tray.and.arrow.down") }
                        }
                        Section {
                            Button { showNewFolder = true } label: { Label("Thư mục mới", systemImage: "folder.badge.plus") }
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .alert("Thư mục mới", isPresented: $showNewFolder) {
                TextField("Tên thư mục", text: $newFolderName)
                Button("Tạo") { createFolder() }
                Button("Huỷ", role: .cancel) {}
            }
            .alert("Hộp thư Inbox", isPresented: $showInboxHint) {
                Button("Đã hiểu") {}
            } message: {
                Text("Cắm iPhone vào máy tính → Tệp (hoặc Finder) → MyDrive → kéo file vào thư mục MyDrive/Inbox. App sẽ tự nhập và đồng bộ các file này.")
            }
            .sheet(isPresented: $showPHPicker) {
                PhotoPicker { items in importPhotos(items) }
                    .ignoresSafeArea()
            }
            .sheet(isPresented: Binding(
                get: { showCamera != nil },
                set: { if !$0 { showCamera = nil } }
            )) {
                CameraPicker(mode: showCamera ?? .photo) { result in
                    importCamera(result)
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showNoteEditor) {
                NoteEditor { name, text in importNote(name: name, text: text) }
                    .ignoresSafeArea()
            }
            .sheet(isPresented: $showDocPicker) {
                DocumentPicker { urls in importDocuments(urls) }
                    .ignoresSafeArea()
            }
            .sheet(item: $renameTarget) { entry in
                RenameSheet(currentName: entry.name) { newName in
                    commitRename(entry, newName)
                }
            }
            .sheet(item: $moveTarget) { entry in
                FolderPicker(store: store, currentPath: path, title: "Di chuyển \"\(entry.name)\"") { dest in
                    moveEntry(entry, to: dest)
                }
            }
            .sheet(isPresented: Binding(get: { previewURL != nil }, set: { if !$0 { previewURL = nil } })) {
                if let url = previewURL {
                    QuickLookView(url: url)
                        .ignoresSafeArea()
                }
            }
            .sheet(isPresented: Binding(get: { shareURL != nil }, set: { if !$0 { shareURL = nil } })) {
                if let url = shareURL {
                    ShareSheet(items: [url])
                }
            }
        }
    }

    private var entries: [FileSystemStore.Entry] {
        (try? store.listDirectory(path)) ?? []
    }

    // MARK: - Row

    @ViewBuilder
    private func row(_ entry: FileSystemStore.Entry) -> some View {
        let childPath = path + [entry.name]
        HStack {
            Image(systemName: entry.isDirectory ? "folder.fill" : icon(for: entry.name))
                .foregroundStyle(entry.isDirectory ? Theme.accent : Color.secondary)
                .frame(width: 28)
            if entry.isDirectory {
                Button {
                    path.append(entry.name)
                } label: {
                    HStack {
                        Text(entry.name)
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            } else {
                Button {
                    let url = store.url(for: childPath)
                    if FileManager.default.fileExists(atPath: url.path) {
                        previewURL = url
                    } else {
                        // File chưa tải về (mới khôi phục) — bảo engine kéo về trước.
                        engine.syncNow()
                    }
                } label: {
                    HStack {
                        Text(entry.name)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .contextMenu { menuItems(entry, childPath) }
    }

    @ViewBuilder
    private func menuItems(_ entry: FileSystemStore.Entry, _ childPath: [String]) -> some View {
        if !entry.isDirectory {
            Button {
                shareURL = store.url(for: childPath)
            } label: {
                Label("Chia sẻ", systemImage: "square.and.arrow.up")
            }
        }
        Button {
            renameTarget = entry
        } label: {
            Label("Đổi tên", systemImage: "pencil")
        }
        Button {
            moveTarget = entry
        } label: {
            Label("Di chuyển", systemImage: "arrowshape.turn.up.right")
        }
        Divider()
        Button(role: .destructive) {
            deleteEntry(entry, childPath)
        } label: {
            Label("Xóa (vào thùng rác Drive)", systemImage: "trash")
        }
    }

    private func icon(for name: String) -> String {
        switch (name as NSString).pathExtension.lowercased() {
        case "jpg", "jpeg", "png", "gif", "heic", "webp": return "photo"
        case "mp4", "mov", "mkv", "avi", "webm": return "video"
        case "mp3", "m4a", "wav", "flac": return "music.note"
        case "pdf": return "doc.richtext"
        case "txt", "md": return "doc.plaintext"
        case "zip", "rar", "7z", "tar", "gz": return "doc.zipper"
        default: return "doc"
        }
    }

    // MARK: - Actions (local-first + journal)

    private func createFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name != "Inbox" || !path.isEmpty else { return }
        let newPath = path + [name]
        try? store.makeDirectory(newPath)
        let p = newPath.joined(separator: "/")
        IndexStore.shared.upsert(path: p, node: .init(
            name: name, isDirectory: true, size: 0, modified: Date(), parts: nil, rev: 1, driveFolderId: nil
        ))
        Journal.shared.enqueue(.createFolder(path: p))
        engine.triggerSync()
        newFolderName = ""
    }

    private func commitRename(_ target: FileSystemStore.Entry, _ newName: String) {
        guard newName != target.name else { return }
        let from = path + [target.name]
        let to = path + [newName]
        try? store.move(from: from, to: to)
        moveIndexEntries(from: from.joined(separator: "/"), to: to.joined(separator: "/"), isDirectory: target.isDirectory, newName: newName)
        Journal.shared.enqueue(.rename(from: from.joined(separator: "/"), to: to.joined(separator: "/")))
        engine.triggerSync()
    }

    private func moveEntry(_ entry: FileSystemStore.Entry, to dest: [String]) {
        let from = path + [entry.name]
        let to = dest + [entry.name]
        guard from != to else { return }
        try? store.move(from: from, to: to)
        moveIndexEntries(from: from.joined(separator: "/"), to: to.joined(separator: "/"), isDirectory: entry.isDirectory, newName: entry.name)
        Journal.shared.enqueue(.move(from: from.joined(separator: "/"), to: to.joined(separator: "/")))
        engine.triggerSync()
    }

    private func deleteEntry(_ entry: FileSystemStore.Entry, _ childPath: [String]) {
        // Snapshot node TRƯỚC khi remove (engine cần parts để trash trên Drive).
        let p = childPath.joined(separator: "/")
        let snapshot = IndexStore.shared.node(at: p)
        try? store.remove(at: childPath)
        IndexStore.shared.remove(path: p)
        if entry.isDirectory {
            IndexStore.shared.removeTree(prefix: p)
        }
        Journal.shared.enqueue(.delete(path: p, snapshot: snapshot))
        engine.triggerSync()
    }

    /// Di chuyển node trong index (giữ placement — không re-upload).
    private func moveIndexEntries(from: String, to: String, isDirectory: Bool, newName: String) {
        let idx = IndexStore.shared
        if var node = idx.node(at: from) {
            node.name = newName
            idx.upsert(path: to, node: node)
            idx.remove(path: from)
            if isDirectory {
                for (childPath, childNode) in idx.allNodes() where childPath.hasPrefix(from + "/") {
                    let newChild = to + childPath.dropFirst(from.count)
                    idx.upsert(path: newChild, node: childNode)
                    idx.remove(path: childPath)
                }
            }
        }
    }

    // MARK: - Import

    private func importPhotos(_ items: [PhotoPicker.Item]) {
        let dir = path
        Task {
            for item in items {
                if let url = try? await item.loadFileURL() {
                    let name = item.suggestedName ?? url.lastPathComponent
                    let dest = dir + [name]
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    try? store.copyFile(from: url, to: dest)
                    registerImportedFile(dest)
                }
            }
            engine.triggerSync()
        }
    }

    private func importCamera(_ result: CameraResult?) {
        guard let result else { return }
        let dest: [String]
        switch result {
        case let .image(image):
            guard let data = image.jpegData(compressionQuality: 0.9) else { return }
            dest = path + [Self.timestampName("jpg")]
            try? store.write(data: data, to: dest)
        case let .video(url):
            dest = path + [Self.timestampName("mov")]
            try? store.copyFile(from: url, to: dest)
        }
        registerImportedFile(dest)
        engine.triggerSync()
    }

    private static func timestampName(_ ext: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date()) + "." + ext
    }

    private func importNote(name: String, text: String) {
        let fileName = name.hasSuffix(".txt") ? name : name + ".txt"
        let dest = path + [fileName]
        try? store.write(data: Data(text.utf8), to: dest)
        registerImportedFile(dest)
        engine.triggerSync()
    }

    private func importDocuments(_ urls: [URL]) {
        let dir = path
        for url in urls {
            let dest = dir + [url.lastPathComponent]
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            try? store.copyFile(from: url, to: dest)
            registerImportedFile(dest)
        }
        engine.triggerSync()
    }

    /// Đăng ký file vừa nhập vào index (chưa có placement → SyncEngine tự chọn account).
    private func registerImportedFile(_ dest: [String]) {
        let size = store.fileSize(at: dest) ?? 0
        let p = dest.joined(separator: "/")
        IndexStore.shared.upsert(path: p, node: .init(
            name: dest.last ?? "", isDirectory: false, size: size,
            modified: Date(), parts: nil, rev: 1, driveFolderId: nil
        ))
        Journal.shared.enqueue(.uploadFile(path: p))
    }
}
