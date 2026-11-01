import SwiftUI
import Combine
import UIKit

// MARK: - Phím ảo

/// Một phím (hoặc chuột) mà nút ảo bắn vào WebView.
///
/// `code` là giá trị `KeyboardEvent.code` (physical key) — game web (RPG Maker,
/// Godot, Ren'Py, Ruffle…) đều lắng nghe qua đây, không phụ thuộc layout bàn phím.
struct VirtualKey: Codable, Hashable {
    /// `KeyboardEvent.code`, vd "ArrowUp", "KeyZ", "Enter", "ShiftLeft".
    var code: String
    /// `KeyboardEvent.key` fallback cho game đọc `key` thay vì `code`.
    var key: String
    /// Nút chuột nếu đây là nút chuột ảo (0 = trái, 2 = phải).
    ///
    /// Một số game (RPG Maker MV/MZ, Godot, HTML5) dùng chuột cho hành động
    /// chính → cần nút chuột ảo, không phải phím.
    var mouseButton: Int?

    init(code: String, key: String? = nil, mouseButton: Int? = nil) {
        self.code = code
        self.key = key ?? Self.defaultKey(for: code)
        self.mouseButton = mouseButton
    }

    /// Nút chuột ảo: trái / phải.
    static let mouseLeft = VirtualKey(code: "MouseLeft", key: "MouseLeft", mouseButton: 0)
    static let mouseRight = VirtualKey(code: "MouseRight", key: "MouseRight", mouseButton: 2)

    /// Nhãn hiển thị trên nút.
    var label: String {
        switch code {
        case "MouseLeft": return "L"
        case "MouseRight": return "R"
        case "ArrowUp": return "▲"
        case "ArrowDown": return "▼"
        case "ArrowLeft": return "◀"
        case "ArrowRight": return "▶"
        case "Enter": return "⏎"
        case "Space": return "␣"
        case "Escape": return "ESC"
        case "Tab": return "TAB"
        case "Backspace": return "⌫"
        case "ShiftLeft": return "⇧"
        case "ControlLeft": return "CTRL"
        case "ShiftRight": return "⇧R"
        default:
            if code.hasPrefix("Key") { return String(code.dropFirst(3)) }
            if code.hasPrefix("Digit") { return String(code.dropFirst(5)) }
            if code.hasPrefix("F"), code.count <= 3 { return code }
            return code
        }
    }

    /// Biểu tượng SF Symbols cho phím đặc biệt (nil → dùng `label` chữ).
    var symbol: String? {
        switch code {
        case "ArrowUp": return "arrowtriangle.up.fill"
        case "ArrowDown": return "arrowtriangle.down.fill"
        case "ArrowLeft": return "arrowtriangle.left.fill"
        case "ArrowRight": return "arrowtriangle.right.fill"
        case "Enter": return "return"
        case "Space": return "space"
        case "Backspace": return "delete.left.fill"
        case "ShiftLeft", "ShiftRight": return "shift.fill"
        case "Escape": return "escape"
        default: return nil
        }
    }

    private static func defaultKey(for code: String) -> String {
        switch code {
        case "ArrowUp": return "ArrowUp"
        case "ArrowDown": return "ArrowDown"
        case "ArrowLeft": return "ArrowLeft"
        case "ArrowRight": return "ArrowRight"
        case "Enter": return "Enter"
        case "Space": return " "
        case "Escape": return "Escape"
        case "Tab": return "Tab"
        case "Backspace": return "Backspace"
        case "ShiftLeft", "ShiftRight": return "Shift"
        case "ControlLeft": return "Control"
        default:
            if code.hasPrefix("Key") { return String(code.dropFirst(3)).lowercased() }
            if code.hasPrefix("Digit") { return String(code.dropFirst(5)) }
            return code
        }
    }

