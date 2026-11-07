import SwiftUI
import QuickLook
import UniformTypeIdentifiers

/// Màn chính: duyệt cây thư mục mirror. Navigation bằng state `path`
/// (không dùng NavigationLink để state không reset khi vào thư mục con).
struct FilesView: View {
    @StateObject private var store = FileSystemStore.shared
    @StateObject private var engine = SyncEngine.shared
    @StateObject private var accounts = AccountStore.shared
    @StateObject private var trash = TrashStore.shared

    @State private var path: [String] = []
    @State private var showNewFolder = false
    @State private var newFolderName = ""
    @State private var showPHPicker = false
    @State private var showCamera: CameraMode?
    @State private var showNoteEditor = false
    @State private var showDocPicker = false
    @State private var showFolderPicker = false
    @State private var showInboxHint = false
    @State private var renameTarget: FileSystemStore.Entry?
    @State private var moveTarget: FileSystemStore.Entry?
    @State private var previewURL: URL?
    @State private var previewURLs: [URL] = []
    @State private var shareURL: URL?
    @State private var showTrash = false

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
                    if path.isEmpty {
                        trashRow
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
                            Button { showDocPicker = true } label: { Label("Chọn tệp…", systemImage: "doc") }
                            Button { showFolderPicker = true } label: { Label("Chọn thư mục…", systemImage: "folder") }
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
            .sheet(isPresented: $showFolderPicker) {
                FolderDocumentPicker { url in importDroppedFolder(url) }
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
                    QuickLookView(
                        urls: previewURLs,
                        startIndex: previewURLs.firstIndex(of: url) ?? 0,
                        onDone: { previewURL = nil }
                    )
                    .ignoresSafeArea()
                }
            }
            .sheet(isPresented: Binding(get: { shareURL != nil }, set: { if !$0 { shareURL = nil } })) {
                if let url = shareURL {
                    ShareSheet(items: [url])
                }
            }
            .navigationDestination(isPresented: Binding(
                get: { showTrash },
                set: { showTrash = $0 }
            )) {
                RecentlyDeletedView(trash: trash)
            }
        }
    }

    /// Ô "Đã xóa gần đây" (giống app Files: chỉ hiện ở gốc Tệp).
    private var trashRow: some View {
        Button {
            trash.purgeExpired()
            showTrash = true
        } label: {
            HStack {
                Image(systemName: "trash")
                    .foregroundStyle(Color.secondary)
                    .frame(width: 28)
                Text("Đã xóa gần đây")
                    .foregroundStyle(.primary)
                Spacer()
                if !trash.items.isEmpty {
                    Text("\(trash.items.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var entries: [FileSystemStore.Entry] {
        _ = store.changeToken   // đăng ký quan sát — mirror đổi là list tự reload
        return (try? store.listDirectory(path)) ?? []
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
                        // Danh sách file cùng thư mục (đã tải về) → vuốt trái/phải
                        // chuyển file trong QuickLook như app Files.
                        previewURLs = entries
                            .filter { !$0.isDirectory && FileManager.default.fileExists(atPath: store.url(for: path + [$0.name]).path) }
                            .map { store.url(for: path + [$0.name]) }
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
            Label("Xóa", systemImage: "trash")
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
        // FileSystemStore.remove chuyển dữ liệu + đăng ký entry "Đã xóa gần đây"
        // (kèm snapshot index). Engine đọc snapshot từ TrashStore khi xử lý op;
        // part trên Drive do engine trash qua op delete.
        let p = childPath.joined(separator: "/")
        try? store.remove(at: childPath)
        Journal.shared.enqueue(.delete(path: p, snapshot: nil))
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

    /// Thư mục người dùng chọn (picker mở tại chỗ — URL gốc security-scoped):
    /// copy cả cây vào mirror trong lúc còn quyền truy cập, đăng ký index +
    /// journal theo từng cấp. KHÔNG xoá srcURL — đó là thư mục thật của người dùng.
    private func importDroppedFolder(_ srcURL: URL?) {
        guard let srcURL else { return }
        let scoped = srcURL.startAccessingSecurityScopedResource()
        defer { if scoped { srcURL.stopAccessingSecurityScopedResource() } }
        let dir = path
        var name = srcURL.lastPathComponent
        var n = 2
        while store.exists(at: dir + [name])
            || IndexStore.shared.node(at: (dir + [name]).joined(separator: "/")) != nil {
            name += " (\(n))"
            n += 1
            if n > 999 { break }
        }
        let dest = dir + [name]
        do {
            try store.copyDirectory(from: srcURL, to: dest)
        } catch {
            AppLog.log("import", "❌ Không copy được thư mục \(name): \(error.localizedDescription)")
            return
        }
        registerImportedFolder(dest)
        engine.triggerSync()
    }

    /// Đăng ký cả cây thư mục vừa nhập (thư mục → createFolder, file → uploadFile).
    private func registerImportedFolder(_ dirPath: [String]) {
        let index = IndexStore.shared
        let fm = FileManager.default
        let dirURL = store.url(for: dirPath)
        let dirKey = dirPath.joined(separator: "/")
        index.upsert(path: dirKey, node: .init(
            name: dirPath.last ?? "", isDirectory: true, size: 0, modified: Date(), parts: nil, rev: 1, driveFolderId: nil
        ))
        Journal.shared.enqueue(.createFolder(path: dirKey))

        let enumerator = fm.enumerator(at: dirURL, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey])
        while let next = enumerator?.nextObject() as? URL {
            let isDir = ((try? next.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory) ?? false
            guard let rel = store.relativePath(of: next) else { continue }
            if isDir {
                index.upsert(path: rel.joined(separator: "/"), node: .init(
                    name: rel.last ?? "", isDirectory: true, size: 0, modified: Date(), parts: nil, rev: 1, driveFolderId: nil
                ))
                Journal.shared.enqueue(.createFolder(path: rel.joined(separator: "/")))
            } else {
                let size = ((try? next.resourceValues(forKeys: [.fileSizeKey]))?.fileSize).map(Int64.init) ?? 0
                let p = rel.joined(separator: "/")
                index.upsert(path: p, node: .init(
                    name: rel.last ?? "", isDirectory: false, size: size, modified: Date(), parts: nil, rev: 1, driveFolderId: nil
                ))
                Journal.shared.enqueue(.uploadFile(path: p))
            }
        }
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

/// "Đã xóa gần đây" — liệt kê các mục đã xóa (30 ngày tự dọn), khôi phục hoặc
/// xóa hẳn. Giống app Files.
struct RecentlyDeletedView: View {
    @StateObject private var trash: TrashStore
    @State private var confirmPurgeAll = false
    @State private var confirmPurge: TrashStore.Item?

    init(trash: TrashStore) {
        _trash = StateObject(wrappedValue: trash)
    }

    var body: some View {
        List {
            if trash.items.isEmpty {
                Text("Không có mục nào đã xóa trong 30 ngày.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(trash.items) { item in
                row(item)
            }
        }
        .navigationTitle("Đã xóa gần đây")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !trash.items.isEmpty {
                    Button(role: .destructive) {
                        confirmPurgeAll = true
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
        }
        .onAppear { trash.purgeExpired() }
        .alert("Dọn sạch thùng rác?", isPresented: $confirmPurgeAll) {
            Button("Dọn sạch", role: .destructive) { trash.purgeAll() }
            Button("Huỷ", role: .cancel) {}
        } message: {
            Text("\(trash.items.count) mục sẽ bị xóa vĩnh viễn.")
        }
        .alert("Xóa vĩnh viễn?", isPresented: Binding(
            get: { confirmPurge != nil },
            set: { if !$0 { confirmPurge = nil } }
        )) {
            Button("Xóa", role: .destructive) {
                if let item = confirmPurge { trash.purge(item) }
                confirmPurge = nil
            }
            Button("Huỷ", role: .cancel) { confirmPurge = nil }
        } message: {
            Text("\"\(confirmPurge?.node.name ?? "")\" sẽ bị xóa vĩnh viễn khỏi thiết bị và Google Drive.")
        }
    }

    @ViewBuilder
    private func row(_ item: TrashStore.Item) -> some View {
        HStack {
            Image(systemName: item.node.isDirectory ? "folder.fill" : "doc")
                .foregroundStyle(item.node.isDirectory ? Theme.accent : Color.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.node.name)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(Self.subtitle(item))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .contextMenu {
            Button {
                trash.restore(item)
            } label: {
                Label("Khôi phục", systemImage: "arrow.uturn.backward")
            }
            Button(role: .destructive) {
                confirmPurge = item
            } label: {
                Label("Xóa vĩnh viễn", systemImage: "trash.fill")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                confirmPurge = item
            } label: {
                Label("Xóa", systemImage: "trash")
            }
            Button {
                trash.restore(item)
            } label: {
                Label("Khôi phục", systemImage: "arrow.uturn.backward")
            }
            .tint(Theme.accent)
        }
    }

    private static func subtitle(_ item: TrashStore.Item) -> String {
        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .short
        let when = df.string(from: item.deletedAt)
        var parts = ["Đã xóa \(when)"]
        if item.node.isDirectory, !item.children.isEmpty {
            parts.append("\(item.children.count) mục bên trong")
        }
        parts.append("còn \(item.daysLeft) ngày")
        return parts.joined(separator: " · ")
    }
}
