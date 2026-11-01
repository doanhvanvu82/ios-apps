import SwiftUI
import WebKit

struct ContentView: View {
    @ObservedObject private var library = GameLibrary.shared
    @State private var playingGame: GameInfo?
    @State private var infoGame: GameInfo?
    /// Bấm "Chơi" trong sheet thông tin → chờ sheet đóng hẳn rồi mới mở game
    /// (iOS không cho present fullScreenCover khi sheet đang dismiss).
    @State private var playAfterInfo: GameInfo?
    @State private var showingFolderPicker = false
    @State private var showingSettings = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            LibraryView(
                library: library,
                onPlay: { playingGame = $0 },
                onShowInfo: { infoGame = $0 },
                onPickFolder: { showingFolderPicker = true },
                onOpenSettings: { showingSettings = true }
            )
        }
        .tint(Theme.accent)
        .fullScreenCover(item: $playingGame) { game in
            GamePlayView(game: game, library: library)
        }
        .sheet(item: $infoGame, onDismiss: {
            if let game = playAfterInfo {
                playAfterInfo = nil
                playingGame = game
            }
        }) { game in
            GameInfoSheet(game: game) { playAfterInfo = game }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .fileImporter(
            isPresented: $showingFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            library.handleFolderPick(result)
        }
        .onAppear {
            // KHÔNG tự quét khi vào app — danh sách lần trước vẫn hiển thị,
            // người dùng kéo xuống / menu thư mục khi muốn quét lại.
            library.importPendingItems()

            // App mở lại sau khi bị kill lúc đang chơi game → ép về dọc.
            // (`scenePhase` có thể đã là .active ngay từ đầu nên onChange
            //  không chạy → cần làm thêm ở đây.)
            //
            // ⚠️ Chỉ làm khi KHÔNG đang chơi game — ContentView.onAppear có
            // thể chạy lại sau khi dismiss fullScreenCover, lúc đó không
            // được ép dọc (đang thoát game, GamePlayView tự xử lý).
            if playingGame == nil {
                OrientationManager.shared.forcePortrait(reason: "app mở / màn danh sách")
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                // Chỉ xử lý file zip trong Imports — không quét lại thư viện.
                library.importPendingItems()

                // ⚠️ Fix "thoát app rồi vào lại → app kẹt màn hình dọc":
                // Khi app bị kill/swipe khỏi đa nhiệm, `onDisappear` của
                // GamePlayView KHÔNG chạy → `OrientationLock.mask` vẫn là
                // landscape-only, nhưng scene được tạo lại ở hướng dọc và
                // bị kẹt (iOS không tự xoay vì hướng hiện tại đã "được phép").
                //
                // Ở màn danh sách (không đang chơi game) ta ép mask = portrait
                // và xin geometry update về dọc → app luôn về dọc khi mở.
                if playingGame == nil {
                    OrientationManager.shared.forcePortrait(reason: "app vào foreground")
                }
            }
        }
    }
}

// MARK: - Màn chơi game

struct GamePlayView: View {
    let game: GameInfo
    let library: GameLibrary
    @Environment(\.dismiss) private var dismiss
    /// Theo dõi app vào/ra foreground — cần để ép lại hướng màn hình khi
    /// user quay lại app (iOS hay bỏ qua geometry update lúc app bị ẩn).
    @Environment(\.scenePhase) private var scenePhase

    @State private var loadedURL: URL?
    @State private var loadError: String?
    @State private var server: LocalWebServer?
    /// Holder class cho WebView — xem `WebViewHolder` để biết vì sao không dùng
    /// `@State var webView: WKWebView?` (bị SwiftUI bỏ qua khi gán trong
    /// `makeUIView` → nút ảo báo "WebView chưa sẵn sàng").
    @StateObject private var webViewHolder = WebViewHolder()

    // --- Màn điều khiển ảo ---
    @State private var gamepadVisible = false
    /// Chuột ảo (touchpad), bật/tắt độc lập với điều khiển ảo.
    @State private var cursorMode = false
    @State private var keyboardVisible = false
    /// Game hợp chơi dọc (người dùng chọn trong menu), lưu theo từng game.
    @State private var portraitMode = false
    @State private var showGamepadSettings = false
    @State private var gamepadLayout: ControlLayout?
    @State private var showingDebugLog = false
    @State private var showingCheat = false
    @StateObject private var cheat = CheatModel()