    /// Danh sách phím có thể gán (menu chọn trong màn hình tuỳ chỉnh).
    static let assignable: [VirtualKey] = [
        VirtualKey(code: "ArrowUp"), VirtualKey(code: "ArrowDown"),
        VirtualKey(code: "ArrowLeft"), VirtualKey(code: "ArrowRight"),
        VirtualKey(code: "KeyZ"), VirtualKey(code: "KeyX"),
        VirtualKey(code: "KeyC"), VirtualKey(code: "KeyA"),
        VirtualKey(code: "KeyS"), VirtualKey(code: "KeyD"),
        VirtualKey(code: "KeyW"), VirtualKey(code: "KeyQ"),
        VirtualKey(code: "KeyE"), VirtualKey(code: "KeyR"),
        VirtualKey(code: "KeyF"), VirtualKey(code: "KeyV"),
        VirtualKey(code: "KeyB"), VirtualKey(code: "KeyN"),
        VirtualKey(code: "KeyM"), VirtualKey(code: "KeyP"),
        VirtualKey(code: "Enter"), VirtualKey(code: "Space"),
        VirtualKey(code: "Escape"), VirtualKey(code: "Tab"),
        VirtualKey(code: "Backspace"), VirtualKey(code: "ShiftLeft"),
        VirtualKey(code: "ControlLeft"),
        VirtualKey(code: "Digit1"), VirtualKey(code: "Digit2"),
        VirtualKey(code: "Digit3"), VirtualKey(code: "Digit4"),
    ]
}

// MARK: - Nút điều khiển

/// Một nút trên màn điều khiển: vị trí + phím được gán + kích thước.
struct ControlButton: Codable, Hashable, Identifiable {
    var id: String { slotID }
    /// Tên vị trí — dùng để map preset; giữ nguyên khi chỉnh tuỳ ý.
    var slotID: String
    /// Vị trí trong overlay (tỉ lệ 0…1 so với kích thước màn hình).
    var x: Double
    var y: Double
    var size: Double
    var vk: VirtualKey

    init(slotID: String, x: Double, y: Double, size: Double = 62, vk: VirtualKey) {
        self.slotID = slotID
        self.x = x
        self.y = y
        self.size = size
        self.vk = vk
    }
}

/// Bố cục điều khiển của MỘT game.
struct ControlLayout: Codable {
    var buttons: [ControlButton]
    /// Độ mờ của toàn bộ màn điều khiển (0.1…0.9).
    var opacity: Double = 0.35
}

/// Preset mặc định cho từng loại engine.
enum ControlPresets {
    /// RPG Maker MV/MZ: Z = OK/confirm, X = cancel/menu, Shift = dash.
    /// Chuột trái = hành động chính, chuột phải = menu (RPG Maker dùng chuột
    /// rất nhiều — chỉ có bàn phím sẽ không chơi được).
    static func rpgMaker() -> ControlLayout {
        ControlLayout(buttons: [
            ControlButton(slotID: "up", x: 0.10, y: 0.72, size: 58, vk: VirtualKey(code: "ArrowUp")),
            ControlButton(slotID: "down", x: 0.10, y: 0.90, size: 58, vk: VirtualKey(code: "ArrowDown")),
            ControlButton(slotID: "left", x: 0.02, y: 0.81, size: 58, vk: VirtualKey(code: "ArrowLeft")),
            ControlButton(slotID: "right", x: 0.18, y: 0.81, size: 58, vk: VirtualKey(code: "ArrowRight")),
            ControlButton(slotID: "ok", x: 0.90, y: 0.74, size: 66, vk: VirtualKey(code: "KeyZ")),
            ControlButton(slotID: "cancel", x: 0.90, y: 0.90, size: 60, vk: VirtualKey(code: "KeyX")),
            ControlButton(slotID: "dash", x: 0.78, y: 0.90, size: 54, vk: VirtualKey(code: "ShiftLeft")),
            ControlButton(slotID: "menu", x: 0.90, y: 0.58, size: 52, vk: VirtualKey(code: "KeyC")),
            ControlButton(slotID: "mouseL", x: 0.62, y: 0.90, size: 58, vk: VirtualKey.mouseLeft),
            ControlButton(slotID: "mouseR", x: 0.72, y: 0.72, size: 54, vk: VirtualKey.mouseRight),
        ])
    }

