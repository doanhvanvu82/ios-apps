import Foundation

/// Loại engine được nhận diện từ nội dung thư mục game.
enum EngineKind: String, Codable, CaseIterable {
    // --- Chơi được trên iOS ---
    case renpyWeb          // Ren'Py build for web (index.html + renpy.js / thư mục renpy/)
    case rpgMakerMV        // RPG Maker MV/MZ (www/ hoặc index.html + js/rpg_*.js)
    case tyranoBuilder     // TyranoBuilder (NW.js/Electron, thường trong app.asar)
    case unityWebGL        // Unity WebGL build (Build/*.loader.js + TemplateData/)
    case godotWebGL        // Godot WebGL build (index.html + index.wasm + index.pck)
    case kirikiWeb         // KiriKiri2 qua runtime kirikiroid2-web (index.wasm + game.zip)
    case flashWeb          // Flash .swf qua Ruffle (index.html + ruffle.js + *.swf)
    // --- Game gốc (Windows) chạy được nhờ runtime đi kèm app, KHÔNG cần build ---
    case godotNative       // Godot Windows: thư mục chứa file .pck
    case kirikiNative      // KiriKiri2 Windows: thư mục chứa file .xp3
    case flashNative       // Adobe Flash: thư mục chứa file .swf
    case genericWeb        // HTML5 generic (index.html + js/ hoặc assets/)

    // --- Đã nhận diện được nhưng chưa hỗ trợ trên iOS ---
    case unityWindows      // Unity build cho Windows (Mono hoặc IL2CPP)
    case renpyNative       // Ren'Py bản desktop (game/ + renpy/ + .exe)
    case kirikiri          // KiriKiri / EAIRPG (KAG)
    case godot             // Godot Engine
    case flashSWF          // Adobe Flash (.swf)
    case adobeAIR          // Adobe AIR
    case gameMaker         // YoYo GameMaker
    case unityIL2CPP       // Unity Windows build IL2CPP (GameAssembly.dll)
    case unrealEngine      // Unreal Engine (.pak / .utoc / .ucas)
    case pixelGameMaker    // Pixel Game Maker MV (Cocos2d-x JS bản Windows)
    case exhibit           // ExHIBIT (rld/, .gyu)
    case renpyOtherVersion // Ren'Py desktop khác nhánh runtime web đi kèm
    case unknown

    /// Runtime đi kèm app dùng để chơi game gốc (không cần build lại).
    var bundledRuntime: EngineRuntime? {
        switch self {
        case .godotNative, .godotWebGL: return .godot4
        case .kirikiNative, .kirikiWeb: return .kiriki
        case .flashNative, .flashWeb: return .ruffle
        case .renpyNative: return .renpy
        default: return nil
        }
    }

    var displayName: String {
        switch self {
        case .renpyWeb: return "Ren'Py (Web)"
        case .rpgMakerMV: return "RPG Maker MV/MZ"
        case .tyranoBuilder: return "TyranoBuilder (NW.js)"
        case .unityWebGL: return "Unity (WebGL)"
        case .godotWebGL: return "Godot (WebGL)"
        case .kirikiWeb: return "KiriKiri2 (WebAssembly)"
        case .flashWeb: return "Flash / Ruffle (Web)"
        case .godotNative: return "Godot (gốc)"
        case .kirikiNative: return "KiriKiri2 (gốc)"
        case .flashNative: return "Flash (gốc)"
        case .genericWeb: return "HTML5 / Web"
        case .unityWindows: return "Unity (Windows)"
        case .renpyNative: return "Ren'Py (gốc)"
        case .kirikiri: return "KiriKiri / EAIRPG"
        case .godot: return "Godot Engine"
        case .flashSWF: return "Adobe Flash"
        case .adobeAIR: return "Adobe AIR"
        case .gameMaker: return "YoYo GameMaker"
        case .unityIL2CPP: return "Unity (Windows, IL2CPP)"
        case .unrealEngine: return "Unreal Engine"
        case .pixelGameMaker: return "Pixel Game Maker MV"
        case .exhibit: return "ExHIBIT"
        case .renpyOtherVersion: return "Ren'Py (gốc, khác phiên bản)"
        case .unknown: return "Không nhận diện được"
        }
    }

