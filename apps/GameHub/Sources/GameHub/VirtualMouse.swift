import SwiftUI
import WebKit

/// Chuột ảo kiểu touchpad: kéo ngón ở bất kỳ đâu → con trỏ di chuyển tương
/// đối (ngón tay không che chỗ cần bấm), chạm → click vào đúng điểm con trỏ.
/// Dùng cho game có chi tiết nhỏ, chạm trực tiếp bằng ngón tay khó trúng.
enum VirtualMouse {
    enum Action: String {
        case move, down, up, click, rightClick
    }

    /// `window.__ghMouse(kind, x, y)`: bắn sự kiện vào phần tử dưới con trỏ
    /// theo đúng thứ tự trình duyệt làm với chuột thật (pointer* → mouse* →
    /// click), kèm over/out khi đổi phần tử để nút hover của game sáng lên.
    /// Toạ độ là CSS px = point vì viewport bị ép `initial-scale=1`.
    static let pageScript = #"""
    (function() {
      var hover = null, held = 0;
      function fire(el, Ctor, type, x, y, button, buttons) {
        var init = { bubbles: true, cancelable: true, composed: true, view: window,
                     clientX: x, clientY: y, screenX: x, screenY: y,
                     button: button, buttons: buttons,
                     pointerId: 1, pointerType: 'mouse', isPrimary: true,
                     width: 1, height: 1, pressure: buttons ? 0.5 : 0 };
        var ev;
        try { ev = new Ctor(type, init); } catch (e) { ev = new MouseEvent(type, init); }
        ev.__gh = true;
        el.dispatchEvent(ev);
      }
      var P = window.PointerEvent || MouseEvent;
      // Phần tử trong shadow DOM (Ruffle: canvas nằm trong <ruffle-embed>) chỉ nhận sự kiện gửi thẳng
      // vào nó; gửi vào thẻ ngoài thì listener của canvas không bao giờ chạy.
      function deepElementFromPoint(x, y) {
        var el = document.elementFromPoint(x, y) || document.body;
        while (el && el.shadowRoot) {
          var inner = el.shadowRoot.elementFromPoint(x, y);
          if (!inner || inner === el) break;
          el = inner;
        }
        return el;
      }
      window.__ghMouse = function(kind, x, y) {
        var el = deepElementFromPoint(x, y);
        if (el !== hover) {
          if (hover && hover.isConnected) {
            fire(hover, P, 'pointerout', x, y, 0, held);
            fire(hover, MouseEvent, 'mouseout', x, y, 0, held);
            fire(hover, MouseEvent, 'mouseleave', x, y, 0, held);
          }
          fire(el, P, 'pointerover', x, y, 0, held);
          fire(el, MouseEvent, 'mouseover', x, y, 0, held);
          fire(el, MouseEvent, 'mouseenter', x, y, 0, held);
          hover = el;
        }
        function press(button) {
          held = button === 2 ? 2 : 1;
          fire(el, P, 'pointerdown', x, y, button, held);
          fire(el, MouseEvent, 'mousedown', x, y, button, held);
        }
        function release(button) {
          held = 0;
          fire(el, P, 'pointerup', x, y, button, 0);
          fire(el, MouseEvent, 'mouseup', x, y, button, 0);
        }
        switch (kind) {
          case 'move':
            fire(el, P, 'pointermove', x, y, 0, held);
            fire(el, MouseEvent, 'mousemove', x, y, 0, held);
            break;
          case 'down': press(0); break;
          case 'up': release(0); break;
          case 'click': press(0); release(0); fire(el, MouseEvent, 'click', x, y, 0, 0); break;
          case 'rightClick':
            press(2); release(2);
            fire(el, MouseEvent, 'auxclick', x, y, 2, 0);
            fire(el, MouseEvent, 'contextmenu', x, y, 2, 0);
            break;
        }
        return el.tagName;
      };
    })();
    """#

    static func send(_ webView: WKWebView, _ action: Action, at point: CGPoint,
                     completion: ((Bool) -> Void)? = nil) {
        let js = "window.__ghMouse && window.__ghMouse('\(action.rawValue)', \(Int(point.x.rounded())), \(Int(point.y.rounded())))"
        webView.evaluateJavaScript(js) { _, error in
            if let error, action != .move {
                AppLog.warn("Chuột ảo (\(action.rawValue)) không tới game: \(error.localizedDescription)")
            }
            completion?(error == nil)
        }
    }

    /// Hệ số tốc độ theo vận tốc ngón (point/giây): kéo chậm → con trỏ đi chậm
    /// hơn ngón để nhắm chi tiết nhỏ; vuốt nhanh → đi xa hơn.
    static func gain(forSpeed speed: CGFloat) -> CGFloat {
        min(max(0.5 + speed / 900, 0.5), 2.4)
    }
}

/// Lớp phủ touchpad + con trỏ vẽ trên game.
///
/// - Kéo 1 ngón: di chuyển con trỏ.
/// - Chạm: click trái.
/// - Giữ yên ~0.5 s: click phải.
/// - Chạm rồi chạm lại trong 0.3 s và giữ: giữ chuột trái (kéo-thả), nhả ngón = nhả chuột.
struct VirtualMouseView: View {
    let webView: () -> WKWebView?

    @State private var cursor: CGPoint?
    @State private var touchStart: Date?
    @State private var lastLocation: CGPoint = .zero
    @State private var lastMoveAt = Date()
    @State private var travelled: CGFloat = 0
    @State private var holding = false
    @State private var longPressFired = false
    @State private var longPressTask: Task<Void, Never>?
    @State private var lastTapEnd = Date.distantPast
    @State private var movePending = false
    @State private var moveQueued = false
    @State private var clicks = 0
    @State private var rightClicks = 0
    @State private var showHint = true

    private static let tapSlop: CGFloat = 8
    private static let doubleTapWindow: TimeInterval = 0.3
    private static let longPress: UInt64 = 500_000_000

    var body: some View {
        GeometryReader { geo in
            let point = cursor ?? CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            ZStack(alignment: .topLeading) {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(trackpad(bounds: geo.size))

                ClickRipple(trigger: clicks, color: .white)
                    .position(point)
                ClickRipple(trigger: rightClicks, color: .orange)
                    .position(point)

                CursorArrow(pressed: holding)
                    .frame(width: 26, height: 26)
                    .offset(x: point.x, y: point.y)
                    .allowsHitTesting(false)

                if showHint {
                    hint
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 18)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
            .onAppear {
                if cursor == nil { cursor = point }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                    withAnimation(.easeOut(duration: 0.4)) { showHint = false }
                }
            }
            .onDisappear {
                longPressTask?.cancel()
                if holding, let wv = webView() { VirtualMouse.send(wv, .up, at: point) }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Touchpad chuột ảo")
        .accessibilityHint("Kéo để di chuyển con trỏ, chạm để click")
    }

    private var hint: some View {
        HStack(spacing: 14) {
            Label("Kéo: di chuyển", systemImage: "hand.draw")
            Label("Chạm: click", systemImage: "hand.tap")
            Label("Giữ: click phải", systemImage: "hand.point.up.left")
            Label("Chạm 2 lần + giữ: kéo", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .environment(\.colorScheme, .dark)
    }

    private func trackpad(bounds: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if touchStart == nil {
                    begin(at: value.location)
                } else {
                    move(to: value.location, bounds: bounds)
                }
            }
            .onEnded { _ in end() }
    }

    private func begin(at location: CGPoint) {
        let now = Date()
        touchStart = now
        lastLocation = location
        lastMoveAt = now
        travelled = 0
        longPressFired = false
        if showHint { withAnimation(.easeOut(duration: 0.3)) { showHint = false } }

        if now.timeIntervalSince(lastTapEnd) < Self.doubleTapWindow {
            holding = true
            fire(.down)
            AppSettings.impact(0.5)
            return
        }
        longPressTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.longPress)
            guard !Task.isCancelled, touchStart != nil, travelled < Self.tapSlop else { return }
            longPressFired = true
            rightClicks += 1
            fire(.rightClick)
            AppSettings.impact(0.9)
        }
    }

    private func move(to location: CGPoint, bounds: CGSize) {
        let now = Date()
        let dx = location.x - lastLocation.x
        let dy = location.y - lastLocation.y
        let distance = hypot(dx, dy)
        let dt = max(now.timeIntervalSince(lastMoveAt), 1.0 / 240)
        lastLocation = location
        lastMoveAt = now
        travelled += distance
        if travelled >= Self.tapSlop { longPressTask?.cancel() }
        guard distance > 0, !longPressFired else { return }

        let gain = VirtualMouse.gain(forSpeed: distance / CGFloat(dt))
        let current = cursor ?? CGPoint(x: bounds.width / 2, y: bounds.height / 2)
        cursor = CGPoint(x: min(max(current.x + dx * gain, 0), bounds.width - 1),
                         y: min(max(current.y + dy * gain, 0), bounds.height - 1))
        sendMove()
    }

    private func end() {
        longPressTask?.cancel()
        let tapped = travelled < Self.tapSlop
        if holding {
            holding = false
            fire(tapped ? .click : .up)
            if tapped { clicks += 1 }
        } else if tapped && !longPressFired {
            clicks += 1
            fire(.click)
            AppSettings.impact(0.6)
            lastTapEnd = Date()
        }
        touchStart = nil
    }

    /// Gộp các lần di chuyển: chỉ một lệnh `move` chạy trong trang tại một
    /// thời điểm, xong thì gửi vị trí mới nhất.
    private func sendMove() {
        guard !movePending else { moveQueued = true; return }
        guard let wv = webView(), let point = cursor else { return }
        movePending = true
        VirtualMouse.send(wv, .move, at: point) { _ in
            movePending = false
            if moveQueued {
                moveQueued = false
                sendMove()
            }
        }
    }

    private func fire(_ action: VirtualMouse.Action) {
        guard let wv = webView(), let point = cursor else { return }
        VirtualMouse.send(wv, action, at: point)
    }
}

/// Mũi tên con trỏ, đầu nhọn ở góc trên trái của khung (= điểm click).
private struct CursorArrow: View {
    let pressed: Bool

    var body: some View {
        ArrowShape()
            .fill(pressed ? Color(white: 0.8) : .white)
            .overlay(ArrowShape().stroke(.black, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round)))
            .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
            .scaleEffect(pressed ? 0.9 : 1, anchor: .topLeading)
            .animation(.easeOut(duration: 0.1), value: pressed)
    }

    private struct ArrowShape: Shape {
        func path(in rect: CGRect) -> Path {
            let w = rect.width, h = rect.height
            var p = Path()
            p.move(to: CGPoint(x: 0, y: 0))
            p.addLine(to: CGPoint(x: 0, y: h * 0.86))
            p.addLine(to: CGPoint(x: w * 0.24, y: h * 0.66))
            p.addLine(to: CGPoint(x: w * 0.40, y: h))
            p.addLine(to: CGPoint(x: w * 0.54, y: h * 0.93))
            p.addLine(to: CGPoint(x: w * 0.39, y: h * 0.61))
            p.addLine(to: CGPoint(x: w * 0.66, y: h * 0.61))
            p.closeSubpath()
            return p
        }
    }
}

/// Vòng lan nhỏ tại điểm click. Mỗi lần trigger đổi → vòng mới riêng (không
/// cộng dồn như keyframeAnimator dùng chung).
private struct ClickRipple: View {
    let trigger: Int
    let color: Color

    var body: some View {
        ZStack {
            if trigger > 0 {
                Ring(color: color).id(trigger)
            }
        }
        .allowsHitTesting(false)
    }

    private struct Ring: View {
        let color: Color
        @State private var expanded = false

        var body: some View {
            Circle()
                .stroke(color, lineWidth: 2)
                .frame(width: 34, height: 34)
                .scaleEffect(expanded ? 1 : 0.2)
                .opacity(expanded ? 0 : 0.9)
                .onAppear { withAnimation(.easeOut(duration: 0.35)) { expanded = true } }
        }
    }
}