    /// Header + nút chức năng: hiện lúc mở game rồi TỰ ẨN để không che game.
    /// Màn khởi động (ảnh bìa + tên game) che WebView tới khi trang load xong.
    @State private var showLaunchOverlay = true
    @StateObject private var loadProgress = LoadProgress()
    @State private var loadingPillDismissed = false
    @State private var confirmingExit = false
    @State private var isExiting = false
    /// Kích thước màn hình hiện tại — đổi khi xoay. Dùng để ép SwiftUI
    /// tính lại `uiSafeArea` (safe-area của UIKit đổi theo hướng xoay).
    @State private var viewportSize: CGSize = .zero
    /// Observe settings để đổi tuỳ chọn (rung, tự ẩn header) có hiệu lực
    /// ngay mà không cần thoát game.
    @ObservedObject private var settings = AppSettings.shared
    @State private var showingSettings = false

    var body: some View {
        // GeometryReader phủ TRỌN màn hình (kể cả vùng notch) — mọi overlay
        // sau đó được canh bằng `uiSafeArea` nên không bị lọt vào vùng che.
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                if let url = loadedURL {
                    GameWebView(url: url, engine: game.engine, onWebViewReady: { wv in
                        webViewHolder.attach(wv)
                        loadProgress.attach(wv)
                    }, onPageLoaded: hideLaunchOverlaySoon)
                    .ignoresSafeArea()
                    // ⚠️ `withAnimation` (dùng khi ẩn/hiện header) có thể làm
                    // SwiftUI **tạo lại** UIViewRepresentable → WebView load
                    // lại từ đầu → game mất tiến trình (log thấy "Trang load
                    // xong" 2 lần). Tắt animation cho riêng cây WebView.
                    .transaction { $0.animation = nil }

                    if cursorMode {
                        VirtualMouseView(webView: { webViewHolder.webView })
                            .ignoresSafeArea()
                            .transition(.opacity)
                    }

                    // Overlay màn điều khiển ảo (đè lên game, mờ).
                    if gamepadVisible {
                        VirtualGamepadView(
                            gameName: game.folderName,
                            engine: game.engine,
                            safeArea: uiSafeArea,
                            fireKey: { vk, down in
                                if let wv = webViewHolder.webView {
                                    GameWebView.fireKey(wv, vk: vk, down: down)
                                }
                            },
                            onFireKey: { vk, down, completion in
                                guard let wv = webViewHolder.webView else {
                                    completion(false, "WebView chưa sẵn sàng")
                                    return
                                }
                                // Nút chuột ảo → bắn MouseEvent, nút phím → KeyboardEvent.
                                if let mb = vk.mouseButton {
                                    GameWebView.fireMouse(wv, button: mb, down: down,
                                                         completion: completion)
                                } else {
                                    GameWebView.fireKey(wv, vk: vk, down: down,
                                                        completion: completion)
                                }
                            },
                            onEdit: { showGamepadSettings = true }
                        )
                        .ignoresSafeArea()
                        .allowsHitTesting(true)
                        .transition(.opacity)
                    }
                }

                if let error = loadError {
                    errorView(error)
                        .transition(.opacity)
                } else if showLaunchOverlay {
                    GameLaunchOverlay(game: game, progress: loadProgress)
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            // ---- Nút ở mép màn hình ----
            // Ngang: nằm giữa dải viền tai thỏ hai bên (game không vẽ vào đó)
            // nên luôn hiện mà không che game. Không dùng NavigationStack +
            // toolbar: toolbar chiếm một dải trên cùng của game.
            .overlay(alignment: .topLeading) {
                VStack(spacing: 10) {
                    EdgeButton(systemImage: "chevron.backward") { requestExit() }
                        .accessibilityLabel("Thoát game")
                    if loadedURL != nil && loadError == nil {
                        EdgeButton(systemImage: cursorMode ? "cursorarrow.rays" : "cursorarrow",
                                   highlighted: cursorMode) {
                            withAnimation(Theme.spring) { cursorMode.toggle() }
                        }
                        .accessibilityLabel(cursorMode ? "Tắt chuột ảo" : "Bật chuột ảo")
                        .transition(.scale.combined(with: .opacity))
                        EdgeButton(systemImage: "wand.and.stars", highlighted: showingCheat) {
                            withAnimation(Theme.spring) { showingCheat.toggle() }
                        }
                        .accessibilityLabel(showingCheat ? "Đóng bảng chỉnh thông số" : "Chỉnh thông số game")
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.leading, edgeInsets.side)
                .padding(.top, edgeInsets.top)
            }
            .overlay(alignment: .topTrailing) {
                VStack(spacing: 10) {
                    menuButton
                    if loadedURL != nil && loadError == nil {
                        EdgeButton(systemImage: gamepadVisible ? "gamecontroller.fill" : "gamecontroller",
                                   highlighted: gamepadVisible) {
                            withAnimation(Theme.spring) { gamepadVisible.toggle() }
                        }
                        .accessibilityLabel(gamepadVisible ? "Ẩn điều khiển" : "Hiện điều khiển")
                        .transition(.scale.combined(with: .opacity))
                        EdgeButton(systemImage: keyboardVisible ? "keyboard.fill" : "keyboard",
                                   highlighted: keyboardVisible) {
                            keyboardVisible.toggle()
                        }
                        .accessibilityLabel(keyboardVisible ? "Ẩn bàn phím" : "Hiện bàn phím")
                        .transition(.scale.combined(with: .opacity))
                        .background {
                            GameKeyboardField(isActive: $keyboardVisible) { webViewHolder.webView }
                                .frame(width: 1, height: 1)
                                .allowsHitTesting(false)
                        }
                    }
                }
                .padding(.trailing, edgeInsets.side)
                .padding(.top, edgeInsets.top)
            }
            // Trang đã mở nhưng engine còn nạp dữ liệu → thanh tải nhỏ dưới đáy,
            // để màn đen lúc đầu không bị tưởng là lỗi.
            .overlay(alignment: .bottom) {
                if loadedURL != nil, loadError == nil, !showLaunchOverlay,
                   !loadProgress.finished, !loadingPillDismissed {
                    GameLoadingPill(
                        progress: loadProgress,
                        accent: game.engine.accent,
                        onOpenLog: { showingDebugLog = true },
                        onDismiss: { withAnimation(Theme.spring) { loadingPillDismissed = true } }
                    )
                    .padding(.horizontal, uiSafeArea.leading + 12)
                    .padding(.bottom, max(uiSafeArea.bottom, 8) + 6)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            // Bảng chỉnh thông số: nằm trong vùng game, chừa dải nút viền phải.
            .overlay(alignment: .trailing) {
                if showingCheat, loadedURL != nil, loadError == nil {
                    CheatPanel(model: cheat) { withAnimation(Theme.spring) { showingCheat = false } }
                        .padding(.trailing, max(uiSafeArea.trailing, 8))
                        .padding(.vertical, max(uiSafeArea.bottom, 8))
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(Theme.spring, value: loadProgress.finished)
            .confirmationDialog("Thoát \"\(game.displayTitle)\"?", isPresented: $confirmingExit, titleVisibility: .visible) {
                Button("Thoát game", role: .destructive) { exitGame() }
                Button("Chơi tiếp", role: .cancel) {}
            } message: {
                Text("Tiến trình chưa lưu trong game sẽ mất.")
            }
            .sheet(isPresented: $showingDebugLog) {
                DebugLogView(game: (game.folderName, game.displayTitle))
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showGamepadSettings) {
                GamepadSettingsView(
                    gameName: game.folderName,
                    engine: game.engine,
                    layout: Binding(
                        get: { gamepadLayout ?? ControlPresets.forEngine(game.engine) },
                        set: { gamepadLayout = $0 }
                    )
                )
                .onDisappear { gamepadLayout = nil }
            }
            // Màn xoay → kích thước đổi → safe-area (notch/home-indicator) đổi
            // theo → ép tính lại layout + giữ header ẩn để không che game.
            .onChange(of: geo.size) { oldSize, newSize in
                guard oldSize != newSize else { return }
                viewportSize = newSize
                let sa = uiSafeArea
                AppLog.info("Layout[\(Int(newSize.width))x\(Int(newSize.height))] safeArea T\(Int(sa.top)) L\(Int(sa.leading)) R\(Int(sa.trailing)) B\(Int(sa.bottom))")
                // Engine có thể giữ kích thước đo lúc trang tải (còn dọc) → báo
                // resize sau khi xoay xong để game tính lại khung hình.
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    _ = try? await webViewHolder.webView?.evaluateJavaScript("window.dispatchEvent(new Event('resize'))")
                }
            }
            .onAppear { viewportSize = geo.size }
        }
        .task {
            cheat.webView = { [webViewHolder] in webViewHolder.webView }
            startServer()
            // Phòng khi `didFinish` không bao giờ tới (trang treo) — không để
            // màn khởi động che game mãi.
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            if showLaunchOverlay { hideLaunchOverlaySoon() }
        }
            // App quay lại foreground (từ Home, app khác, hoặc vừa mở lại
            // sau khi bị kill) → ép lại hướng ngang. iOS thường bỏ qua
            // geometry update lúc app bị ẩn nên phải xin lại.
            .onChange(of: scenePhase) { _, phase in
                if phase == .active, loadedURL != nil {
                    AppLog.info("App vào foreground → xin xoay lại")
                    applyOrientation()
                }
            }
            .onDisappear {
                // Thoát game → về dọc. Dùng setLandscape(false) (nhiều lần thử)
                // vì lúc này fullScreenCover đang dismiss, iOS hay bỏ qua
                // requestGeometryUpdate nếu gọi 1 lần.
                setLandscape(false)
                loadProgress.stop()
                server?.stop()
                server = nil
                loadedURL = nil
                webViewHolder.detach()
                library.markPlayed(game)
                AppLog.shared.endGame()
            }
        // GeometryReader phủ trọn màn hình → ZStack bên trong cũng trọn màn,
        // game không bị chừa dải trên/dưới. Mọi overlay tự canh theo
        // `uiSafeArea` (vùng không bị notch/home-indicator che).
        .ignoresSafeArea()
    }

    // MARK: - Khởi động / thoát

    /// Trang load xong → đợi engine vẽ khung đầu rồi fade màn khởi động.
    private func hideLaunchOverlaySoon() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard showLaunchOverlay else { return }
            withAnimation(.easeOut(duration: 0.45)) { showLaunchOverlay = false }
        }
    }

    /// Đang khởi động/lỗi thì thoát ngay; đang chơi thì hỏi lại trước.
    private func requestExit() {
        if showLaunchOverlay || loadError != nil {
            dismiss()
        } else {
            confirmingExit = true
        }
    }

    /// Chụp màn hình game làm ảnh bìa rồi mới đóng (WebView còn sống).
    private func exitGame() {
        guard !isExiting else { return }
        isExiting = true
        guard let wv = webViewHolder.webView else {
            dismiss()
            return
        }
        wv.takeSnapshot(with: nil) { image, error in
            Task { @MainActor in
                if let image {
                    CoverStore.shared.saveSnapshot(image, for: game)
                } else if let error {
                    AppLog.warn("Không chụp được màn hình game: \(error.localizedDescription)")
                }
                dismiss()
            }
        }
    }

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.yellow)
                .symbolEffect(.bounce, value: error)
            Text("Không tải được game")
                .font(.title3.weight(.bold))
            Text(error)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            HStack(spacing: 12) {
                Button { showingDebugLog = true } label: {
                    Label("Xem log", systemImage: "terminal")
                }
                .buttonStyle(.bordered)
                Button("Quay lại") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
            }
            .padding(.top, 4)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }

    // MARK: - Thanh công cụ nổi (header)

    /// Safe-area hiện tại của màn hình (theo UIKit).
    ///
    /// Dùng UIKit thay vì `GeometryReader.safeAreaInsets` vì view gốc có
    /// `.ignoresSafeArea()` → insets từ GeometryReader luôn bằng 0.
    /// Ở chiều ngang, iPhone có Dynamic Island/notch → safeArea.left/right
    /// ≈ 47–59pt; đây chính là vùng mà nút cũ bị lọt vào và bị che.
    private var uiSafeArea: EdgeInsets {
        // `viewportSize` được đọc để body re-evaluate khi màn xoay (safe-area
        // của UIKit đổi theo hướng, nhưng SwiftUI không tự biết).
        _ = viewportSize
        let insets = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .keyWindow?.safeAreaInsets
            ?? .zero
        return EdgeInsets(top: insets.top, leading: insets.left,
                          bottom: insets.bottom, trailing: insets.right)
    }

    /// Khoảng cách nút tới mép màn hình.
    ///
    /// Ngang: căn giữa dải safe-area hai bên (≈59pt, phần viền tai thỏ mà game
    /// không vẽ tới); `top` 12pt để nút không bị góc bo của màn hình cắt.
    /// Dọc: nằm dưới Dynamic Island.
    private var edgeInsets: (side: CGFloat, top: CGFloat) {
        let sa = uiSafeArea
        let landscape = viewportSize.width > viewportSize.height
        if landscape {
            let band = max(sa.leading, sa.trailing)
            return (max(6, (band - EdgeButton.size) / 2), 12)
        }
        return (10, sa.top + 6)
    }