    /// Game có thể chơi trực tiếp trên iOS.
    var isPlayable: Bool {
        switch self {
        case .renpyWeb, .rpgMakerMV, .tyranoBuilder, .unityWebGL, .godotWebGL,
             .kirikiWeb, .flashWeb, .genericWeb,
             .godotNative, .kirikiNative, .flashNative, .renpyNative:
            return true
        default:
            return false
        }
    }

    /// Giải thích ngắn gọn vì sao engine này chưa chơi được trong app này.
    var unsupportedReason: String? {
        switch self {
        case .unityWindows:
            return "Unity bản Mono cho Windows: không có runtime Unity nào trên iOS chạy được. Cần xuất project (tools/unity_extract.sh) và build WebGL trên máy tính."
        case .unityIL2CPP:
            return "Unity IL2CPP: logic game đã biên dịch thành mã máy Windows (GameAssembly.dll), không chạy được trên iOS và không xuất lại project được."
        case .unrealEngine:
            return "Unreal Engine không có runtime web/iOS chạy được bản build Windows."
        case .pixelGameMaker:
            return "Pixel Game Maker MV: logic game nằm trong engine C++ của file .exe."
        case .exhibit:
            return "ExHIBIT là engine riêng của Windows, chưa có runtime cho iOS."
        case .renpyOtherVersion:
            return "App chỉ có runtime Ren'Py \(RenPyNative.supportedVersions); game dùng phiên bản Ren'Py khác (xem renpy/vc_version.py)."
        case .kirikiri:
            return "Game KiriKiri/EAIRPG cần runtime KiriKiri cho iOS."
        case .godot:
            return "Game Godot cần bản export iOS từ project gốc."
        case .flashSWF:
            return "Game Flash cần trình đọc Flash (vd: Ruffle)."
        case .adobeAIR:
            return "Adobe AIR không có runtime cho iOS."
        case .gameMaker:
            return "GameMaker native export không chạy được trên iOS; cần bản HTML5."
        case .unknown:
            return "Không tìm thấy index.html — game có thể không phải bản web."
        default:
            return nil
        }
    }
}

struct DetectedGame: Identifiable, Hashable {
    var id: String { folderName }
    let folderName: String
    let engine: EngineKind
    /// Đường dẫn tương đối tới thư mục chứa index.html ("." = chính thư mục game).
    /// Với game `.asar`, đây là `nil` vì entry nằm trong archive.
    let entryPath: String?
    /// `true` nếu game đóng gói: archive `.asar` (Electron/NW.js) hoặc zip
    /// gắn trong `.exe` (NW.js một tệp). Tên giữ nguyên vì đã lưu trong cache.
    let isAsar: Bool
}

/// Nhận diện engine của một thư mục game trong Documents/Games.
enum EngineDetector {

