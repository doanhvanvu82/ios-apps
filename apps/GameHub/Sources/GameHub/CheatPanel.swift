import SwiftUI
import WebKit

/// Giá trị đọc từ trang (số / bật-tắt / chữ).
enum CheatValue: Equatable {
    case number(Double), bool(Bool), text(String), none

    init(_ any: Any?) {
        switch any {
        case let n as NSNumber where CFGetTypeID(n) == CFBooleanGetTypeID(): self = .bool(n.boolValue)
        case let n as NSNumber: self = .number(n.doubleValue)
        case let s as String: self = .text(s)
        default: self = .none
        }
    }

    var display: String {
        switch self {
        case .number(let d): return CheatValue.format(d)
        case .bool(let b): return b ? "true" : "false"
        case .text(let s): return s
        case .none: return "?"
        }
    }

    static func format(_ d: Double) -> String {
        d == d.rounded() && abs(d) < 1e15 ? String(Int64(d)) : String(d)
    }
}

/// Một giá trị sửa/khoá được. `ref` là mã tham chiếu trong Cheat/cheat.js.
struct CheatEntry: Identifiable, Equatable {
    let ref: String
    var label: String
    var value: CheatValue
    var id: String { ref }

    init(ref: String, label: String, value: CheatValue) {
        self.ref = ref
        self.label = label
        self.value = value
    }

    init?(_ any: Any?) {
        guard let d = any as? [String: Any], let ref = d["ref"] as? String else { return nil }
        self.init(ref: ref, label: d["label"] as? String ?? ref, value: CheatValue(d["value"]))
    }
}

struct RpgmActor: Identifiable {
    let id: Int
    let name: String
    let fields: [CheatEntry]
}

struct RpgmData {
    var gold = CheatEntry(ref: "r:gold", label: "Vàng", value: .none)
    var actors: [RpgmActor] = []
    var items: [CheatEntry] = []
    var variables: [CheatEntry] = []
    var switches: [CheatEntry] = []

    init() {}

    init(_ any: Any?) {
        guard let d = any as? [String: Any] else { return }
        gold.value = CheatValue(d["gold"])
        actors = (d["actors"] as? [[String: Any]] ?? []).compactMap { a in
            guard let id = (a["id"] as? NSNumber)?.intValue else { return nil }
            func field(_ key: String, _ title: String, max: String? = nil) -> CheatEntry {
                let cap = max.flatMap { (a[$0] as? NSNumber).map { " / \(CheatValue.format($0.doubleValue))" } } ?? ""
                return CheatEntry(ref: "r:actor:\(id):\(key)", label: title + cap, value: CheatValue(a[key]))
            }
            var fields = [field("level", "Level"), field("hp", "HP", max: "mhp"), field("mp", "MP", max: "mmp"),
                          field("tp", "TP"), field("exp", "EXP")]
            for p in a["params"] as? [[String: Any]] ?? [] {
                let i = (p["id"] as? NSNumber)?.intValue ?? 0
                fields.append(CheatEntry(ref: "r:actor:\(id):param\(i)", label: p["name"] as? String ?? "param\(i)",
                                         value: CheatValue(p["value"])))
            }
            return RpgmActor(id: id, name: a["name"] as? String ?? "#\(id)", fields: fields)
        }
        let kindTitle = ["item": "Vật phẩm", "weapon": "Vũ khí", "armor": "Giáp"]
        items = (d["items"] as? [[String: Any]] ?? []).compactMap { i in
            guard let kind = i["kind"] as? String, let id = (i["id"] as? NSNumber)?.intValue else { return nil }
            return CheatEntry(ref: "r:\(kind):\(id)", label: "\(i["name"] as? String ?? "") · \(kindTitle[kind] ?? kind)",
                              value: CheatValue(i["count"]))
        }
        func list(_ key: String, _ kind: String) -> [CheatEntry] {
            (d[key] as? [[String: Any]] ?? []).compactMap { v in
                guard let id = (v["id"] as? NSNumber)?.intValue else { return nil }
                return CheatEntry(ref: "r:\(kind):\(id)", label: "\(id). \(v["name"] as? String ?? "")", value: CheatValue(v["value"]))
            }
        }
        variables = list("variables", "variable")
        switches = list("switches", "switch")
    }
}