    private var menuButton: some View {
        Menu {
            Button {
                showingDebugLog = true
            } label: {
                Label("Xem log", systemImage: "terminal")
            }
            Button {
                showGamepadSettings = true
            } label: {
                Label("Tuỳ chỉnh nút & phím", systemImage: "slider.horizontal.3")
            }
            Button {
                runHealthCheck()
            } label: {
                Label("Kiểm tra game (nút có ấn được?)", systemImage: "stethoscope")
            }
            Button {
                portraitMode.toggle()
                UserDefaults.standard.set(portraitMode, forKey: portraitKey)
                applyOrientation()
            } label: {
                Label(portraitMode ? "Chơi màn hình ngang" : "Chơi màn hình dọc",
                      systemImage: portraitMode ? "rectangle.landscape.rotate" : "rectangle.portrait.rotate")
            }
            Button {
                showingSettings = true
            } label: {
                Label("Cài đặt", systemImage: "gearshape")
            }
            Divider()
            Button(role: .destructive) {
                requestExit()
            } label: {
                Label("Thoát game", systemImage: "xmark.circle")
            }
        } label: {
            EdgeButtonLabel(systemImage: "ellipsis")
        }
        .accessibilityLabel("Menu chức năng")
    }

    /// Kiểm tra sức khoẻ game: cho user biết chính xác nút ảo có ấn được
    /// hay không, và nếu không thì lý do (game chết / mất focus / lỗi JS).
    private func runHealthCheck() {
        guard let wv = webViewHolder.webView else {
            AppLog.warn("Chưa có WebView để kiểm tra")
            return
        }
        AppLog.info("Đang kiểm tra game…")
        GameWebView.checkHealth(wv) { ok, detail in
            DispatchQueue.main.async {
                if ok {
                    AppLog.ok("Game OK — \(detail)")
                    AppSettings.notifySuccess()
                } else {
                    AppLog.error("Game có vấn đề — \(detail)")
                    AppSettings.notifyError()
                }
                showingDebugLog = true
            }
        }
    }