    /// Ren'Py / visual novel: Enter = advance, Ctrl = skip, right-click = menu.
    static func visualNovel() -> ControlLayout {
        ControlLayout(buttons: [
            ControlButton(slotID: "advance", x: 0.86, y: 0.85, size: 70, vk: VirtualKey(code: "Enter")),
            ControlButton(slotID: "skip", x: 0.72, y: 0.85, size: 60, vk: VirtualKey(code: "ControlLeft")),
            ControlButton(slotID: "menu", x: 0.58, y: 0.85, size: 56, vk: VirtualKey(code: "Escape")),
            ControlButton(slotID: "back", x: 0.44, y: 0.85, size: 56, vk: VirtualKey(code: "KeyA")),
        ])
    }

    /// Godot / game hành động: WASD + Z/X + chuột trái/phải.
    static func action() -> ControlLayout {
        ControlLayout(buttons: [
            ControlButton(slotID: "up", x: 0.10, y: 0.68, size: 58, vk: VirtualKey(code: "KeyW")),
            ControlButton(slotID: "down", x: 0.10, y: 0.86, size: 58, vk: VirtualKey(code: "KeyS")),
            ControlButton(slotID: "left", x: 0.02, y: 0.77, size: 58, vk: VirtualKey(code: "KeyA")),
            ControlButton(slotID: "right", x: 0.18, y: 0.77, size: 58, vk: VirtualKey(code: "KeyD")),
            ControlButton(slotID: "ok", x: 0.90, y: 0.72, size: 68, vk: VirtualKey(code: "KeyZ")),
            ControlButton(slotID: "cancel", x: 0.88, y: 0.90, size: 60, vk: VirtualKey(code: "KeyX")),
            ControlButton(slotID: "mouseL", x: 0.66, y: 0.90, size: 56, vk: VirtualKey.mouseLeft),
            ControlButton(slotID: "mouseR", x: 0.76, y: 0.74, size: 52, vk: VirtualKey.mouseRight),
        ])
    }

    /// Preset theo engine của game.
    static func forEngine(_ engine: EngineKind) -> ControlLayout {
        switch engine {
        case .rpgMakerMV, .tyranoBuilder:
            return rpgMaker()
        case .renpyWeb, .renpyNative, .kirikiNative, .kirikiWeb:
            return visualNovel()
        case .godotNative, .godotWebGL, .godot:
            return action()
        default:
            return rpgMaker()
        }
    }
}

// MARK: - Lưu bố cục theo game

/// Lưu bố cục điều khiển **theo từng game** trong Documents/GameHub/Controls/.
final class ControlStore {
    static let shared = ControlStore()

    private let dir: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        dir = docs.appendingPathComponent("GameHub/Controls", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func fileURL(for gameName: String) -> URL {
        // Tên file an toàn: bỏ ký tự đặc biệt.
        let safe = gameName.replacingOccurrences(
            of: "[^a-zA-Z0-9-_ .]", with: "_",
            options: .regularExpression)
        return dir.appendingPathComponent("\(safe).json")
    }

    /// Bố cục đã lưu của game; `nil` nếu chưa chỉnh → dùng preset theo engine.
    func load(for gameName: String) -> ControlLayout? {
        guard let data = try? Data(contentsOf: fileURL(for: gameName)) else { return nil }
        guard var layout = try? JSONDecoder().decode(ControlLayout.self, from: data) else { return nil }
        layout = Self.migrate(layout)
        return layout
    }

    /// Bổ sung các nút mới (vd nút chuột) vào bố cục đã lưu từ bản cũ.
    ///
    /// Layout cũ lưu JSON đúng danh sách nút tại thời điểm đó. Khi app thêm
    /// nút mới (chuột trái/phải), game đã lưu sẽ không có → bổ sung vào vị
    /// trí mặc định nếu chưa có slot đó.
    static func migrate(_ layout: ControlLayout) -> ControlLayout {
        var result = layout
        let existing = Set(result.buttons.map { $0.slotID })
        // Các nút chuột chỉ thêm cho layout không phải visual novel.
        if !existing.contains("mouseL"), !existing.contains("advance") {
            result.buttons.append(ControlButton(slotID: "mouseL", x: 0.62, y: 0.90,
                                                size: 58, vk: VirtualKey.mouseLeft))
        }
        if !existing.contains("mouseR"), !existing.contains("advance") {
            result.buttons.append(ControlButton(slotID: "mouseR", x: 0.72, y: 0.72,
                                                size: 54, vk: VirtualKey.mouseRight))
        }
        return result
    }

    func save(_ layout: ControlLayout, for gameName: String) {
        guard let data = try? JSONEncoder().encode(layout) else { return }
        try? data.write(to: fileURL(for: gameName), options: .atomic)
    }

    /// Xoá bố cục đã lưu (về preset mặc định).
    func reset(for gameName: String) {
        try? FileManager.default.removeItem(at: fileURL(for: gameName))
    }
}

// MARK: - Nút ảo (multi-touch)

/// Vòng sóng của một lần chạm: luôn lan từ cỡ nút tới 1.75× rồi mờ hẳn.
private struct RippleRing: View {
    static let duration = 0.4
    @State private var expanded = false