/// Trạng thái bảng chỉnh thông số — sống suốt phiên chơi (đóng bảng không mất
/// kết quả quét / danh sách đã ghim).
@MainActor
final class CheatModel: ObservableObject {
    enum ScanType: String, CaseIterable, Identifiable {
        case number, int32, float32, int16, int8, float64
        var id: String { rawValue }
        var title: String {
            switch self {
            case .number: return "Số JS"
            case .int32: return "Int 4 byte"
            case .float32: return "Float"
            case .int16: return "Int 2 byte"
            case .int8: return "Byte"
            case .float64: return "Double"
            }
        }
    }

    enum NextMode: String, CaseIterable, Identifiable {
        case exact, increased, decreased, changed, unchanged
        var id: String { rawValue }
        var title: String {
            switch self {
            case .exact: return "Bằng giá trị đã nhập"
            case .increased: return "Đã tăng"
            case .decreased: return "Đã giảm"
            case .changed: return "Đã thay đổi"
            case .unchanged: return "Không đổi"
            }
        }
    }

    var webView: () -> WKWebView? = { nil }

    @Published var isRpgm = false
    @Published var heapMB = 0
    @Published var rpgm = RpgmData()
    @Published var scanType: ScanType = .number
    @Published var between = false
    @Published var value = ""
    @Published var value2 = ""
    @Published var resultCount: Int?
    @Published var results: [CheatEntry] = []
    @Published var saved: [CheatEntry] = []
    @Published var frozen: Set<String> = []
    @Published var busy = false
    @Published var progress = 0.0
    @Published var error: String?
    private var scanTypeChosen = false

    private struct Failure: LocalizedError {
        let errorDescription: String?
    }

    private func call(_ name: String, _ args: [String: Any] = [:]) async throws -> Any? {
        guard let wv = webView() else { throw Failure(errorDescription: "WebView chưa sẵn sàng") }
        return try await GameWebView.cheat(wv, name, args)
    }

    private func attempt(_ body: () async throws -> Void) async {
        error = nil
        do {
            try await body()
        } catch {
            let ns = error as NSError
            self.error = ns.userInfo["WKJavaScriptExceptionMessage"] as? String ?? error.localizedDescription
        }
    }

    func refreshInfo() async {
        await attempt {
            let info = try await call("info") as? [String: Any] ?? [:]
            isRpgm = (info["rpgm"] as? Bool) ?? false
            heapMB = (info["heapMB"] as? NSNumber)?.intValue ?? 0
            if !scanTypeChosen {
                scanType = heapMB > 0 && !isRpgm ? .int32 : .number
                scanTypeChosen = true
            }
            if isRpgm { rpgm = RpgmData(try await call("rpgm")) }
        }
    }

    func set(_ entry: CheatEntry, to value: CheatValue) async {
        await attempt {
            let jsValue: Any
            switch value {
            case .number(let d): jsValue = d == d.rounded() && abs(d) < 1e15 ? Int64(d) as Any : d
            case .bool(let b): jsValue = b
            case .text(let s): jsValue = s
            case .none: return
            }
            let updated = CheatEntry(try await call("write", ["ref": entry.ref, "value": jsValue]))
            AppLog.info("Cheat: \(entry.label) [\(entry.ref)] = \(updated?.value.display ?? "?")")
            if let updated { replace(updated) }
            if entry.ref.hasPrefix("r:") { rpgm = RpgmData(try await call("rpgm")) }
        }
    }

