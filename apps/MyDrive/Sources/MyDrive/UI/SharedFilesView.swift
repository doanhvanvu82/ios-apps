import SwiftUI

/// Tab "Được chia sẻ": thấy luôn nội dung bãi trung chuyển Documents/Shared
/// (dùng chung với app Files, KHÔNG đồng bộ). Nhập kho qua "Di chuyển vào MyDrive".
struct SharedTabView: View {
    var body: some View {
        NavigationStack {
            SharedFilesView()
        }
    }
}

/// Bãi trung chuyển chung với app Files: Documents/Shared (kế bên Logs).
/// Người dùng copy file/thư mục từ Files vào đây — nội dung KHÔNG đồng bộ.
/// Vào tab này thấy luôn các mục; chọn rồi "Di chuyển vào MyDrive" (chọn đích)
/// — lúc đó mới nhập kho: move vào mirror + đăng ký index/journal + sync.
struct SharedFilesView: View {
    @State private var items: [FileSystemStore.Entry] = []
    @State private var selectionMode = false
    @State private var selected: Set<String> = []
    @State private var pendingMove: [String]?
    @State private var confirmDelete = false
    @State private var confirmDeleteTarget: String?
    @State private var previewURL: URL?
    @StateObject private var store = FileSystemStore.shared

    var body: some View {
        List {
            if items.isEmpty {
                Text("Trống. Mở app Files → On My iPhone → MyDrive → Shared (hoặc kéo thả qua USB) để bỏ file vào đây. Nội dung ở đây KHÔNG đồng bộ lên Drive — chọn mục rồi bấm \"Di chuyển vào MyDrive\" để nhập kho.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(items) { entry in
                row(entry)
            }
        }
        .navigationTitle("Được chia sẻ")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .refreshable { reload() }
        .onAppear { reload() }
        .sheet(isPresented: Binding(get: { pendingMove != nil }, set: { if !$0 { pendingMove = nil } })) {
            FolderPicker(store: store, currentPath: [], title: "Di chuyển \(pendingMove?.count ?? 0) mục vào MyDrive") { dest in
                moveSelected(to: dest)
                pendingMove = nil
            }
        }
        .alert("Xóa vĩnh viễn?", isPresented: Binding(
            get: { confirmDeleteTarget != nil || confirmDelete },
            set: { if !$0 { confirmDeleteTarget = nil; confirmDelete = false } }
        )) {
            Button("Xóa", role: .destructive) {
                if let t = confirmDeleteTarget {
                    try? FileManager.default.removeItem(at: AppPaths.sharedFiles.appendingPathComponent(t))
                } else {
                    for name in selected {
                        try? FileManager.default.removeItem(at: AppPaths.sharedFiles.appendingPathComponent(name))
                    }
                }
                selected = []
                selectionMode = false
                reload()
            }
            Button("Huỷ", role: .cancel) {
                confirmDeleteTarget = nil
                confirmDelete = false
            }
        } message: {
            Text("Xóa khỏi Shared — không liên quan Drive (mục chưa từng đồng bộ).")
        }
        .sheet(isPresented: Binding(
            get: { previewURL != nil },
            set: { if !$0 { previewURL = nil } }
        )) {
            if let url = previewURL {
                QuickLookView(urls: [url], onDone: { previewURL = nil })
                    .ignoresSafeArea()
            }
        }
    }

    /// Nút "Di chuyển vào MyDrive" — hành động chính của tab.
    private var moveButton: some View {
        Button {
            pendingMove = selectionMode && !selected.isEmpty ? Array(selected) : items.map(\.name)
        } label: {
            Label("Di chuyển vào MyDrive", systemImage: "arrow.right.circle")
        }
        .disabled(items.isEmpty)
    }

    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if selectionMode {
                Button(selected.isEmpty ? "Chọn tất cả" : "Bỏ chọn") {
                    if selected.count >= items.count { selected = [] } else { selected = Set(items.map(\.name)) }
                }
            } else {
                Button("Chọn") {
                    selectionMode = true
                    selected = []
                }
            }
            moveButton
        }
    }

    @ViewBuilder
    private func row(_ entry: FileSystemStore.Entry) -> some View {
        if selectionMode {
            Button {
                if selected.contains(entry.name) { selected.remove(entry.name) } else { selected.insert(entry.name) }
            } label: {
                HStack {
                    Image(systemName: selected.contains(entry.name) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected.contains(entry.name) ? Theme.accent : Color.secondary)
                    Image(systemName: entry.isDirectory ? "folder.fill" : "doc")
                        .foregroundStyle(entry.isDirectory ? Theme.accent : Color.secondary)
                        .frame(width: 26)
                    Text(entry.name).foregroundStyle(.primary).lineLimit(1)
                    Spacer()
                    if !entry.isDirectory {
                        Text(ByteFmt.string(entry.size)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        } else {
            HStack {
                Image(systemName: entry.isDirectory ? "folder.fill" : "doc")
                    .foregroundStyle(entry.isDirectory ? Theme.accent : Color.secondary)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name).foregroundStyle(.primary).lineLimit(1)
                    Text(entry.isDirectory ? "Thư mục" : ByteFmt.string(entry.size))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if !entry.isDirectory {
                    previewURL = AppPaths.sharedFiles.appendingPathComponent(entry.name)
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    confirmDeleteTarget = entry.name
                } label: {
                    Label("Xóa", systemImage: "trash")
                }
            }
        }
    }

    private func reload() {
        _ = store.changeToken
        let list = (try? FileManager.default.contentsOfDirectory(
            at: AppPaths.sharedFiles,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        )) ?? []
        items = list
            .filter { $0.lastPathComponent != ".DS_Store" }
            .map { url in
                let isDir = ((try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory) ?? false
                let size = Int64(((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize) ?? 0)
                let mod = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
                return FileSystemStore.Entry(name: url.lastPathComponent, isDirectory: isDir, size: size, modified: mod ?? Date())
            }
            .sorted { a, b in
                if a.isDirectory != b.isDirectory { return a.isDirectory }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
    }

    /// Nhập kho: move cả cây vào mirror tại đích, đăng ký index/journal từng cấp.
    private func moveSelected(to dest: [String]) {
        let store = FileSystemStore.shared
        let names = selectionMode && !selected.isEmpty ? Array(selected) : items.map(\.name)
        for name in names {
            let src = AppPaths.sharedFiles.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: src.path) else { continue }
            var finalName = name
            var n = 2
            while store.exists(at: dest + [finalName])
                || IndexStore.shared.node(at: (dest + [finalName]).joined(separator: "/")) != nil {
                let base = (name as NSString).deletingPathExtension
                let ext = (name as NSString).pathExtension
                finalName = ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)"
                n += 1
                if n > 999 { break }
            }
            let target = dest + [finalName]
            let isDir = ((try? src.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory) ?? false
            do {
                if isDir {
                    try store.copyDirectory(from: src, to: target)
                    try FileManager.default.removeItem(at: src)
                    registerFolder(target)
                } else {
                    try store.copyFile(from: src, to: target)
                    try FileManager.default.removeItem(at: src)
                    registerFile(target)
                }
                let destText = target.joined(separator: "/")
                AppLog.log("shared", "📦 Nhập từ Shared: \(name) → \(destText)")
            } catch {
                AppLog.log("shared", "❌ Không nhập được \(name): \(error.localizedDescription)")
            }
        }
        selectionMode = false
        selected = []
        reload()
        store.notifyChanged()
        SyncEngine.triggerSyncPublic()
    }

    private func registerFolder(_ path: [String]) {
        let key = path.joined(separator: "/")
        IndexStore.shared.upsert(path: key, node: .init(
            name: path.last ?? "", isDirectory: true, size: 0, modified: Date(), parts: nil, rev: 1, driveFolderId: nil
        ))
        Journal.shared.enqueue(.createFolder(path: key))
        // Con bên trong (nếu có) — duyệt đích mới sau khi đã move vào mirror.
        let fm = FileManager.default
        let dirURL = FileSystemStore.shared.url(for: path)
        if let enumerator = fm.enumerator(at: dirURL, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey]) {
            while let next = enumerator.nextObject() as? URL {
                let isDir = ((try? next.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory) ?? false
                guard let rel = FileSystemStore.shared.relativePath(of: next) else { continue }
                if isDir {
                    let k = rel.joined(separator: "/")
                    IndexStore.shared.upsert(path: k, node: .init(
                        name: rel.last ?? "", isDirectory: true, size: 0, modified: Date(), parts: nil, rev: 1, driveFolderId: nil
                    ))
                    Journal.shared.enqueue(.createFolder(path: k))
                } else {
                    let size = ((try? next.resourceValues(forKeys: [.fileSizeKey]))?.fileSize).map(Int64.init) ?? 0
                    let k = rel.joined(separator: "/")
                    IndexStore.shared.upsert(path: k, node: .init(
                        name: rel.last ?? "", isDirectory: false, size: size, modified: Date(), parts: nil, rev: 1, driveFolderId: nil
                    ))
                    Journal.shared.enqueue(.uploadFile(path: k))
                }
            }
        }
    }

    private func registerFile(_ path: [String]) {
        let size = FileSystemStore.shared.fileSize(at: path) ?? 0
        let key = path.joined(separator: "/")
        IndexStore.shared.upsert(path: key, node: .init(
            name: path.last ?? "", isDirectory: false, size: size, modified: Date(), parts: nil, rev: 1, driveFolderId: nil
        ))
        Journal.shared.enqueue(.uploadFile(path: key))
    }
}