    var body: some View {
        Circle()
            .stroke(Color.white, lineWidth: 2.5)
            .scaleEffect(expanded ? 1.75 : 1)
            .opacity(expanded ? 0 : 0.9)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeOut(duration: Self.duration)) { expanded = true }
            }
    }
}

/// Một nút phím ảo trên overlay: hỗ trợ **nhiều ngón cùng lúc** (di chuyển +
/// bấm xác nhận đồng thời) và **giữ phím** (dash, skip).
///
/// Phản hồi thị giác không phụ thuộc thời gian giữ ngón: chạm nhanh chỉ
/// ~50–80 ms, animation lúc ấn mà chạy theo `pressed` thì chưa kịp hiện đã
/// bị nhả → chỉ còn rung. Nên:
/// - Ấn: đổi trạng thái **tức thì** (không animation) — luôn có ít nhất 1 khung hình sáng.
/// - Nhả: mờ dần 0.22 s.
/// - Mỗi lần chạm thêm một vòng sóng **riêng** (`RippleRing`) lan trọn 0.4 s
///   rồi bị gỡ. Không dùng một `keyframeAnimator` chung: chạm lại khi vòng cũ
///   chưa xong thì animation mới nối tiếp đà cũ → vòng phình to dần.
private struct KeyPadButton: View {
    let button: ControlButton
    let opacity: Double
    let onDown: () -> Void
    let onUp: () -> Void
    /// Phím có thực sự tới game không (nil = chưa biết/không theo dõi).
    let isAccepted: Bool?
    @State private var pressed = false
    @State private var taps = 0
    @State private var ripples: [Int] = []
    private static let maxRipples = 3

    var body: some View {
        ZStack {
            ForEach(ripples, id: \.self) { _ in
                RippleRing().transition(.identity)
            }

            Circle()
                .fill(pressed
                      ? AnyShapeStyle(RadialGradient(colors: [.white, Color(white: 0.82)],
                                                     center: .center, startRadius: 0, endRadius: button.size * 0.6))
                      : AnyShapeStyle(LinearGradient(colors: [Color.white.opacity(0.10 + opacity * 0.25),
                                                              Color.black.opacity(0.35 + opacity * 0.4)],
                                                     startPoint: .top, endPoint: .bottom)))

            Circle()
                .strokeBorder(borderColor, lineWidth: pressed ? 2.5 : 1.5)

            label
                .foregroundStyle(pressed ? Color.black.opacity(0.85) : Color.white.opacity(max(opacity, 0.6) + 0.2))
        }
        .frame(width: button.size, height: button.size)
        .scaleEffect(pressed ? 0.88 : 1.0)
        .shadow(color: pressed ? Color.white.opacity(0.7) : Color.black.opacity(0.45),
                radius: pressed ? 14 : 4)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !pressed else { return }
                    var instant = Transaction()
                    instant.disablesAnimations = true
                    withTransaction(instant) { pressed = true }
                    taps += 1
                    let id = taps
                    withTransaction(instant) {
                        ripples.append(id)
                        if ripples.count > Self.maxRipples { ripples.removeFirst() }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + RippleRing.duration + 0.05) {
                        withTransaction(instant) { ripples.removeAll { $0 == id } }
                    }
                    // Rung chỉ khi người dùng BẬT trong Cài đặt.
                    AppSettings.impact(0.75)
                    onDown()
                }
                .onEnded { _ in
                    withAnimation(.easeOut(duration: 0.22)) { pressed = false }
                    onUp()
                }
        )
        .accessibilityLabel(button.vk.label)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var label: some View {
        if let symbol = button.vk.symbol {
            Image(systemName: symbol)
                .font(.system(size: button.size * 0.32, weight: .bold))
        } else {
            Text(button.vk.label)
                .font(.system(size: button.size * (button.vk.label.count > 2 ? 0.22 : 0.32),
                              weight: .heavy, design: .rounded))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .padding(.horizontal, 4)
        }
    }

    /// Màu viền: xanh lá = game đã nhận phím; trắng = bình thường; đỏ = game
    /// **không nhận** phím (báo lỗi) → người dùng biết ngay nút đó hỏng.
    private var borderColor: Color {
        switch isAccepted {
        case .some(true):  return Color.green.opacity(0.95)
        case .some(false): return Color.red.opacity(0.95)
        case nil:          return Color.white.opacity(pressed ? 1 : 0.55)
        }
    }
}

