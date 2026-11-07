import SwiftUI
import QuickLook
import UniformTypeIdentifiers

/// Kiểu sắp xếp (nhớ lựa chọn qua AppStorage).
enum SortOption: Int, CaseIterable, Identifiable {
    case nameAsc, nameDesc, dateNew, dateOld, sizeAsc, sizeDesc
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .nameAsc: return "Tên A→Z"
        case .nameDesc: return "Tên Z→A"
        case .dateNew: return "Mới nhất"
        case .dateOld: return "Cũ nhất"
        case .sizeAsc: return "Nhỏ nhất"
        case .sizeDesc: return "Lớn nhất"
        }
    }
    var icon: String {
        switch self {
        case .nameAsc: return "textformat.abc"
        case .nameDesc: return "textformat.size"
        case .dateNew: return "arrow.down"
        case .dateOld: return "arrow.up"
        case .sizeAsc: return "arrow.up.right"
        case .sizeDesc: return "arrow.down.right"
        }
    }
}

/// Màn chính: duyệt cây thư mục mirror. Navigation bằng state `path`
/// (không dùng NavigationLink để state không reset khi vào thư mục con).
/// Hỗ trợ: chọn nhiều, sắp xếp, tìm trong cây, nhân đôi, thông tin, sao chép vào…
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
    @State private var showSharedFiles = false
    @State private var showInfoSheet = false
    @State private var renameTarget: FileSystemStore.Entry?
    @State private var previewURL: URL?
    @State private var previewURLs: [URL] = []
    @State private var shareURLs: [URL]?
    @State private var showTrash = false

    // Chọn nhiều + hành động hàng loạt
    @State private var selectionMode = false
    @State private var selectedPaths: Set<String> = []
    @State private var confirmDeleteSelection = false

    // Di chuyển / sao chép (1 hoặc nhiều mục)
    @State private var pendingMove: [String]?
    @State private var pendingCopy: [String]?

    // Sắp xếp + tìm kiếm + thông tin
    @AppStorage("mydSort") private var sortRaw = SortOption.nameAsc.rawValue
    @State private var searchText = ""
    @State private var infoPath: String?

    private var alertDeleteTitle: String { "Xóa \(selectedPaths.count) mục?" }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SyncStatusBanner(status: engine.status)
                List {
                    if !path.isEmpty && searchText.isEmpty {
                        Button {
                            if !path.isEmpty { _ = path.popLast() }
                        } label: {
                            Label(".. Quay lại", systemImage: "chevron.left")
                                .foregroundStyle(Theme.accent)
                        }
                    }
                    if path.isEmpty && searchText.isEmpty {
                        trashRow
                    }
                    ForEach(listing, id: \.key) { item in
                        row(item)
                    }
                    if listing.isEmpty {
                        Text(searchText.isEmpty
                             ? "Thư mục trống. Nhấn + để thêm ảnh/video, ghi chú, hoặc kéo file vào Inbox qua USB File Sharing."
                             : "Không tìm thấy \"\(searchText)\" trong thư mục này.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(path.last ?? "MyDrive")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Tìm trong thư mục này")
            .onChange(of: searchText) { _ in
                exitSelection()
            }
            .onChange(of: path) { _ in
                exitSelection()
            }
            .toolbar { toolbarContent }
            .alert("Thư mục mới", isPresented: $showNewFolder) {
                TextField("Tên thư mục", text: $newFolderName)
                Button("Tạo") { createFolder() }
                Button("Huỷ", role: .cancel) {}
            }
            .alert(alertDeleteTitle, isPresented: $confirmDeleteSelection) {
                Button("Xóa", role: .destructive) { deleteSelected() }
                Button("Huỷ", role: .cancel) {}
            } message: {
                Text("Các mục sẽ chuyển vào Đã xóa gần đây (giữ 30 ngày).")
            }
            .alert("Hộp thư Inbox", isPresented: $showInboxHint) {
                Button("Đã hiểu") {}
            } message: {
                Text("Cắm iPhone vào máy tính → Tệp (hoặc Finder) → MyDrive → kéo file vào thư mục Inbox. App sẽ tự nhập và đồng bộ các file này.")
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
            .sheet(isPresented: Binding(get: { pendingMove != nil }, set: { if !$0 { pendingMove = nil } })) {
                FolderPicker(store: store, currentPath: path, title: "Di chuyển \(pendingMove?.count ?? 0) mục") { dest in
                    moveEntries(pendingMove ?? [], to: dest)
                    pendingMove = nil
                }
            }
            .sheet(isPresented: Binding(get: { pendingCopy != nil }, set: { if !$0 { pendingCopy = nil } })) {
                FolderPicker(store: store, currentPath: path, title: "Sao chép \(pendingCopy?.count ?? 0) mục") { dest in
                    copyEntries(pendingCopy ?? [], to: dest)
                    pendingCopy = nil
                }
            }
            .sheet(isPresented: Binding(get: { shareURLs != nil }, set: { if !$0 { shareURLs = nil } })) {
                if let urls = shareURLs {
                    ShareSheet(items: urls)
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
            .sheet(isPresented: $showInfoSheet) {
                if let p = infoPath {
                    InfoView(path: p)
                }
            }
            .modifier(CommonSheets(
                showTrash: $showTrash,
                trash: trash,
                showSharedFiles: $showSharedFiles,
                onTabRetapped: {
                    exitSelection()
                    showTrash = false
                    previewURL = nil
                    shareURLs = nil
                    searchText = ""
                    path = []
                }
            ))
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if engine.status.isWorking {
                ProgressView()
            } else if searchText.isEmpty {
                Menu {
                    ForEach(SortOption.allCases) { opt in
                        Button {
                            sortRaw = opt.rawValue
                        } label: {
                            if opt.rawValue == sortRaw {
                                Label(opt.label, systemImage: "checkmark")
                            } else {
                                Text(opt.label)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            if isSelecting {
                Button(selectedPaths.isEmpty ? "Chọn tất cả" : "Bỏ chọn") {
                    toggleSelectAll()
                }
            } else if searchText.isEmpty {
                Button {
                    selectionMode = true
                    selectedPaths = []
                } label: {
                    Text("Chọn")
                }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            if !isSelecting && searchText.isEmpty {
                Menu {
                    Section("Thêm nội dung") {
                        Button { showPHPicker = true } label: { Label("Ảnh/Video…", systemImage: "photo.on.rectangle") }
                        Button { showCamera = .photo } label: { Label("Chụp ảnh", systemImage: "camera") }
                        Button { showCamera = .video } label: { Label("Quay video", systemImage: "video") }
                        Button { showNoteEditor = true } label: { Label("Ghi chú văn bản", systemImage: "square.and.pencil") }
                        Button { showDocPicker = true } label: { Label("Chọn tệp…", systemImage: "doc") }
                        Button { showFolderPicker = true } label: { Label("Chọn thư mục…", systemImage: "folder") }
                        Button { showSharedFiles = true } label: { Label("Tệp chung (từ app Files)", systemImage: "arrow.left.arrow.right.square") }
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
        ToolbarItemGroup(placement: .bottomBar) {
            if isSelecting {
                Button {
                    shareSelected()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(shareableURLs.isEmpty)
                Spacer()
                Button {
                    pendingMove = Array(selectedPaths)
                } label: {
                    Image(systemName: "folder")
                }
                .disabled(selectedPaths.isEmpty)
                Spacer()
                Button {
                    pendingCopy = Array(selectedPaths)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .disabled(selectedPaths.isEmpty)
                Spacer()
                Text("\(selectedPaths.count) mục")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(role: .destructive) {
                    confirmDeleteSelection = true
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(selectedPaths.isEmpty)
            }
        }
    }

    // MARK: - Danh sách (sắp xếp / tìm kiếm)

    private var isSelecting: Bool {
        selectionMode && searchText.isEmpty
    }

    /// Mục hiển thị: đang tìm → kết quả trong CÂY con (theo index);
    /// không → nội dung thư mục hiện tại (thư mục đứng trước, theo kiểu sắp xếp).
    private var listing: [SearchItem] {
        _ = store.changeToken
        if !searchText.isEmpty {
            let prefixKey = path.joined(separator: "/")
            let prefix = prefixKey.isEmpty ? "" : prefixKey + "/"
            return IndexStore.shared.allNodes().compactMap { pair in
                let (key, node) = pair
                guard key != prefixKey, key.hasPrefix(prefix) else { return nil }
                guard node.name.localizedCaseInsensitiveContains(searchText) else { return nil }
                return SearchItem(
                    key: key,
                    entry: .init(name: node.name, isDirectory: node.isDirectory,
                                 size: node.size, modified: node.modified ?? Date()),
                    relativePath: String(key.dropFirst(prefix.count))
                )
            }
            .sorted {
                if $0.entry.isDirectory != $1.entry.isDirectory { return $0.entry.isDirectory }
                return $0.entry.name.localizedStandardCompare($1.entry.name) == .orderedAscending
            }
        }
        let list = (try? store.listDirectory(path)) ?? []
        let folders = list.filter(\.isDirectory)
        let files = list.filter { !$0.isDirectory }
        let opt = SortOption(rawValue: sortRaw) ?? .nameAsc
        func sorted(_ arr: [FileSystemStore.Entry]) -> [FileSystemStore.Entry] {
            switch opt {
            case .nameAsc: return arr.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            case .nameDesc: return arr.sorted { $0.name.localizedStandardCompare($1.name) == .orderedDescending }
            case .dateNew: return arr.sorted { $0.modified > $1.modified }
            case .dateOld: return arr.sorted { $0.modified < $1.modified }
            case .sizeAsc: return arr.sorted { $0.size < $1.size }
            case .sizeDesc: return arr.sorted { $0.size > $1.size }
            }
        }
        return (sorted(folders) + sorted(files)).map {
            SearchItem(key: (path + [$0.name]).joined(separator: "/"),
                       entry: $0, relativePath: $0.name)
        }
    }

    private struct SearchItem: Identifiable, Hashable {
        let key: String
        let entry: FileSystemStore.Entry
        let relativePath: String
        var id: String { key }
    }

    // MARK: - Row

    @ViewBuilder
    private func row(_ item: SearchItem) -> some View {
        let entry = item.entry
        let comps = item.key.components
        let childPath = comps

        if isSelecting {
            Button {
                toggleSelection(item.key)
            } label: {
                HStack {
                    Image(systemName: selectedPaths.contains(item.key) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selectedPaths.contains(item.key) ? Theme.accent : Color.secondary)
                        .font(.body)
                    Image(systemName: entry.isDirectory ? "folder.fill" : icon(for: entry.name))
                        .foregroundStyle(entry.isDirectory ? Theme.accent : Color.secondary)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.name)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if !searchText.isEmpty {
                            Text(item.relativePath)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    if !entry.isDirectory {
                        Text(ByteFmt.string(entry.size))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } else {
            HStack {
                Image(systemName: entry.isDirectory ? "folder.fill" : icon(for: entry.name))
                    .foregroundStyle(entry.isDirectory ? Theme.accent : Color.secondary)
                    .frame(width: 28)
                if entry.isDirectory {
                    Button {
                        path = comps
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
                        openFile(comps)
                    } label: {
                        HStack {
                            Text(entry.name)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer()
                            Text(ByteFmt.string(entry.size))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    deleteEntry(entry, comps)
                } label: {
                    Label("Xóa", systemImage: "trash")
                }
            }
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                if !entry.isDirectory {
                    Button {
                        shareURLs = [store.url(for: comps)]
                    } label: {
                        Label("Chia sẻ", systemImage: "square.and.arrow.up")
                    }
                    .tint(Theme.accent)
                }
            }
            .contextMenu { menuItems(entry, comps) }
        }
    }

    @ViewBuilder
    private func menuItems(_ entry: FileSystemStore.Entry, _ childPath: [String]) -> some View {
        Button {
            selectionMode = true
            selectedPaths = [childPath.joined(separator: "/")]
        } label: {
            Label("Chọn", systemImage: "checkmark.circle")
        }
        if !entry.isDirectory {
            Button {
                shareURLs = [store.url(for: childPath)]
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
            pendingMove = [childPath.joined(separator: "/")]
        } label: {
            Label("Di chuyển", systemImage: "arrowshape.turn.up.right")
        }
        Button {
            pendingCopy = [childPath.joined(separator: "/")]
        } label: {
            Label("Sao chép vào…", systemImage: "doc.on.doc")
        }
        Button {
            duplicateEntry(entry, childPath)
        } label: {
            Label("Nhân đôi", systemImage: "plus.square.on.square")
        }
        Button {
            infoPath = childPath.joined(separator: "/")
            showInfoSheet = true
        } label: {
            Label("Thông tin", systemImage: "info.circle")
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

    // MARK: - Mở file (preview danh sách cùng thư mục)

    private func openFile(_ comps: [String]) {
        let url = store.url(for: comps)
        if FileManager.default.fileExists(atPath: url.path) {
            // Danh sách file cùng thư mục (đã tải về) → vuốt trái/phải chuyển file.
            let dirKey = comps.dropLast().joined(separator: "/")
            let files = IndexStore.shared.allNodes().filter { pair in
                guard !pair.node.isDirectory else { return false }
                let parent = pair.path.components.dropLast().joined(separator: "/")
                return parent == dirKey
                    && FileManager.default.fileExists(atPath: store.url(for: pair.path.components).path)
            }
            previewURLs = files
                .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
                .map { store.url(for: $0.path.components) }
            previewURL = url
        } else {
            // File chưa tải về (mới khôi phục) — bảo engine kéo về trước.
            engine.syncNow()
        }
    }

    // MARK: - Chọn nhiều

    private func toggleSelection(_ key: String) {
        if selectedPaths.contains(key) {
            selectedPaths.remove(key)
        } else {
            selectedPaths.insert(key)
        }
    }

    private func toggleSelectAll() {
        if selectedPaths.count >= listing.count {
            selectedPaths = []
        } else {
            selectedPaths = Set(listing.map(\.key))
        }
    }

    private func exitSelection() {
        selectionMode = false
        selectedPaths = []
    }

    private var shareableURLs: [URL] {
        selectedPaths
            .map { store.url(for: $0.components) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func shareSelected() {
        let urls = shareableURLs
        guard !urls.isEmpty else { return }
        shareURLs = urls
    }

    private func deleteSelected() {
        for key in selectedPaths {
            let comps = key.components
            let p = key
            try? store.remove(at: comps)
            Journal.shared.enqueue(.delete(path: p, snapshot: nil))
        }
        exitSelection()
        engine.triggerSync()
    }

    private func moveEntries(_ keys: [String], to dest: [String]) {
        for key in keys {
            let comps = key.components
            guard let name = comps.last else { continue }
            let to = dest + [name]
            guard comps != to else { continue }
            try? store.move(from: comps, to: to)
            moveIndexEntries(from: key, to: to.joined(separator: "/"), isDirectory: isDirectory(key), newName: name)
            Journal.shared.enqueue(.move(from: key, to: to.joined(separator: "/")))
        }
        exitSelection()
        engine.triggerSync()
    }

    private func isDirectory(_ key: String) -> Bool {
        IndexStore.shared.node(at: key)?.isDirectory ?? false
    }

    private func copyEntries(_ keys: [String], to dest: [String]) {
        for key in keys {
            let comps = key.components
            guard let name = comps.last else { continue }
            var newName = name
            var n = 2
            while store.exists(at: dest + [newName])
                || IndexStore.shared.node(at: (dest + [newName]).joined(separator: "/")) != nil {
                newName = uniquedCopyName(for: name, n)
                n += 1
                if n > 999 { break }
            }
            let target = dest + [newName]
            if isDirectory(key) {
                try? store.copyDirectory(from: store.url(for: comps), to: target)
                registerImportedFolder(target)
            } else {
                try? store.copyFile(from: store.url(for: comps), to: target)
                registerImportedFile(target)
            }
        }
        exitSelection()
        engine.triggerSync()
    }

    private func uniquedCopyName(for name: String, _ n: Int) -> String {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        return ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)"
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

    private func deleteEntry(_ entry: FileSystemStore.Entry, _ childPath: [String]) {
        // FileSystemStore.remove chuyển dữ liệu + đăng ký entry "Đã xóa gần đây"
        // (kèm snapshot index). Engine đọc snapshot từ TrashStore khi xử lý op;
        // part trên Drive do engine trash qua op delete.
        let p = childPath.joined(separator: "/")
        try? store.remove(at: childPath)
        Journal.shared.enqueue(.delete(path: p, snapshot: nil))
        engine.triggerSync()
    }

    /// Nhân đôi: copy trong cùng thư mục với tên "tên (2).ext" + đăng ký sync.
    private func duplicateEntry(_ entry: FileSystemStore.Entry, _ childPath: [String]) {
        guard let name = childPath.last else { return }
        var newName = name
        var n = 2
        while store.exists(at: path + [newName])
            || IndexStore.shared.node(at: (path + [newName]).joined(separator: "/")) != nil {
            newName = uniquedCopyName(for: name, n)
            n += 1
            if n > 999 { break }
        }
        let target = path + [newName]
        if entry.isDirectory {
            try? store.copyDirectory(from: store.url(for: childPath), to: target)
            registerImportedFolder(target)
        } else {
            try? store.copyFile(from: store.url(for: childPath), to: target)
            registerImportedFile(target)
        }
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

// MARK: - Sheet chung (trash, tệp chung, tab-retapped)

/// Tách modifier để compiler không phải type-check chuỗi modifier quá dài.
struct CommonSheets: ViewModifier {
    @Binding var showTrash: Bool
    @ObservedObject var trash: TrashStore
    @Binding var showSharedFiles: Bool
    let onTabRetapped: () -> Void

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showTrash) {
                RecentlyDeletedView(trash: trash)
            }
            .sheet(isPresented: $showSharedFiles) {
                NavigationStack { SharedFilesView() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .myDriveTabRetapped)) { note in
                // Bấm lại tab Tệp khi đang ở thư mục con → về root (như app Files).
                guard (note.object as? Int) == 0 else { return }
                onTabRetapped()
            }
    }
}

// MARK: - Thông tin (như "Get Info" của Files)

/// Sheet thông tin 1 file/thư mục: loại, kích thước, ngày sửa, parts + account,
/// vị trí. Đọc từ index (đúng trạng thái sync).
struct InfoView: View {
    let path: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if let node = IndexStore.shared.node(at: path) {
                    LabeledContent("Tên", value: node.name)
                    LabeledContent("Loại", value: node.isDirectory ? "Thư mục" : "Tệp")
                    if !node.isDirectory {
                        LabeledContent("Kích thước", value: ByteFmt.string(node.size))
                    }
                    LabeledContent("Ngày sửa", value: Self.dateText(node.modified ?? Date()))
                    LabeledContent("Vị trí", value: path)
                    if let parts = node.parts, !parts.isEmpty {
                        Section("Phần trên Drive") {
                            ForEach(parts.sorted { $0.index < $1.index }, id: \.index) { part in
                                LabeledContent("Phần \(part.index)") {
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text(part.accountEmail.isEmpty ? "—" : part.accountEmail)
                                            .font(.caption)
                                        Text(part.driveFileId == nil ? "chưa tải lên" : "đã tải lên")
                                            .font(.caption)
                                            .foregroundStyle(part.driveFileId == nil ? Color.orange : Color.green)
                                    }
                                }
                            }
                        }
                    }
                } else {
                    Text("Mục này chưa được đồng bộ (chưa có trong chỉ mục).")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Thông tin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") { dismiss() }
                }
            }
        }
    }

    private static func dateText(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df.string(from: date)
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