    /// `value`: số đang gõ chưa ghi — khoá luôn ở giá trị đó thay vì giá trị hiện tại.
    func setFrozen(_ entry: CheatEntry, _ on: Bool, value: Double? = nil) async {
        await attempt {
            var args: [String: Any] = ["ref": entry.ref, "on": on]
            if let value { args["value"] = value == value.rounded() && abs(value) < 1e15 ? Int64(value) as Any : value }
            let updated = CheatEntry(try await call("freeze", args))
            if on { frozen.insert(entry.ref) } else { frozen.remove(entry.ref) }
            AppLog.info("Cheat: \(on ? "khoá" : "bỏ khoá") \(entry.label) [\(entry.ref)] = \(value.map(CheatValue.format) ?? entry.value.display)")
            if let updated { replace(updated) }
        }
    }

    func pin(_ entry: CheatEntry) {
        guard !saved.contains(where: { $0.ref == entry.ref }) else { return }
        saved.append(entry)
    }

    func unpin(_ entry: CheatEntry) async {
        if frozen.contains(entry.ref) { await setFrozen(entry, false) }
        saved.removeAll { $0.ref == entry.ref }
    }

    func scan(first: Bool, mode: NextMode = .exact) async {
        guard !busy else { return }
        let needsValue = first || mode == .exact
        guard !needsValue || Double(value) != nil, !(first && between) || Double(value2) != nil else {
            error = "Nhập giá trị số trước khi quét"
            return
        }
        busy = true
        progress = 0
        let poll = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                if let p = try? await call("progress") as? NSNumber { progress = p.doubleValue }
            }
        }
        await attempt {
            var args: [String: Any] = ["value": Double(value) ?? 0, "value2": Double(value2) ?? 0]
            if first {
                args["type"] = scanType.rawValue
                args["mode"] = between ? "between" : "exact"
            } else {
                args["mode"] = mode.rawValue
            }
            let started = Date()
            applyResults(try await call(first ? "first" : "next", args))
            AppLog.info("Cheat: quét \(first ? "đầu" : "tiếp (\(mode.rawValue))") \(scanType.rawValue) \(value) → \(resultCount ?? 0) kết quả, \(Int(Date().timeIntervalSince(started) * 1000)) ms")
        }
        poll.cancel()
        busy = false
    }

    func resetScan() async {
        await attempt { _ = try await call("reset") }
        resultCount = nil
        results = []
    }

    /// Đọc lại giá trị đang thấy (kết quả + đã ghim) để thấy chúng đổi theo game.
    func refreshValues() async {
        guard !busy else { return }
        let refs = Array(Set(results.map(\.ref) + saved.map(\.ref)))
        guard !refs.isEmpty, let wv = webView(),
              let list = try? await GameWebView.cheat(wv, "read", ["refs": refs]) as? [Any] else { return }
        for e in list.compactMap({ CheatEntry($0) }) { replace(e) }
    }

    private func applyResults(_ any: Any?) {
        let d = any as? [String: Any] ?? [:]
        resultCount = (d["count"] as? NSNumber)?.intValue ?? 0
        results = (d["items"] as? [Any] ?? []).compactMap { CheatEntry($0) }
    }

    private func replace(_ e: CheatEntry) {
        if let i = results.firstIndex(where: { $0.ref == e.ref }) { results[i].value = e.value }
        if let i = saved.firstIndex(where: { $0.ref == e.ref }) { saved[i].value = e.value }
    }
}

/// Bảng nổi bên phải: game vẫn chạy và nhìn thấy phía sau (sheet sẽ che kín và
/// làm trang mất focus — RPG Maker ngừng update khi mất focus).
struct CheatPanel: View {
    @ObservedObject var model: CheatModel
    let onClose: () -> Void