// MARK: - Màn điều khiển ảo

/// Overlay hiển thị các nút ảo lên trên WebView.
///
/// Nút bắn phím qua `fireKey` (down/up riêng để hỗ trợ giữ phím). Bố cục được
/// lưu theo từng game trong `ControlStore`.
struct VirtualGamepadView: View {
    let gameName: String
    let engine: EngineKind
    /// Safe-area của màn hình hiện tại — dùng để KẸP nút ảo vào vùng nhìn
    /// được. Ở ngang, iPhone có notch (safeArea.left/right ≈ 47–59pt) và
    /// home indicator (safeArea.bottom ≈ 21pt); nếu tính vị trí theo toàn màn
    /// hình thì nút bên phải lọt vào mép, bị cắt và đè lên game.
    var safeArea: EdgeInsets = EdgeInsets()
    /// Bắn sự kiện phím xuống WebView (down = true, up = false).
    let fireKey: (VirtualKey, _ down: Bool) -> Void
    /// Phiên bản có callback báo kết quả (game đã nhận phím hay không).
    /// Nếu không truyền thì mặc định dùng `fireKey`.
    var onFireKey: ((VirtualKey, _ down: Bool, @escaping (Bool, String?) -> Void) -> Void)?
    /// Bấm để mở màn hình tuỳ chỉnh.
    let onEdit: () -> Void

    @State private var layout: ControlLayout?
    @State private var dragOffset: CGSize = .zero
    @State private var draggingID: String?
    @State private var editMode = false
    /// Trạng thái gửi phím cho từng nút: true = game đã nhận, false = lỗi,
    /// nil = chưa thử. Dùng để tô viền xanh/đỏ → người dùng biết nút nào
    /// đang hoạt động và nút nào hỏng.
    @State private var acceptState: [String: Bool] = [:]