    /// Yêu cầu iOS xoay màn hình — đã chuyển toàn bộ logic sang
    /// `OrientationManager` (xem file đó để đọc các bài học đã gặp thật).
    private func setLandscape(_ on: Bool) {
        if on {
            OrientationManager.shared.forceLandscape(reason: "vào game \(game.folderName)")
        } else {
            OrientationManager.shared.forcePortrait(reason: "thoát game \(game.folderName)")
        }
    }

    private var portraitKey: String { "portraitMode.\(game.folderName)" }

    private func applyOrientation() {
        if portraitMode {
            OrientationManager.shared.forcePortrait(reason: "game \(game.folderName) chơi dọc")
        } else {
            setLandscape(true)
        }
    }

    private func startServer() {
        AppLog.shared.beginGame(game.folderName)
        AppLog.info("Bắt đầu mở game: \(game.folderName) [\(game.engine.rawValue)]")
        portraitMode = UserDefaults.standard.bool(forKey: portraitKey)
        applyOrientation()
        guard game.isPlayable else {
            AppLog.warn("Engine không chơi được: \(game.engine.rawValue)")
            loadError = "Engine '\(game.engine.displayName)' chưa được hỗ trợ trên iOS."
            return
        }

        // Nhận diện lại lúc mở: cache thư viện có thể còn entryPath của cách nhận
        // diện cũ (vd game Flash từng lấy nhầm `data/` làm gốc).
        var game = self.game
        let detected = EngineDetector.detect(in: library.gameDirectory(for: game))
        if detected.engine == game.engine,
           detected.entryPath != game.entryPath || detected.isAsar != game.isAsar {
            AppLog.info("Thư mục gốc game đổi: \(game.entryPath ?? "-") → \(detected.entryPath ?? "-")")
            game = GameInfo(folderName: game.folderName, engine: game.engine, entryPath: detected.entryPath,
                            isAsar: detected.isAsar, lastPlayed: game.lastPlayed, playCount: game.playCount)
        }

        var root: GameResourceRoot
        do {
            root = try library.resourceRoot(for: game)
        } catch {
            AppLog.error("resourceRoot lỗi: \(error)")
            loadError = "Không mở được tài nguyên game: \(error.localizedDescription)"
            return
        }

        // --- Game gốc Windows: gắn runtime đi kèm app vào ---
        // Nhờ vậy Godot (.pck) / Flash (.swf) / KiriKiri (.xp3) chạy được
        // mà KHÔNG cần build lại game trên máy tính.
        switch game.engine {
        case .godotNative, .kirikiNative, .flashNative:
            let gameDir = library.gameDirectory(for: game)
            // Với game có entryPath (thư mục con), runtime dùng đúng thư mục đó.
            let effectiveDir = (game.entryPath != nil && game.entryPath != ".")
                ? gameDir.appendingPathComponent(game.entryPath!, isDirectory: true)
                : gameDir
            configureRuntime(root: root, gameDir: effectiveDir, engine: game.engine)
        case .tyranoBuilder:
            TyranoPatch.applyWebStorageSave(to: root)
        case .rpgMakerMV:
            root.runtimeDirectory = ElectronShim.compatDirectory
        case .renpyNative:
            do {
                try RenPyNative.configure(root: root, gameDir: library.gameDirectory(for: game),
                                          title: game.displayTitle)
            } catch {
                AppLog.error("Ren'Py: \(error.localizedDescription)")
                loadError = error.localizedDescription
                return
            }
        default:
            break
        }

        // Kiểm tra entry có tồn tại không (đối với game thư mục thường).
        // Với game .asar, index.html nằm ở gốc archive.
        if !game.isAsar, root.customIndexHTML == nil, root.source(for: "index.html") == nil {
            AppLog.error("Không có index.html — entry: \(game.entryPath ?? "-"), engine: \(game.engine.rawValue)")
            loadError = "Không tìm thấy index.html trong game (entry: \(game.entryPath ?? "-"))."
            return
        }

        let webServer = LocalWebServer(root: root)
        do {
            try webServer.start(preferredPort: LocalWebServer.stablePort(for: game.folderName))
            server = webServer
            loadProgress.start(server: webServer)
            AppLog.ok("Server port \(webServer.port) — engine \(game.engine.rawValue)")
            var url = URL(string: "http://127.0.0.1:\(webServer.port)/index.html")!

            // Runtime KiriKiri (kirikiroid2-web) tự nạp game qua tham số URL.
            // - .kirikiWeb: game đã đóng gói sẵn thành game.zip
            // - .kirikiNative: quét thư mục game gốc qua WebDAV PROPFIND
            if game.engine == .kirikiWeb {
                url = URL(string: "http://127.0.0.1:\(webServer.port)/index.html?game=/game.zip&loadMode=eager")!
            } else if game.engine == .kirikiNative {
                // loadMode=lazy: đọc .xp3 theo HTTP Range khi cần. eager tải/ghi
                // cả game vào bộ nhớ trình duyệt trước → game vài GB (Hold Me
                // Tight: patch.xp3 4.4 GB) làm WebKit hết RAM.
                // renderer=software: tránh WebGL của WebKit iOS (Godot đã mất WebGL
                // context vì nó). entry: khởi động thẳng data.xp3, bỏ màn chọn
                // archive (chọn nhầm archive khác là game không chạy).
                var query = "webdavUrl=/&loadMode=lazy&renderer=software"
                if root.source(for: "data.xp3") != nil { query += "&entry=data.xp3" }
                url = URL(string: "http://127.0.0.1:\(webServer.port)/index.html?\(query)")!
            }

            loadedURL = url
        } catch {
            AppLog.error("Server không chạy được: \(error)")
            loadError = "Lỗi server: \(error.localizedDescription)"
        }
    }