    static func detect(in gameDir: URL) -> DetectedGame {
        // 1. Game đóng gói NW.js / Electron → nằm trong `app.asar`.
        //
        // Chỉ dùng archive khi nó chứa `index.html` ở gốc. Nhiều game bọc
        // Electron shell trong `app.asar` (chỉ có main.js/preload.js) còn game
        // thật nằm ở thư mục con — trường hợp đó phải rơi xuống nhánh thư mục.
        if let asarURL = GameResourceRoot.findAsarArchive(in: gameDir),
           let archive = try? AsarArchive(url: asarURL),
           archive.hasRootIndexHTML {
            return DetectedGame(
                folderName: gameDir.lastPathComponent,
                engine: detectEngine { archive.entry(at: $0) != nil },
                entryPath: nil,
                isAsar: true
            )
        }

        // NW.js đóng gói một tệp: zip (có index.html ở gốc) gắn cuối `.exe`.
        if let exeURL = ExeZipArchive.find(in: gameDir),
           let archive = try? ExeZipArchive(url: exeURL) {
            return DetectedGame(
                folderName: gameDir.lastPathComponent,
                engine: detectEngine { archive.entry(at: $0) != nil },
                entryPath: nil,
                isAsar: true
            )
        }

        // 2. Game trong thư mục thường.
        if let entry = findEntryWhere(gameDir, depth: 3, predicate: isRenpyWeb) {
            return DetectedGame(
                folderName: gameDir.lastPathComponent,
                engine: .renpyWeb,
                entryPath: relativeEntry(gameDir, entry),
                isAsar: false
            )
        }

        if let entry = findEntryWhere(gameDir, depth: 3, predicate: isRPGMaker) {
            return DetectedGame(
                folderName: gameDir.lastPathComponent,
                engine: .rpgMakerMV,
                entryPath: relativeEntry(gameDir, entry),
                isAsar: false
            )
        }

        if let entry = findEntryWhere(gameDir, depth: 3, predicate: isTyranoBuilder) {
            return DetectedGame(
                folderName: gameDir.lastPathComponent,
                engine: .tyranoBuilder,
                entryPath: relativeEntry(gameDir, entry),
                isAsar: false
            )
        }

        if let entry = findEntryWhere(gameDir, depth: 3, predicate: isUnityWebGL) {
            return DetectedGame(
                folderName: gameDir.lastPathComponent,
                engine: .unityWebGL,
                entryPath: relativeEntry(gameDir, entry),
                isAsar: false
            )
        }

        if let entry = findEntryWhere(gameDir, depth: 3, predicate: isGodotWebGL) {
            return DetectedGame(
                folderName: gameDir.lastPathComponent,
                engine: .godotWebGL,
                entryPath: relativeEntry(gameDir, entry),
                isAsar: false
            )
        }

        if let entry = findEntryWhere(gameDir, depth: 3, predicate: isKirikiWeb) {
            return DetectedGame(
                folderName: gameDir.lastPathComponent,
                engine: .kirikiWeb,
                entryPath: relativeEntry(gameDir, entry),
                isAsar: false
            )
        }

        if let entry = findEntryWhere(gameDir, depth: 3, predicate: isFlashWeb) {
            return DetectedGame(
                folderName: gameDir.lastPathComponent,
                engine: .flashWeb,
                entryPath: relativeEntry(gameDir, entry),
                isAsar: false
            )
        }

        // --- Game gốc Windows: chạy được nhờ runtime đi kèm app ---
        if let entry = findEntryWhere(gameDir, depth: 3, predicate: isGodotNative) {
            return DetectedGame(
                folderName: gameDir.lastPathComponent,
                engine: .godotNative,
                entryPath: relativeEntry(gameDir, entry),
                isAsar: false
            )
        }

        if let entry = findEntryWhere(gameDir, depth: 3, predicate: isKirikiNative) {
            return DetectedGame(
                folderName: gameDir.lastPathComponent,
                engine: .kirikiNative,
                entryPath: relativeEntry(gameDir, entry),
                isAsar: false
            )
        }

        if let entry = findEntryWhere(gameDir, depth: 3, predicate: isFlashNative) {
            return DetectedGame(
                folderName: gameDir.lastPathComponent,
                engine: .flashNative,
                entryPath: relativeEntry(gameDir, entry),
                isAsar: false
            )
        }

        if let entry = findEntryWhere(gameDir, depth: 3, predicate: isGenericWeb) {
            return DetectedGame(
                folderName: gameDir.lastPathComponent,
                engine: .genericWeb,
                entryPath: relativeEntry(gameDir, entry),
                isAsar: false
            )
        }

        // 3. Không có bản web — nhận diện engine native để báo lý do cụ thể.
        return DetectedGame(
            folderName: gameDir.lastPathComponent,
            engine: detectNativeEngine(in: gameDir),
            entryPath: nil,
            isAsar: false
        )
    }

    // MARK: - Nhận diện engine native (chưa hỗ trợ trên iOS)