    var body: some View {
        GeometryReader { geo in
            let layout = resolvedLayout
            ZStack {
                ForEach(layout.buttons) { btn in
                    keyButton(btn, in: geo.size, layout: layout)
                }

                // Tay cầm kéo toàn bộ (chỉ trong edit mode)
                if editMode {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "hand.draw")
                                .foregroundStyle(.white)
                                .padding(10)
                                .background(.ultraThinMaterial, in: Circle())
                                .padding(8)
                        }
                        Spacer()
                    }
                    .padding(.top, safeArea.top)
                    .padding(.trailing, safeArea.trailing)
                    .allowsHitTesting(false)
                }
            }
            // Nút edit nhỏ ở góc — chỉ hiện trong edit mode.
            // Canh theo safe-area để không bị lọt vào vùng notch/Dynamic Island.
            .overlay(alignment: .topTrailing) {
                if editMode {
                    Button {
                        onEdit()
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .padding(.trailing, safeArea.trailing + 8)
                    .padding(.top, safeArea.top + 8)
                }
            }
        }
        .onAppear { layout = ControlStore.shared.load(for: gameName) }
        // LƯU Ý: KHÔNG có contentShape(Rectangle())/onTapGesture phủ full màn —
        // chúng chặn toàn bộ touch của game bên dưới (nguyên nhân màn đen
        // tưởng tải được nhưng bấm không ăn). Chỉ các nút nhận touch.
        .allowsHitTesting(true)
    }

    private var resolvedLayout: ControlLayout {
        if let layout { return layout }
        return ControlPresets.forEngine(engine)
    }

    private func keyButton(_ btn: ControlButton, in size: CGSize, layout: ControlLayout) -> some View {
        let isDragging = draggingID == btn.slotID && editMode
        let rect = usableRect(in: size)
        let x = rect.minX + min(max(btn.x, 0), 1) * rect.width
        let y = rect.minY + min(max(btn.y, 0), 1) * rect.height

        return KeyPadButton(
            button: btn,
            opacity: editMode ? 0.85 : layout.opacity,
            onDown: {
                guard !editMode else { return }
                sendKey(btn.vk, true)
            },
            onUp: {
                guard !editMode else { return }
                sendKey(btn.vk, false)
            },
            isAccepted: acceptState[btn.slotID]
        )
        .position(
            x: x + (isDragging ? dragOffset.width : 0),
            y: y + (isDragging ? dragOffset.height : 0)
        )
        .gesture(editMode ? dragGesture(btn, in: size) : nil)
        // Double-tap nút trong edit mode để đổi phím. Chỉ gắn khi đang chỉnh:
        // nhận diện chạm đôi bắt iOS chờ xem có chạm lần 2 không → nút trễ.
        .simultaneousGesture(editMode ? TapGesture(count: 2).onEnded { onEdit() } : nil)
    }

    /// Bắn phím xuống game và cập nhật trạng thái "game đã nhận chưa".
    ///
    /// `fireKey` báo lại qua callback (xem `GameWebView.fireKey`) → nếu script
    /// lỗi (game chết / trang trắng) thì nút sẽ viền **đỏ** thay vì im lặng.
    private func sendKey(_ vk: VirtualKey, _ down: Bool) {
        let handler: (Bool, String?) -> Void = { ok, err in
            Task { @MainActor in
                self.acceptState[vk.code] = ok
                if !ok, let err {
                    AppLog.error("Nút \(vk.label) không tới game: \(err)")
                    // Rung kiểu "cảnh báo" (nếu người dùng bật) để user biết
                    // chắc chắn nút hỏng.
                    AppSettings.notifyError()
                }
            }
        }
        if let onFireKey {
            onFireKey(vk, down, handler)
        } else {
            fireKey(vk, down)
        }
    }

    /// Vùng an toàn để đặt nút: bỏ notch (trái/phải) + home indicator (dưới).
    ///
    /// Ở chiều ngang trên iPhone có Dynamic Island/notch → `safeArea.left/right`
    /// khá lớn (≈47–59pt). Nút đặt theo tỉ lệ toàn màn sẽ nằm đúng vào vùng
    /// bị che → mất một phần nút và đè lên game.
    private func usableRect(in size: CGSize) -> CGRect {
        let left = min(max(safeArea.leading, 0), size.width * 0.2)
        let right = min(max(safeArea.trailing, 0), size.width * 0.2)
        let top = min(max(safeArea.top, 0), size.height * 0.2)
        let bottom = min(max(safeArea.bottom, 0), size.height * 0.2)
        let w = max(size.width - left - right, 1)
        let h = max(size.height - top - bottom, 1)
        return CGRect(x: left, y: top, width: w, height: h)
    }

    private func dragGesture(_ btn: ControlButton, in size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if draggingID != btn.slotID {
                    draggingID = btn.slotID
                    dragOffset = .zero
                }
                dragOffset = value.translation
            }
            .onEnded { value in
                var newLayout = resolvedLayout
                guard let idx = newLayout.buttons.firstIndex(where: { $0.slotID == btn.slotID }) else { return }
                let rect = usableRect(in: size)
                let dx = (value.translation.width) / rect.width
                let dy = (value.translation.height) / rect.height
                newLayout.buttons[idx].x = min(max(newLayout.buttons[idx].x + dx, 0), 1)
                newLayout.buttons[idx].y = min(max(newLayout.buttons[idx].y + dy, 0), 1)
                layout = newLayout
                ControlStore.shared.save(newLayout, for: gameName)
                draggingID = nil
                dragOffset = .zero
            }
    }
}

// MARK: - Màn hình tuỳ chỉnh bố cục