    /// Godot export "Embed PCK": pck nằm cuối `.exe` → phục vụ đoạn đó dưới
    /// tên `game.pck`, không chép ra đĩa (có game pck > 1 GB).
    private func configureEmbeddedGodot(root: GameResourceRoot, gameDir: URL, items: [String]) {
        guard let exe = items.first(where: {
            $0.lowercased().hasSuffix(".exe") && GodotPack.embeddedPack(in: gameDir.appendingPathComponent($0)) != nil
        }) else { return }
        let exeURL = gameDir.appendingPathComponent(exe)
        guard let pack = GodotPack.embeddedPack(in: exeURL) else { return }
        let version = GodotPack.version(of: exeURL, offset: pack.offset)
        let runtime = GodotPack.runtime(for: version)
        let packName = "game.pck"
        root.virtualSources[packName] = FileSliceSource(fileURL: exeURL, offset: pack.offset,
                                                        size: pack.size, relativePath: packName)
        root.runtimeDirectory = EngineRuntime.directory(for: runtime)
        root.customIndexHTML = EngineRuntime.indexHTML(for: runtime, packSize: Int64(pack.size),
                                                       packName: packName, title: game.folderName)
        AppLog.info("Godot \(version.map { "\($0.major).\($0.minor).\($0.patch)" } ?? "?") — pck nhúng trong \(exe) (\(pack.size / 1_048_576) MB)")
    }