    private enum Tab: Hashable { case quick, scan, saved }
    @State private var tab: Tab = .scan
    @State private var search = ""

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Label("Chỉnh thông số", systemImage: "wand.and.stars")
                    .font(.headline)
                Spacer()
                Button { Task { await model.refreshInfo() } } label: { Image(systemName: "arrow.clockwise") }
                    .accessibilityLabel("Tải lại")
                Button(action: onClose) { Image(systemName: "xmark.circle.fill").font(.title3) }
                    .accessibilityLabel("Đóng")
            }
            Picker("", selection: $tab) {
                if model.isRpgm { Text("Nhanh").tag(Tab.quick) }
                Text("Quét").tag(Tab.scan)
                Text("Đã ghim (\(model.saved.count))").tag(Tab.saved)
            }
            .pickerStyle(.segmented)

            if let error = model.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    switch tab {
                    case .quick: quickTab
                    case .scan: scanTab
                    case .saved: savedTab
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .padding(14)
        .frame(width: 400)
        .frame(maxHeight: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.12)))
        .environment(\.colorScheme, .dark)
        .tint(Theme.accent)
        .task {
            await model.refreshInfo()
            if model.isRpgm { tab = .quick }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await model.refreshValues()
            }
        }
    }

    // MARK: Nhanh (RPG Maker)

    @ViewBuilder private var quickTab: some View {
        TextField("Tìm vật phẩm / biến / công tắc…", text: $search)
            .textFieldStyle(.roundedBorder)
        row(model.rpgm.gold)
        ForEach(model.rpgm.actors) { actor in
            sectionTitle(actor.name)
            ForEach(actor.fields) { row($0) }
        }
        let items = model.rpgm.items.filter { search.isEmpty ? $0.value != .number(0) : matches($0) }
        sectionTitle(search.isEmpty ? "Vật phẩm đang có (gõ tên để thêm món khác)" : "Vật phẩm")
        ForEach(items) { row($0) }
        sectionTitle("Biến")
        ForEach(model.rpgm.variables.filter(matches)) { row($0) }
        sectionTitle("Công tắc")
        ForEach(model.rpgm.switches.filter(matches)) { entry in
            Toggle(entry.label, isOn: Binding(
                get: { entry.value == .bool(true) },
                set: { on in Task { await model.set(entry, to: .bool(on)) } }))
                .font(.subheadline)
        }
    }

    private func matches(_ e: CheatEntry) -> Bool {
        search.isEmpty || e.label.localizedCaseInsensitiveContains(search)
    }

    // MARK: Quét (kiểu Cheat Engine)

    @ViewBuilder private var scanTab: some View {
        HStack {
            Picker("Kiểu", selection: $model.scanType) {
                ForEach(CheatModel.ScanType.allCases) { t in
                    if t == .number || model.heapMB > 0 { Text(t.title).tag(t) }
                }
            }
            .disabled(model.resultCount != nil)
            Toggle("Khoảng", isOn: $model.between)
                .fixedSize()
                .disabled(model.resultCount != nil)
        }
        HStack {
            numberField(model.between && model.resultCount == nil ? "Từ" : "Giá trị", text: $model.value)
            if model.between && model.resultCount == nil { numberField("Đến", text: $model.value2) }
        }
        HStack {
            Button("Quét mới") { Task { await model.resetScan(); await model.scan(first: true) } }
                .buttonStyle(.borderedProminent)
            Menu("Quét tiếp") {
                ForEach(CheatModel.NextMode.allCases) { mode in
                    Button(mode.title) { Task { await model.scan(first: false, mode: mode) } }
                }
            }
            .buttonStyle(.bordered)
            .disabled(model.resultCount == nil)
            Button("Làm lại", role: .destructive) { Task { await model.resetScan() } }
                .buttonStyle(.bordered)
                .disabled(model.resultCount == nil)
        }
        .disabled(model.busy)
        if model.busy {
            ProgressView(value: model.progress) { Text("Đang quét…").font(.caption) }
        }
        if let count = model.resultCount {
            Text(count > model.results.count ? "Tìm thấy \(count) — hiện \(model.results.count) đầu, quét tiếp để lọc"
                                             : "Tìm thấy \(count)")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(model.results) { row($0, pinnable: true) }
        } else {
            Text("""
            Nhập giá trị đang thấy trong game (vd số tiền) → Quét mới. Đổi giá trị đó trong game, \
            nhập số mới → Quét tiếp → "Bằng giá trị đã nhập". Lặp tới khi còn ít kết quả rồi sửa hoặc khoá.
            \(model.heapMB > 0 ? "Bộ nhớ game: \(model.heapMB) MB — game Unity/Godot chọn Int 4 byte hoặc Float." : "")
            """)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: Đã ghim

    @ViewBuilder private var savedTab: some View {
        if model.saved.isEmpty {
            Text("Bấm 📌 ở kết quả quét để ghim. Danh sách chỉ giữ trong lần chơi này (địa chỉ đổi mỗi lần mở game).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        ForEach(model.saved) { entry in
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    TextField("Tên", text: savedLabel(entry.ref))
                        .font(.caption.weight(.semibold))
                    Button(role: .destructive) { Task { await model.unpin(entry) } } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                }
                row(entry)
            }
        }
    }

    private func savedLabel(_ ref: String) -> Binding<String> {
        Binding(
            get: { model.saved.first { $0.ref == ref }?.label ?? "" },
            set: { name in
                if let i = model.saved.firstIndex(where: { $0.ref == ref }) { model.saved[i].label = name }
            })
    }

    // MARK: Thành phần

    private func sectionTitle(_ s: String) -> some View {
        Text(s)
            .font(.caption.weight(.bold))
            .foregroundStyle(.secondary)
            .padding(.top, 8)
    }

    private func numberField(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text)
            .keyboardType(.numbersAndPunctuation)
            .textFieldStyle(.roundedBorder)
    }

    private func row(_ entry: CheatEntry, pinnable: Bool = false) -> some View {
        CheatValueRow(
            entry: entry,
            frozen: model.frozen.contains(entry.ref),
            pinned: pinnable && model.saved.contains { $0.ref == entry.ref },
            onSet: { v in Task { await model.set(entry, to: .number(v)) } },
            onFreeze: { on, value in Task { await model.setFrozen(entry, on, value: value) } },
            onPin: pinnable ? { model.pin(entry) } : nil)
    }
}