/// Sheet tuỳ chỉnh: đổi phím từng nút, reset về preset, chỉnh độ mờ.
struct GamepadSettingsView: View {
    let gameName: String
    let engine: EngineKind
    @Binding var layout: ControlLayout
    @Environment(\.dismiss) private var dismiss

    /// Nút đang được chọn để đổi phím (nil = không chọn).
    @State private var selectingFor: ControlButton?
    @State private var editingKey = false

    var body: some View {
        NavigationStack {
            List {
                Section("Cách kiểm tra nút có ấn được không") {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Viền xanh = game đã nhận phím", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Label("Viền đỏ = game không nhận (game chết / mất focus)", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                        Label("Nút ấn được sẽ rung tay + sáng trắng + phình to", systemImage: "hand.tap.fill")
                            .foregroundStyle(.secondary)
                        Text("Nếu tất cả nút đều viền đỏ → bấm vào game một lần để game có focus, rồi thử lại. Menu ⋯ → “Kiểm tra game” để xem chi tiết.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .font(.footnote)
                }

                Section("Độ mờ") {
                    HStack {
                        Image(systemName: "circle.lefthalf.filled")
                        Slider(value: $layout.opacity, in: 0.1...0.9, step: 0.05)
                        Text("\(Int(layout.opacity * 100))%")
                            .monospacedDigit()
                            .frame(width: 44)
                    }
                }

                Section("Nút bấm — bấm vào nút để đổi phím") {
                    ForEach($layout.buttons) { $btn in
                        Button {
                            selectingFor = btn
                            editingKey = true
                        } label: {
                            HStack {
                                Text(btn.vk.label)
                                    .font(.system(.body, design: .rounded).bold())
                                    .frame(width: 56, height: 36)
                                    .background(Color.blue.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
                                Text(slotName(btn.slotID))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text(btn.vk.code)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        layout = ControlPresets.forEngine(engine)
                        ControlStore.shared.save(layout, for: gameName)
                    } label: {
                        Label("Về preset mặc định của engine", systemImage: "arrow.counterclockwise")
                    }
                } footer: {
                    Text("Bố cục được lưu riêng cho từng game. Trên màn chơi, kéo nút (khi bật chế độ chỉnh) để đổi vị trí.")
                }
            }
            .navigationTitle("Tuỳ chỉnh điều khiển")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") {
                        ControlStore.shared.save(layout, for: gameName)
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $editingKey) {
                if let selecting = selectingFor {
                    KeyPickerView(selected: selecting.vk) { newKey in
                        if let idx = layout.buttons.firstIndex(where: { $0.slotID == selecting.slotID }) {
                            layout.buttons[idx].vk = newKey
                        }
                        ControlStore.shared.save(layout, for: gameName)
                    }
                    .presentationDetents([.medium, .large])
                }
            }
        }
    }

    private func slotName(_ id: String) -> String {
        switch id {
        case "up": return "Lên"
        case "down": return "Xuống"
        case "left": return "Trái"
        case "right": return "Phải"
        case "ok": return "Xác nhận"
        case "cancel": return "Huỷ / Menu"
        case "dash": return "Chạy nhanh"
        case "menu": return "Menu"
        case "advance": return "Kể chuyện tiếp"
        case "skip": return "Skip (giữ)"
        case "back": return "Log / Quay lại"
        case "mouseL": return "Chuột trái"
        case "mouseR": return "Chuột phải"
        default: return id
        }
    }
}

/// Chọn phím để gán cho nút.
private struct KeyPickerView: View {
    let selected: VirtualKey
    let onPick: (VirtualKey) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [VirtualKey] {
        guard !query.isEmpty else { return VirtualKey.assignable }
        return VirtualKey.assignable.filter {
            $0.code.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List(filtered, id: \.self) { vk in
                Button {
                    onPick(vk)
                    dismiss()
                } label: {
                    HStack {
                        Text(vk.label)
                            .font(.system(.body, design: .rounded).bold())
                            .frame(width: 52, height: 32)
                            .background(Color.blue.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
                        Text(vk.code)
                            .foregroundStyle(.primary)
                        Spacer()
                        if vk == selected {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Tìm phím (vd KeyZ, Enter)")
            .navigationTitle("Gán phím")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Huỷ") { dismiss() }
                }
            }
        }
    }
}