    /// Gắn runtime engine đi kèm app vào gốc tài nguyên của game gốc.
    private func configureRuntime(root: GameResourceRoot,
                                  gameDir: URL,
                                  engine: EngineKind) {
        let fm = FileManager.default
        let items = (try? fm.contentsOfDirectory(atPath: gameDir.path)) ?? []

        switch engine {
        case .godotNative:
            // Chọn file .pck CHÍNH: ưu tiên pck trùng tên .exe (vd Game.pck cho
            // Game.exe); nếu không có thì pck lớn nhất. Các pck phụ (DLC, patch)
            // sẽ được nạp bởi chính game.
            let candidates = items.filter { $0.hasSuffix(".pck") }
            guard !candidates.isEmpty else {
                configureEmbeddedGodot(root: root, gameDir: gameDir, items: items)
                return
            }
            let exeNames = Set(items.filter { $0.hasSuffix(".exe") }.map {
                ($0 as NSString).deletingPathExtension
            })
            let mainPck = candidates.first { exeNames.contains(($0 as NSString).deletingPathExtension) }
                ?? candidates.max { p1, p2 in
                    let s1 = (try? fm.attributesOfItem(atPath: gameDir.appendingPathComponent(p1).path)[.size] as? NSNumber)?.int64Value ?? 0
                    let s2 = (try? fm.attributesOfItem(atPath: gameDir.appendingPathComponent(p2).path)[.size] as? NSNumber)?.int64Value ?? 0
                    return s1 < s2
                }!
            let packURL = gameDir.appendingPathComponent(mainPck)
            let size = (try? fm.attributesOfItem(atPath: packURL.path)[.size] as? NSNumber)?.int64Value ?? 0
            let version = GodotPack.version(of: packURL)
            let actualRuntime = GodotPack.runtime(for: version)
            root.runtimeDirectory = EngineRuntime.directory(for: actualRuntime)
            root.customIndexHTML = EngineRuntime.indexHTML(
                for: actualRuntime,
                packSize: size,
                packName: mainPck,
                title: game.folderName
            )

        case .flashNative:
            let swf: String
            if let projector = FlashProjector.entry(in: gameDir, items: items) {
                swf = "game_entry.swf"
                root.virtualSources[swf] = FileSliceSource(fileURL: gameDir.appendingPathComponent(projector.exe),
                                                           offset: projector.offset, size: projector.size,
                                                           relativePath: swf)
                AppLog.info("Flash — SWF chính nhúng trong \(projector.exe) (\(projector.size / 1024) KB)")
            } else if let first = items.first(where: { $0.hasSuffix(".swf") }) {
                swf = first
                AppLog.info("Flash — không có projector .exe trong \(gameDir.lastPathComponent)/, chạy \(first)")
            } else {
                return
            }
            root.runtimeDirectory = EngineRuntime.directory(for: .ruffle)
            root.customIndexHTML = EngineRuntime.indexHTML(
                for: .ruffle,
                packSize: 0,
                title: game.folderName,
                swfName: swf
            )

        case .kirikiNative:
            // Runtime KiriKiri quét thư mục game qua WebDAV PROPFIND và đọc
            // file .xp3 lazy qua HTTP Range → KHÔNG cần nén game.zip.
            root.runtimeDirectory = EngineRuntime.directory(for: .kiriki)
            root.customIndexHTML = EngineRuntime.indexHTML(for: .kiriki, packSize: 0, title: game.folderName)
            root.virtualFiles = KiriKiriPatch.virtualFiles(gameDir: gameDir, runtimeDir: root.runtimeDirectory)

        default:
            break
        }
    }
}