    /// Dò engine của game bản desktop/native.
    ///
    /// Mục đích: hiển thị cho người dùng biết *cụ thể* vì sao game đó không
    /// chạy được, thay vì chỉ ghi "Chưa hỗ trợ".
    private static func detectNativeEngine(in gameDir: URL) -> EngineKind {
        let fm = FileManager.default

        // Unity: có `globalgamemanagers` (IL2CPP/Mono đều có) hoặc `UnityPlayer.dll`.
        if containsFile(named: "globalgamemanagers", in: gameDir, depth: 3)
            || containsFile(named: "UnityPlayer.dll", in: gameDir, depth: 3) {
            return containsFile(named: "GameAssembly.dll", in: gameDir, depth: 3) ? .unityIL2CPP : .unityWindows
        }

        // Unreal: thư mục Engine/ + tệp .pak/.utoc của game.
        if containsFile(suffix: ".utoc", in: gameDir, depth: 4)
            || (containsFile(suffix: ".pak", in: gameDir, depth: 4) && containsFile(named: "Engine", in: gameDir, depth: 2)) {
            return .unrealEngine
        }

        // Pixel Game Maker MV: lõi Cocos2d-x (libcocos2d.dll) + Resources/data/project.json.
        if containsFile(named: "libcocos2d.dll", in: gameDir, depth: 2)
            && containsFile(named: "project.json", in: gameDir.appendingPathComponent("Resources/data"), depth: 1) {
            return .pixelGameMaker
        }

        // ExHIBIT: thư mục rld/ với script .rld (trước đây bị nhận nhầm là KiriKiri).
        if directoryExists(gameDir, "rld") {
            return .exhibit
        }

        // Ren'Py desktop: thư mục `renpy/` + `game/`. Chỉ chơi được khi cùng
        // nhánh với runtime web đi kèm (module Cython phải khớp mã Python).
        if directoryExists(gameDir, "renpy") && directoryExists(gameDir, "game") {
            let version = RenPyNative.version(in: gameDir) ?? ""
            return RenPyNative.runtime(forVersion: version) != nil ? .renpyNative : .renpyOtherVersion
        }

        // Adobe AIR: META-INF/AIR/application.xml
        if containsFile(named: "application.xml", in: gameDir.appendingPathComponent("META-INF/AIR"), depth: 1) {
            return .adobeAIR
        }

        // GameMaker: data.win hoặc *.yyz
        if containsFile(named: "data.win", in: gameDir, depth: 3)
            || containsFile(suffix: ".yyz", in: gameDir, depth: 3) {
            return .gameMaker
        }

        // `.pck` không có magic GDPC (Godot thật đã thành godotNative ở trên):
        // vd pck voice Wwise của Tsumakan2 — không gắn nhãn Godot.

        // KiriKiri/EAIRPG: thư mục `plugin/` với .dll, hoặc file .rld / .eog / .tjs
        if directoryExists(gameDir, "plugin") {
            return .kirikiri
        }

        // Flash: file .swf
        if containsFile(suffix: ".swf", in: gameDir, depth: 3) {
            return .flashSWF
        }

        _ = fm
        return .unknown
    }

    /// Tìm file có tên cụ thể trong cây thư mục (giới hạn độ sâu).
    private static func containsFile(named name: String, in dir: URL, depth: Int) -> Bool {
        if FileManager.default.fileExists(atPath: dir.appendingPathComponent(name).path) {
            return true
        }
        return searchFiles(in: dir, depth: depth) { $0.lastPathComponent == name }
    }

    /// Tìm file có phần mở rộng trong cây thư mục (giới hạn độ sâu).
    /// `suffix` có hoặc không có dấu chấm đầu (".pck" hay "pck").
    private static func containsFile(suffix: String, in dir: URL, depth: Int) -> Bool {
        let ext = suffix.hasPrefix(".") ? String(suffix.dropFirst()) : suffix
        return searchFiles(in: dir, depth: depth) { $0.pathExtension.lowercased() == ext }
    }

