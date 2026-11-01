import SwiftUI
import WebKit

/// Giữ tham chiếu `WKWebView` đang chạy — dùng để bắn phím từ bên ngoài.
///
/// ⚠️ Vì sao không dùng `@State var webView: WKWebView?` trong view cha?
/// `onWebViewReady` được gọi **bên trong `makeUIView`**, tức là giữa chừng
/// quá trình update của SwiftUI. Gán `@State` ở thời điểm đó bị SwiftUI bỏ
/// qua → `webView` vẫn là `nil` → bấm nút ảo báo "WebView chưa sẵn sàng".
///
/// Holder là **class** (reference type) nên gán ở bất kỳ lúc nào cũng có hiệu
/// lực, không phụ thuộc thời điểm update.
final class WebViewHolder: ObservableObject {
    @Published private(set) var webView: WKWebView?

    func attach(_ wv: WKWebView) {
        webView = wv
    }

    func detach() {
        webView = nil
    }
}

/// WebView full màn hình, load game qua LocalWebServer.
///
/// Kèm hệ **phím ảo**: `fireKey(code:key:down:)` bắn `KeyboardEvent` thật vào
/// trang (tập trung vào phần tử đang focus, fallback `document.body`) — game
/// web (RPG Maker, Godot, Ren'Py, Ruffle…) nhận như bàn phím vật lý.
struct GameWebView: UIViewRepresentable {
    let url: URL
    /// Engine của game đang mở — quyết định polyfill JS cần inject
    /// (vd: TyranoBuilder cần stub `require('fs')` vì configSave=file).
    var engine: EngineKind = .unknown
    /// Được gọi 1 lần sau khi WebView tạo xong (để GamePlayView giữ tham chiếu bắn phím).
    var onWebViewReady: ((WKWebView) -> Void)?
    /// Trang chính load xong (`didFinish`) — GamePlayView ẩn màn khởi động.
    var onPageLoaded: (() -> Void)?

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []  // autoplay audio/video (game cần)
        // Chạm không ăn (nút/overlay của game không phản hồi) → log phần tử nhận chạm và
        // xem `click` có tới nơi không. Chỉ 40 lần chạm đầu để log không phình.
        config.userContentController.addUserScript(WKUserScript(source: """
        (function() {
          var n = 0;
          function desc(el) {
            return el ? el.tagName + (el.id ? '#' + el.id : '') + (el.className && el.className.baseVal === undefined ? '.' + String(el.className).split(' ').join('.') : '') : 'null';
          }
          window.addEventListener('pointerdown', function(e) {
            if (n++ >= 40) return;
            var top = document.elementFromPoint(e.clientX, e.clientY);
            console.log('[tap] ' + e.pointerType + ' ' + Math.round(e.clientX) + ',' + Math.round(e.clientY) +
              ' → ' + desc(top) + ' (target ' + desc(e.target) + ') vp ' + innerWidth + 'x' + innerHeight);
          }, true);
          window.addEventListener('click', function(e) {
            if (n <= 40) console.log('[click] ' + desc(e.target));
          }, true);
        })();
        """, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        // iPhone vẫn mở trình phát toàn màn hình cho <video> thiếu `playsinline`
        // (vd plugin YSP_VideoPlayer của RPG Maker) → game mất cảnh, đơ.
        config.userContentController.addUserScript(WKUserScript(source: """
        (function() {
          var play = HTMLMediaElement.prototype.play;
          HTMLMediaElement.prototype.play = function() {
            if (this instanceof HTMLVideoElement) this.playsInline = true;
            if (this.__ghPriming) { this.__ghPriming = false; this.muted = this.__ghMuted; }
            return play.apply(this, arguments);
          };
          // iPhone không tải trước video chưa phát (dừng ở loadedmetadata) → game chờ
          // `canplay` mãi (vd YSP_VideoPlayer.isReady()). Phát tắt tiếng một nhịp để
          // iOS tải dữ liệu, rồi dừng + tua về 0, trừ khi game đã tự gọi play().
          function prime(el) {
            if (!el.paused || el.readyState >= 3) return;
            el.__ghMuted = el.muted;
            el.__ghPriming = true;
            el.muted = true;
            var done = function() {
              if (el.__ghPriming) { el.pause(); el.currentTime = 0; el.muted = el.__ghMuted; }
              el.__ghPriming = false;
            };
            play.call(el).then(done, done);
          }
          var create = Document.prototype.createElement;
          Document.prototype.createElement = function(tag) {
            var el = create.apply(this, arguments);
            if (el instanceof HTMLVideoElement) {
              el.playsInline = true;
              el.addEventListener('loadedmetadata', function() { prime(el); });
              // Game chờ video sẵn sàng mà không báo lỗi → log để biết kẹt ở bước nào.
              ['loadedmetadata', 'canplay', 'playing', 'stalled', 'waiting', 'ended', 'error'].forEach(function(ev) {
                el.addEventListener(ev, function() {
                  var name = (el.currentSrc || el.src || '').split('/').pop();
                  console.log('[video] ' + ev + ' ' + decodeURIComponent(name) +
                    (el.error ? ' code=' + el.error.code + ' ' + (el.error.message || '') : ''));
                });
              });
            }
            return el;
          };
        })();
        """, injectionTime: .atDocumentStart, forMainFrameOnly: false))

        // Dùng data store mặc định (lưu vào đĩa) để **giữ save game**:
        // game web lưu save trong IndexedDB/localStorage. Nếu dùng
        // `.nonPersistent()`, mọi save sẽ mất khi app đóng lại.
        config.websiteDataStore = .default()

        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        config.defaultWebpagePreferences = preferences

        // Bắt console + lỗi JS của game -> AppLog (xem qua màn Debug).
        // Error object: JSON.stringify ra "{}" → lấy message + stack. Lỗi trong
        // promise (fetch/đọc file hỏng) không qua onerror → unhandledrejection.
        let consoleSource = [
            "(function() {",
            "  var describe = function(a) {",
            "    if (a instanceof Error) return a.name + ': ' + a.message + (a.stack ? '\\n' + a.stack : '');",
            "    try { return typeof a === 'object' ? JSON.stringify(a) : String(a); }",
            "    catch (e) { return String(a); }",
            "  };",
            "  var send = function(level, args) {",
            "    try {",
            "      window.webkit.messageHandlers.jsLog.postMessage({",
            "        level: level,",
            "        text: Array.prototype.map.call(args, describe).join(' ')",
            "      });",
            "    } catch (e) {}",
            "  };",
            "  ['error', 'warn', 'log', 'info', 'debug'].forEach(function(level) {",
            "    var orig = console[level].bind(console);",
            "    console[level] = function() { send(level, arguments); orig.apply(console, arguments); };",
            "  });",
            "  window.onerror = function(msg, src, line, col, err) {",
            "    send('error', ['[onerror] ' + msg + ' @' + src + ':' + line + (err && err.stack ? '\\n' + err.stack : '')]);",
            "  };",
            "  window.addEventListener('unhandledrejection', function(ev) {",
            "    send('error', ['[unhandledrejection]', ev.reason]);",
            "  });",
            "})();",
        ].joined(separator: "\n")
        let consoleScript = WKUserScript(
            source: consoleSource,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true)
        config.userContentController.addUserScript(consoleScript)
        config.userContentController.add(context.coordinator, name: "jsLog")

        // Bảng chỉnh thông số: phải chạy trước engine để bắt được WebAssembly.Memory.
        if let cheatURL = Bundle.module.resourceURL?.appendingPathComponent("Cheat/cheat.js"),
           let cheatSource = try? String(contentsOf: cheatURL, encoding: .utf8) {
            config.userContentController.addUserScript(WKUserScript(
                source: cheatSource, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        } else {
            AppLog.warn("Không đọc được Cheat/cheat.js — bảng chỉnh thông số không dùng được")
        }

        // Ép viewport chuẩn cho mọi game. Game web desktop (RPG Maker MZ…) hay chỉ
        // có `user-scalable=no` → WebKit dàn trang theo bề rộng ảo 980 px rồi thu
        // nhỏ; trang tải lúc còn dọc rồi mới xoay ngang nên engine tính khung game
        // theo kích thước sai → tràn màn. viewport-fit=cover: dùng cả vùng tai thỏ
        // (màn ngang ~2.17:1 rộng hơn game 16:9/4:3 nên tai thỏ rơi vào dải đen).
        let viewportSource = """
        (function() {
          var fit = \(engine == .genericWeb ? "true" : "false");
          var k = 1, baseW = 0;
          // k > 1: viewport ảo rộng k lần cùng tỉ lệ màn → iOS co cả trang lại k lần (vừa màn).
          var content = function() {
            if (k <= 1) return 'width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover';
            return 'width=' + Math.round(baseW * k) + ', user-scalable=no, viewport-fit=cover';
          };
          var apply = function() {
            var metas = document.querySelectorAll('meta[name="viewport"]');
            if (metas.length === 0) {
              var m = document.createElement('meta');
              m.name = 'viewport';
              (document.head || document.documentElement).appendChild(m);
              metas = [m];
            }
            for (var i = 0; i < metas.length; i++) metas[i].setAttribute('content', content());
          };
          // Game web khung cố định (html/body overflow:hidden) nhưng đặt min-width/min-height lớn hơn
          // màn điện thoại → bị cắt mất phần tràn (vd nút ở đáy). Trang cuộn được thì không đụng.
          var hidden = function(el) {
            var st = getComputedStyle(el);
            return st.overflow === 'hidden' || (st.overflowX === 'hidden' && st.overflowY === 'hidden');
          };
          // Khung game = phần tử cha lớn nhất của phần tử ở giữa màn (không tính panel trượt ngoài màn).
          var stageSize = function() {
            var el = document.elementFromPoint(innerWidth / 2, innerHeight / 2), w = 0, h = 0;
            while (el && el !== document.body && el !== document.documentElement) {
              var r = el.getBoundingClientRect();
              w = Math.max(w, r.width); h = Math.max(h, r.height);
              el = el.parentElement;
            }
            return { w: w, h: h };
          };
          var fitCheck = function(tries) {
            var de = document.documentElement, b = document.body;
            if (!fit || !b || tries > 4 || !(hidden(de) || hidden(b))) return;
            var s = stageSize();
            var need = Math.max(s.w / innerWidth, s.h / innerHeight);
            if (need < 1.03 || need > 3) return;
            if (k === 1) baseW = innerWidth;
            k = Math.min(3, k * need);
            apply();
            setTimeout(function() { fitCheck(tries + 1); }, 400);
          };
          var reset = function() {
            if (k === 1) { setTimeout(function() { fitCheck(0); }, 600); return; }
            k = 1; apply();
            setTimeout(function() { fitCheck(0); }, 600);
          };
          if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', apply); else apply();
          window.addEventListener('load', function() { setTimeout(function() { fitCheck(0); }, 600); });
          if (window.matchMedia) matchMedia('(orientation: portrait)').addEventListener('change', reset);
          new MutationObserver(function(list) {
            for (var i = 0; i < list.length; i++) {
              for (var j = 0; j < list[i].addedNodes.length; j++) {
                var n = list[i].addedNodes[j];
                if (n.nodeName === 'META' && n.name === 'viewport' && n.getAttribute('content') !== content()) n.setAttribute('content', content());
              }
            }
          }).observe(document.documentElement, { childList: true, subtree: true });
        })();
        """
        config.userContentController.addUserScript(WKUserScript(
            source: viewportSource, injectionTime: .atDocumentStart, forMainFrameOnly: true))

        // Unity WebGL: game gọi Screen.SetResolution (vd 1280x720) → Unity khoá buffer canvas ở cỡ đó,
        // không theo kích thước hiển thị nữa → khung hình bị cắt/tràn trên màn ngang ~2.17:1.
        // Giữ buffer = kích thước CSS × devicePixelRatio, đúng cỡ Unity tự đặt; thấp hơn thì Unity vẫn
        // dựng theo cỡ đầy đủ rồi bị cắt, game hiện phóng to một góc.
        if engine == .unityWebGL {
            config.userContentController.addUserScript(WKUserScript(source: """
            (function() {
              var sync = function() {
                var c = document.querySelector('#unity-canvas');
                if (!c) return;
                var d = window.devicePixelRatio || 1, r = c.getBoundingClientRect(), w = Math.round(r.width * d), h = Math.round(r.height * d);
                if (w > 0 && h > 0 && (c.width !== w || c.height !== h)) { c.width = w; c.height = h; }
              };
              setInterval(sync, 500);
              window.addEventListener('resize', sync);
            })();
            """, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }

        // Đếm phím ảo thực sự tới trang (listener capture ở window chạy trước
        // mọi listener của game) — "Kiểm tra game" dùng số này thay cho
        // document.hasFocus(): bấm nút native của app luôn làm trang mất focus,
        // còn phím ảo bắn bằng dispatchEvent thì không cần focus.
        config.userContentController.addUserScript(WKUserScript(source: """
        (function() {
          window.__ghKeys = { count: 0, last: '', at: 0 };
          window.addEventListener('keydown', function(e) {
            if (!e.__gh || e.__ghCounted) return;
            e.__ghCounted = true;
            __ghKeys.count++; __ghKeys.last = e.code; __ghKeys.at = Date.now();
          }, true);
        })();
        """, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        config.userContentController.addUserScript(WKUserScript(
            source: VirtualMouse.pageScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))

        // Shim localStorage/sessionStorage dự phòng (chạy TRƯỚC mọi script game).
        //
        // iOS có thể ném SecurityError khi truy cập localStorage với origin
        // http://127.0.0.1 (không được coi là trustworthy). Code engine cũ
        // (Tyrano kag.js, RPG Maker) bắt lỗi này rồi trả chuỗi "null" thay vì
        // null → eval → biến save `sf` = null → crash
        // "null is not an object (evaluating 'that.variable.sf...')".
        //
        // Shim: nếu storage thật dùng được thì giữ nguyên; nếu bị chặn thì
        // thay bằng bản in-memory — game chạy được (không crash), save giữ
        // trong phiên (mất khi thoát app, nhưng hơn là không chơi được).
        let storageShim = """
        (function() {
          try {
            window.localStorage.getItem('__probe__');
            return;  // storage hoạt động bình thường
          } catch (e) {}
          var mem = {};
          var shim = {
            getItem: function(k) { return Object.prototype.hasOwnProperty.call(mem, k) ? mem[k] : null; },
            setItem: function(k, v) { mem[k] = String(v); },
            removeItem: function(k) { delete mem[k]; },
            clear: function() { mem = {}; },
            key: function(i) { var ks = Object.keys(mem); return i < ks.length ? ks[i] : null; }
          };
          Object.defineProperty(shim, 'length', { get: function() { return Object.keys(mem).length; } });
          try {
            Object.defineProperty(window, 'localStorage', { value: shim, configurable: true });
            Object.defineProperty(window, 'sessionStorage', { value: shim, configurable: true });
            console.warn('localStorage bị chặn — dùng shim in-memory (save không giữ lâu dài)');
          } catch (e2) {}
        })();
        """
        let storageShimScript = WKUserScript(
            source: storageShim,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true)
        config.userContentController.addUserScript(storageShimScript)

        // TyranoBuilder: không giả lập Node. Có `process` + `require` là Tyrano 5
        // tưởng đang chạy NW.js và đi đường lưu file (cần electron.remote).
        // Chế độ configSave=file được đổi sang webstorage ở TyranoPatch.
        if engine == .rpgMakerMV {
            config.userContentController.addUserScript(WKUserScript(
                source: ElectronShim.source, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }

        let webview = WKWebView(frame: .zero, configuration: config)
        webview.navigationDelegate = context.coordinator
        webview.scrollView.isScrollEnabled = false          // game tự xử lý touch
        // Trang chiếm trọn màn hình (không chừa safe area) — engine tự đóng khung
        // đen giữ tỉ lệ; xem viewport-fit=cover ở trên.
        webview.scrollView.contentInsetAdjustmentBehavior = .never
        webview.scrollView.bounces = false
        webview.allowsBackForwardNavigationGestures = false
        webview.backgroundColor = .black
        webview.isOpaque = false

        // Giữ màn hình không tắt khi chơi
        UIApplication.shared.isIdleTimerDisabled = true

        webview.load(URLRequest(url: url))
        context.coordinator.webView = webview
        context.coordinator.onPageLoaded = onPageLoaded
        onWebViewReady?(webview)
        return webview
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.onPageLoaded = onPageLoaded
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        UIApplication.shared.isIdleTimerDisabled = false
        coordinator.webView = nil
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?
        var onPageLoaded: (() -> Void)?

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == "jsLog",
                  let body = message.body as? [String: Any],
                  let level = body["level"] as? String,
                  let text = body["text"] as? String else { return }
            switch level {
            case "error": AppLog.error("JS: \(text)")
            case "warn": AppLog.warn("JS: \(text)")
            default: AppLog.info("JS: \(text)")
            }
        }

        func webView(_ webView: WKWebView, decide policy: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            AppLog.info("→ NAV \(webView.url?.absoluteString ?? "?")")
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationResponse: WKNavigationResponse,
                     decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            if let http = navigationResponse.response as? HTTPURLResponse {
                AppLog.info("← RESP \(http.statusCode) \(navigationResponse.response.url?.lastPathComponent ?? "?")")
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            AppLog.info("→ BẮT ĐẦU nạp: \(webView.url?.absoluteString ?? "?")")
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            AppLog.error("Navigation lỗi: \(error.localizedDescription)")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            AppLog.error("Không tải được trang: \(error.localizedDescription)")
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            AppLog.ok("Trang load xong: \(webView.url?.path ?? "?")")
            onPageLoaded?()
        }

        /// ⚠️ WebKit giết tiến trình web khi vượt giới hạn RAM → trang reload
        /// và game mất tiến trình. Đây là nguyên nhân khả dĩ nhất với game
        /// Godot có .pck hàng trăm MB (nạp hết vào RAM của trang).
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            AppLog.error("⚠️ WebKit giết tiến trình web (hết RAM) — game sẽ reload")
        }
    }

    // MARK: - Bảng chỉnh thông số

    /// Gọi lệnh của bảng chỉnh thông số (`window.__ghCheat`, xem Cheat/cheat.js).
    /// Lệnh quét trả Promise — `callAsyncJavaScript` đợi tới khi xong.
    @MainActor
    static func cheat(_ webView: WKWebView, _ name: String, _ args: [String: Any] = [:]) async throws -> Any? {
        try await webView.callAsyncJavaScript(
            "if (!window.__ghCheat) throw new Error('Trang game chưa có bảng chỉnh thông số'); return await window.__ghCheat.call(name, args);",
            arguments: ["name": name, "args": args], in: nil, contentWorld: .page)
    }

    // MARK: - Bắn phím ảo

    /// Bắn sự kiện phím (down/up) vào trang.
    ///
    /// Gửi **cả** `code` (phím vật lý) và `key` — engine nào đọc gì cũng nhận.
    /// Mọi listener được gọi theo thứ tự chuẩn: keydown → keypress → keyup.
    ///
    /// ## Phản hồi (quan trọng cho UX)
    /// Trước đây `completionHandler: nil` → **nuốt mọi lỗi**: game chết hoặc
    /// màn trắng thì nút vẫn "bấm được" trên UI nhưng không có gì xảy ra, người
    /// dùng không phân biệt được lỗi app với lỗi game. Nay callback trả về
    /// `Bool` (script có chạy được trong trang hay không) + lỗi JS nếu có.
    static func fireKey(_ webView: WKWebView,
                        vk: VirtualKey,
                        down: Bool,
                        completion: ((Bool, String?) -> Void)? = nil) {
        let type = down ? "keydown" : "keyup"
        let js = """
        (function() {
            var target = document.activeElement;
            if (!target || target === document.body) {
                var canvas = document.querySelector('canvas');
                target = canvas || document.body;
            }
            var ev = new KeyboardEvent(\(Self.jsString(type)), {
                key: \(Self.jsString(vk.key)),
                code: \(Self.jsString(vk.code)),
                keyCode: \(Self.keyCodeValue(vk)),
                which: \(Self.keyCodeValue(vk)),
                bubbles: true,
                cancelable: true,
                location: 0,
                repeat: false
            });
            // Engine cũ (RPG Maker…) đọc keyCode; constructor có thể bỏ qua
            // keyCode/which trong init → gán lại cho chắc.
            if (ev.keyCode !== \(Self.keyCodeValue(vk))) {
                Object.defineProperty(ev, 'keyCode', { get: function() { return \(Self.keyCodeValue(vk)); } });
                Object.defineProperty(ev, 'which', { get: function() { return \(Self.keyCodeValue(vk)); } });
            }
            ev.__gh = true;
            // bubbles: true → tự lan lên document rồi window. Dispatch thêm ở
            // document/window làm listener của game nhận 2–3 lần mỗi lần bấm.
            target.dispatchEvent(ev);
            return { ok: true };
        })();
        """
        webView.evaluateJavaScript(js) { result, error in
            if let error {
                AppLog.warn("Phím \(vk.code) (\(type)) không gửi được: \(error.localizedDescription)")
                completion?(false, error.localizedDescription)
                return
            }
            completion?(true, nil)
        }
    }

    /// Chữ gõ từ bàn phím hệ thống (`GameKeyboardField`). "\u{8}" = xoá, "\n" = Enter.
    /// Ô nhập HTML đang focus → chèn chữ thẳng vào ô (sự kiện phím giả không tự
    /// chèn chữ). Còn lại (game canvas) → keydown/keypress/keyup cho từng ký tự.
    static func typeText(_ webView: WKWebView, _ text: String) {
        let js = """
        (function(t) {
          var el = document.activeElement;
          var field = el && (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA') ? el : null;
          var rich = el && el.isContentEditable;
          var target = el && el !== document.body ? el : (document.querySelector('canvas') || document.body);
          function key(k, code, kc) {
            ['keydown', 'keypress', 'keyup'].forEach(function(type) {
              if (type === 'keypress' && kc < 32 && kc !== 13) return;
              var ev = new KeyboardEvent(type, { key: k, code: code, keyCode: kc, which: kc,
                charCode: type === 'keypress' ? kc : 0, bubbles: true, cancelable: true });
              if (ev.keyCode !== kc) {
                Object.defineProperty(ev, 'keyCode', { get: function() { return kc; } });
                Object.defineProperty(ev, 'which', { get: function() { return kc; } });
              }
              ev.__gh = true;
              target.dispatchEvent(ev);
            });
          }
          // Ô number/email không có selection (setRangeText ném lỗi) → sửa ở cuối chuỗi.
          function put(text, back) {
            var v = field.value, s = field.selectionStart, e = field.selectionEnd;
            if (s === null) { field.value = back ? v.slice(0, -1) : v + text; return; }
            if (back && s === e && s > 0) s--;
            field.setRangeText(text, s, e, 'end');
          }
          function input(type, data) {
            el.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: type, data: data }));
          }
          if (t === '\\b') {
            if (field) { put('', true); input('deleteContentBackward', null); } else if (rich) document.execCommand('delete');
            else key('Backspace', 'Backspace', 8);
            return;
          }
          if (t === '\\n') { key('Enter', 'Enter', 13); return; }
          if (field) { put(t, false); input('insertText', t); return; }
          if (rich) { document.execCommand('insertText', false, t); return; }
          for (var ch of t) {
            var up = ch.toUpperCase();
            var code = /[A-Z]/.test(up) ? 'Key' + up : /[0-9]/.test(ch) ? 'Digit' + ch : ch === ' ' ? 'Space' : '';
            key(ch, code, code ? up.charCodeAt(0) : ch.charCodeAt(0));
          }
        })(\(Self.jsString(text)));
        """
        webView.evaluateJavaScript(js) { _, error in
            if let error { AppLog.warn("Gõ phím không gửi được: \(error.localizedDescription)") }
        }
    }

    /// Kiểm tra "sức khoẻ" của game trong trang: còn JS sống không, có canvas
    /// không, có focus không.
    ///
    /// Dùng để phân biệt cho người dùng:
    /// - Game OK → nút ảo bấm được, viền xanh.
    /// - Game chết/trắng → nút bấm không ăn, viền đỏ + cảnh báo.
    static func checkHealth(_ webView: WKWebView,
                            completion: @escaping (Bool, String) -> Void) {
        let js = """
        (function() {
            var canvas = document.querySelector('canvas');
            var body = document.body;
            return {
                alive: true,
                focused: (typeof document.hasFocus === 'function') ? document.hasFocus() : true,
                hasCanvas: !!canvas,
                canvasSize: canvas ? (canvas.width + 'x' + canvas.height) : 'none',
                title: document.title || '',
                readyState: document.readyState,
                keys: window.__ghKeys ? window.__ghKeys.count : -1,
                lastKey: window.__ghKeys ? window.__ghKeys.last : '',
                lastKeyAgo: window.__ghKeys && window.__ghKeys.at ? Math.round((Date.now() - window.__ghKeys.at) / 1000) : -1
            };
        })();
        """
        webView.evaluateJavaScript(js) { result, error in
            if let error {
                completion(false, "Không đọc được trang game: \(error.localizedDescription)")
                return
            }
            guard let d = result as? [String: Any] else {
                completion(false, "Trang game không phản hồi")
                return
            }
            let alive = (d["alive"] as? Bool) ?? false
            let focused = (d["focused"] as? Bool) ?? true
            let hasCanvas = (d["hasCanvas"] as? Bool) ?? false
            let canvasSize = d["canvasSize"] as? String ?? "?"
            let title = d["title"] as? String ?? ""
            let readyState = d["readyState"] as? String ?? "?"

            let keys = (d["keys"] as? NSNumber)?.intValue ?? -1
            let lastKey = d["lastKey"] as? String ?? ""
            let lastKeyAgo = (d["lastKeyAgo"] as? NSNumber)?.intValue ?? -1

            var notes: [String] = []
            switch keys {
            case ..<0: notes.append("phím ảo: chưa đo được (mở lại game)")
            case 0: notes.append("phím ảo: chưa bấm lần nào")
            default: notes.append("phím ảo đã tới game \(keys) lần (gần nhất \(lastKey), \(lastKeyAgo)s trước)")
            }
            notes.append("canvas: \(hasCanvas ? canvasSize : "không có")")
            notes.append("ready: \(readyState)")
            // Chỉ để tham khảo: mở menu của app luôn làm trang mất focus.
            notes.append("focus: \(focused ? "có" : "không")")
            if !title.isEmpty { notes.append("title: \(title)") }

            if !alive {
                completion(false, "Game không phản hồi — \(notes.joined(separator: " · "))")
            } else {
                completion(true, notes.joined(separator: " · "))
            }
        }
    }

    /// Bắn sự kiện **chuột** (mousedown/mouseup/click) vào trang.
    static func fireMouse(_ webView: WKWebView,
                          button: Int,
                          down: Bool,
                          completion: ((Bool, String?) -> Void)? = nil) {
        let type = down ? "mousedown" : "mouseup"
        let js = """
        (function() {
            var target = document.activeElement;
            if (!target || target === document.body) {
                var canvas = document.querySelector('canvas');
                target = canvas || document.body;
            }
            var rect = target.getBoundingClientRect
                ? target.getBoundingClientRect()
                : {left: 0, top: 0, width: 1, height: 1};
            var cx = rect.left + rect.width / 2;
            var cy = rect.top + rect.height / 2;
            var ev = new MouseEvent(\(Self.jsString(type)), {
                button: \(button),
                buttons: \(down ? 1 : 0),
                clientX: cx, clientY: cy,
                bubbles: true, cancelable: true, view: window
            });
            target.dispatchEvent(ev);  // bubbles → document nhận 1 lần
            if (\(down ? "false" : "true")) {  // nhả nút → thêm click
                var click = new MouseEvent('click', {
                    button: \(button), bubbles: true, cancelable: true,
                    view: window, clientX: cx, clientY: cy
                });
                target.dispatchEvent(click);
            }
            return true;
        })();
        """
        webView.evaluateJavaScript(js) { _, error in
            if let error {
                completion?(false, error.localizedDescription)
            } else {
                completion?(true, nil)
            }
        }
    }

    /// Escape chuỗi JS an toàn.
    private static func jsString(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }

    /// Bảng `keyCode` cũ (một số game cũ đọc `keyCode`/`which`).
    private static func keyCodeValue(_ vk: VirtualKey) -> Int {
        switch vk.code {
        case "ArrowUp": return 38
        case "ArrowDown": return 40
        case "ArrowLeft": return 37
        case "ArrowRight": return 39
        case "Enter": return 13
        case "Space": return 32
        case "Escape": return 27
        case "Tab": return 9
        case "Backspace": return 8
        case "ShiftLeft", "ShiftRight": return 16
        case "ControlLeft", "ControlRight": return 17
        default:
            if vk.code.hasPrefix("Key"), let f = vk.code.last {
                return Int(f.asciiValue ?? 0)  // A-Z
            }
            if vk.code.hasPrefix("Digit"), let d = vk.code.last, d.isNumber {
                return Int(String(d))!
            }
            return 0
        }
    }
}