private struct CheatValueRow: View {
    let entry: CheatEntry
    let frozen: Bool
    let pinned: Bool
    let onSet: (Double) -> Void
    let onFreeze: (Bool, Double?) -> Void
    let onPin: (() -> Void)?

    @State private var text = ""
    /// Giá trị game lần cuối đưa vào ô — `text` khác nó nghĩa là người dùng đang sửa.
    @State private var shown = ""
    @FocusState private var focused: Bool

    private var editable: Bool {
        if case .number = entry.value { return true }
        return false
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(entry.label)
                .font(entry.ref.hasPrefix("w:") ? .caption.monospaced() : .subheadline)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            TextField("", text: $text)
                .keyboardType(.numbersAndPunctuation)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .frame(width: 110)
                .focused($focused)
                .disabled(!editable)
                .submitLabel(.done)
                .onSubmit(apply)
            if pendingValue != nil {
                Button(action: apply) { Image(systemName: "checkmark.circle.fill").font(.title3) }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.green)
                    .accessibilityLabel("Áp dụng")
                    .transition(.scale.combined(with: .opacity))
            }
            Button { onFreeze(!frozen, frozen ? nil : pendingValue) } label: {
                Image(systemName: frozen ? "lock.fill" : "lock.open")
                    .foregroundStyle(frozen ? Theme.accent : .secondary)
            }
            .buttonStyle(.borderless)
            .disabled(!editable)
            .accessibilityLabel(frozen ? "Bỏ khoá" : "Khoá giá trị")
            if let onPin {
                Button(action: onPin) { Image(systemName: pinned ? "pin.fill" : "pin") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Ghim")
            }
        }
        .animation(Theme.snappy, value: pendingValue != nil)
        .onAppear {
            text = entry.value.display
            shown = text
        }
        // Đang gõ dở (chưa áp dụng) thì giữ số đang gõ, không bị giá trị từ game đè.
        .onChange(of: entry.value) { _, v in
            if text == shown || text == v.display { text = v.display }
            shown = v.display
        }
    }

    private func apply() {
        guard let d = pendingValue else { return }
        focused = false
        onSet(d)
    }

    /// Số đang gõ mà chưa ghi vào game (khác giá trị hiện tại).
    private var pendingValue: Double? {
        guard text != shown else { return nil }
        return Double(text.replacingOccurrences(of: ",", with: "."))
    }
}