    private static func searchFiles(in dir: URL, depth: Int, match: (URL) -> Bool) -> Bool {
        guard depth >= 0 else { return false }
        let fm = FileManager.default
        guard let children = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return false }
        for child in children {
            var isDir: ObjCBool = false
            fm.fileExists(atPath: child.path, isDirectory: &isDir)
            if isDir.boolValue {
                if searchFiles(in: child, depth: depth - 1, match: match) { return true }
            } else if match(child) {
                return true
            }
        }
        return false
    }

    // MARK: - Predicates

    /// Ren'Py web build: index.html + (renpy.js ở gốc HOẶC thư mục renpy/ có file *renpy.js)
    private static func isRenpyWeb(_ dir: URL) -> Bool {
        guard hasFile(dir, "index.html") else { return false }
        return hasFile(dir, "renpy.js") || directoryContains(dir, "renpy", suffix: "renpy.js")
    }

    /// RPG Maker MV/MZ: index.html + js/rpg_core.js (MV) hoặc js/rmmz_core.js (MZ)
    private static func isRPGMaker(_ dir: URL) -> Bool {
        guard hasFile(dir, "index.html") else { return false }
        return hasFile(dir, "js/rpg_core.js")
            || hasFile(dir, "js/rmmz_core.js")
            || hasFile(dir, "js/plugins.js")
    }

    /// TyranoBuilder: index.html + thư mục tyrano/ hoặc file tyrano/tyrano.js
    private static func isTyranoBuilder(_ dir: URL) -> Bool {
        guard hasFile(dir, "index.html") else { return false }
        return directoryExists(dir, "tyrano")
            || hasFile(dir, "tyrano/tyrano.js")
            || hasFile(dir, "tyrano/tyrano.js")
    }

    /// Unity WebGL: index.html + thư mục `Build/` (chứa *.loader.js) và/hoặc `TemplateData/`
    private static func isUnityWebGL(_ dir: URL) -> Bool {
        guard hasFile(dir, "index.html") else { return false }
        if directoryExists(dir, "TemplateData") { return true }
        guard directoryExists(dir, "Build") else { return false }
        guard let items = try? FileManager.default.contentsOfDirectory(
            atPath: dir.appendingPathComponent("Build").path
        ) else { return false }
        return items.contains { $0.hasSuffix(".loader.js") }
    }

    /// KiriKiri2 (runtime kirikiroid2-web): index.html + index.wasm + game.zip
    private static func isKirikiWeb(_ dir: URL) -> Bool {
        guard hasFile(dir, "index.html"), hasFile(dir, "index.wasm") else { return false }
        return hasFile(dir, "game.zip")
    }

    /// Flash (.swf) qua Ruffle: index.html + ruffle.js + file .swf
    private static func isFlashWeb(_ dir: URL) -> Bool {
        guard hasFile(dir, "index.html"), hasFile(dir, "ruffle.js") else { return false }
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return false }
        return items.contains { $0.hasSuffix(".swf") }
    }

    /// Godot Windows (bản gốc): thư mục chứa file `.pck` có magic `GDPC`.
    ///
    /// App phục vụ `.pck` gốc kèm runtime Godot web đi kèm → chơi được
    /// mà **không cần build lại** game.
    ///
    /// Lưu ý: check magic vì game khác cũng có file `.pck` (vd Tsumakan2
    /// dùng pck riêng cho voice, không phải Godot).
    private static func isGodotNative(_ dir: URL) -> Bool {
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return false }
        return items.contains { $0.hasSuffix(".pck") && hasGodotPackMagic(at: dir.appendingPathComponent($0)) }
            || items.contains { $0.lowercased().hasSuffix(".exe") && GodotPack.embeddedPack(in: dir.appendingPathComponent($0)) != nil }
    }

    /// `true` nếu file có header `GDPC` (Godot pack).
    static func hasGodotPackMagic(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 4) else { return false }
        return header == Data("GDPC".utf8)
    }

    /// KiriKiri2 Windows (bản gốc): thư mục chứa file `.xp3`.
    private static func isKirikiNative(_ dir: URL) -> Bool {
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return false }
        return items.contains { $0.hasSuffix(".xp3") }
    }

    /// Adobe Flash (bản gốc): thư mục chứa file `.swf`, hoặc projector `.exe` nhúng SWF chính
    /// (khi đó thư mục này mới là gốc, `data/` chỉ chứa SWF phụ).
    private static func isFlashNative(_ dir: URL) -> Bool {
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return false }
        return items.contains { $0.hasSuffix(".swf") } || FlashProjector.entry(in: dir, items: items) != nil
    }

    /// Godot WebGL: index.html + index.wasm + index.pck (bản export HTML5 của Godot).
    private static func isGodotWebGL(_ dir: URL) -> Bool {
        guard hasFile(dir, "index.html") else { return false }
        guard hasFile(dir, "index.wasm") else { return false }
        // Godot đặt tên pack theo tên project, thường là index.pck
        if hasFile(dir, "index.pck") { return true }
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return false }
        return items.contains { $0.hasSuffix(".pck") }
    }

    /// HTML5 generic: index.html + (js/ HOẶC assets/ HOẶC data/)
    private static func isGenericWeb(_ dir: URL) -> Bool {
        guard hasFile(dir, "index.html") else { return false }
        return directoryExists(dir, "js")
            || directoryExists(dir, "assets")
            || directoryExists(dir, "data")
            || hasFile(dir, "main.js")
    }

    // MARK: - Detection inside an .asar archive

    /// Nhận diện engine bên trong archive `.asar`.
    ///
    /// Chỉ kiểm tra ở gốc archive vì game NW.js thường đặt `index.html` ở gốc
    /// cùng với thư mục `tyrano/`, `data/`.
    /// Engine của game trong archive (`.asar` / zip trong exe).
    private static func detectEngine(has: (String) -> Bool) -> EngineKind {
        if has("tyrano/tyrano.js") || has("tyrano") {
            return .tyranoBuilder
        }
        if has("js/rpg_core.js") || has("js/rmmz_core.js") || has("js/plugins.js") {
            return .rpgMakerMV
        }
        if has("renpy.js") || has("renpy") {
            return .renpyWeb
        }
        return .genericWeb
    }

    // MARK: - Search helpers

    /// Dò tìm entry: thử các vị trí phổ biến trước (nhanh), rồi quét đệ quy giới hạn độ sâu.
    private static func findEntryWhere(_ root: URL, depth: Int, predicate: (URL) -> Bool) -> URL? {
        let common = ["", "www", "game", "web", "dist", "public", "app"]
        for sub in common {
            let candidate = sub.isEmpty ? root : root.appendingPathComponent(sub)
            if predicate(candidate) { return candidate }
        }
        return searchRecursive(root, depth: depth, predicate: predicate)
    }

    private static func searchRecursive(_ dir: URL, depth: Int, predicate: (URL) -> Bool) -> URL? {
        if predicate(dir) { return dir }
        guard depth > 0 else { return nil }
        let fm = FileManager.default
        guard let children = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return nil }
        for child in children {
            var isDir: ObjCBool = false
            fm.fileExists(atPath: child.path, isDirectory: &isDir)
            if isDir.boolValue, child.lastPathComponent != "save" {
                if let hit = searchRecursive(child, depth: depth - 1, predicate: predicate) {
                    return hit
                }
            }
        }
        return nil
    }

    private static func hasFile(_ dir: URL, _ relative: String) -> Bool {
        FileManager.default.fileExists(atPath: dir.appendingPathComponent(relative).path)
    }

    private static func directoryExists(_ dir: URL, _ relative: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: dir.appendingPathComponent(relative).path, isDirectory: &isDir)
            && isDir.boolValue
    }

    private static func directoryContains(_ dir: URL, _ sub: String, suffix: String) -> Bool {
        let subDir = dir.appendingPathComponent(sub)
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: subDir.path) else { return false }
        return items.contains { $0.hasSuffix(suffix) }
    }

    private static func relativeEntry(_ gameRoot: URL, _ entry: URL) -> String {
        let root = gameRoot.standardizedFileURL.path
        let entryPath = entry.standardizedFileURL.path
        if entryPath == root { return "." }
        if entryPath.hasPrefix(root + "/") {
            return String(entryPath.dropFirst(root.count + 1))
        }
        return "."
    }
}