// MARK: - Màn khởi động game

/// Ảnh bìa làm nền mờ + tên game + thanh chạy, che WebView tới khi trang
/// load xong (tránh màn đen/trắng lúc engine đang nạp).
private struct GameLaunchOverlay: View {
    let game: GameInfo
    @ObservedObject var progress: LoadProgress
    @State private var appeared = false
    @State private var sweep = false

    var body: some View {
        ZStack {
            GameCoverView(game: game, maxPixel: 600)
                .scaleEffect(1.25)
                .blur(radius: 36)
                .opacity(0.6)
                .ignoresSafeArea()
            Color.black.opacity(0.45).ignoresSafeArea()

            VStack(spacing: 18) {
                GameCoverView(game: game, maxPixel: 600)
                    .frame(width: 200, height: 130)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.15)))
                    .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
                    .scaleEffect(appeared ? 1 : 0.85)

                VStack(spacing: 8) {
                    Text(game.displayTitle)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    EngineChip(engine: game.engine)
                }

                Capsule()
                    .fill(.white.opacity(0.15))
                    .frame(width: 170, height: 4)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(game.engine.accent)
                            .frame(width: 60)
                            .offset(x: sweep ? 110 : 0)
                    }
                    .clipShape(Capsule())
                    .padding(.top, 6)

                VStack(spacing: 3) {
                    Text("Đang khởi động…")
                    LoadStatsText(progress: progress)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.45))
                }
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.horizontal, 40)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(Theme.spring) { appeared = true }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { sweep = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Đang khởi động \(game.displayTitle)")
    }
}

// MARK: - Nút ở mép màn chơi

/// Nút tròn kính mờ đặt ở mép màn hình chơi game.
private struct EdgeButton: View {
    static let size: CGFloat = 36
    let systemImage: String
    var highlighted = false
    let action: () -> Void

    var body: some View {
        Button(action: action) { EdgeButtonLabel(systemImage: systemImage, highlighted: highlighted) }
            .buttonStyle(PressableButtonStyle(scale: 0.88))
    }
}

private struct EdgeButtonLabel: View {
    let systemImage: String
    /// Đang bật (điều khiển / chuột ảo) → nền sáng để biết chế độ hiện tại.
    var highlighted = false

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 15, weight: .semibold))
            .contentTransition(.symbolEffect(.replace))
            .foregroundStyle(highlighted ? Color.black : .white.opacity(0.9))
            .frame(width: EdgeButton.size, height: EdgeButton.size)
            .background(Circle().fill(.white.opacity(highlighted ? 0.85 : 0)))
            .background(.ultraThinMaterial, in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.15), lineWidth: 1))
            .environment(\.colorScheme, .dark)
            .contentShape(Circle())
    }
}
