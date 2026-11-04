import SwiftUI

extension GameInfo {
    /// Tên hiển thị: thay `_` bằng dấu cách (tên thư mục game hay dùng `_`).
    var displayTitle: String {
        folderName.replacingOccurrences(of: "_", with: " ")
    }
}

/// Màn thư viện: tìm kiếm, lọc, "Chơi tiếp", lưới ảnh bìa.
struct LibraryView: View {
    @ObservedObject var library: GameLibrary
    let onPlay: (GameInfo) -> Void
    let onShowInfo: (GameInfo) -> Void
    let onPickFolder: () -> Void
    let onOpenSettings: () -> Void

    @State private var query = ""
    @State private var filter: Filter = .all
    @State private var sort: Sort = .recent
    @State private var pendingDelete: GameInfo?
    @State private var appeared = false
    @Namespace private var chipNamespace

    enum Filter: CaseIterable {
        case all, playable, unsupported

        var title: String {
            switch self {
            case .all: return "Tất cả"
            case .playable: return "Chơi được"
            case .unsupported: return "Chưa hỗ trợ"
            }
        }

        func matches(_ game: GameInfo) -> Bool {
            switch self {
            case .all: return true
            case .playable: return game.isPlayable
            case .unsupported: return !game.isPlayable
            }
        }
    }

    enum Sort {
        case recent, name
    }

    private var playableCount: Int { library.games.filter(\.isPlayable).count }

    private var visibleGames: [GameInfo] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let matched = library.games.filter { game in
            filter.matches(game) && (q.isEmpty
                || game.displayTitle.localizedCaseInsensitiveContains(q)
                || game.engine.shortName.localizedCaseInsensitiveContains(q))
        }
        switch sort {
        case .recent:
            return matched.sorted { a, b in
                let da = a.lastPlayed ?? .distantPast, db = b.lastPlayed ?? .distantPast
                if da != db { return da > db }
                if a.isPlayable != b.isPlayable { return a.isPlayable }
                return a.displayTitle.localizedStandardCompare(b.displayTitle) == .orderedAscending
            }
        case .name:
            return matched.sorted { $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending }
        }
    }

    private var recentGames: [GameInfo] {
        library.games
            .filter { $0.isPlayable && $0.lastPlayed != nil }
            .sorted { ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) }
            .prefix(6)
            .map { $0 }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                summaryLine
                    .padding(.horizontal, 16)

                folderBanner
                    .padding(.horizontal, 16)

                if library.games.isEmpty {
                    if !library.isScanning { emptyLibrary }
                } else {
                    if query.isEmpty, filter != .unsupported, !recentGames.isEmpty {
                        recentSection
                    }
                    filterBar
                        .padding(.horizontal, 16)
                    gameGrid
                        .padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.immediately)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Game Hub")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Tìm game hoặc engine")
        .refreshable { library.refresh() }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Button { onPickFolder() } label: {
                        Label(library.gamesRoot == nil ? "Chọn thư mục game" : "Đổi thư mục game",
                              systemImage: "folder.badge.gearshape")
                    }
                    Button { library.refresh() } label: {
                        Label("Quét lại thư viện", systemImage: "arrow.clockwise")
                    }
                    .disabled(library.gamesRoot == nil || library.isScanning)
                } label: {
                    Image(systemName: "folder")
                }
                .accessibilityLabel("Thư mục game")

                Button { onOpenSettings() } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Cài đặt")
            }
        }
        .confirmationDialog(
            "Xoá \"\(pendingDelete?.displayTitle ?? "")\"?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { game in
            Button("Xoá thư mục game", role: .destructive) {
                CoverStore.shared.removeSnapshot(for: game)
                withAnimation(Theme.spring) { library.delete(game) }
            }
        } message: { _ in
            Text("Toàn bộ thư mục game (kể cả save trong thư mục) bị xoá khỏi máy, không hoàn tác được.")
        }
        .onAppear {
            guard !appeared else { return }
            withAnimation(Theme.spring) { appeared = true }
        }
    }

    // MARK: - Đầu trang

    private var summaryLine: some View {
        HStack(spacing: 6) {
            if library.games.isEmpty {
                Text(library.gamesRoot == nil ? "Chưa có thư viện" : "Thư viện trống")
            } else {
                Text("\(library.games.count) game")
                Text("·")
                Text("\(playableCount) chơi được").foregroundStyle(Theme.accent)
            }
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.secondary)
        .contentTransition(.numericText())
        .animation(Theme.spring, value: library.games.count)
    }

    @ViewBuilder
    private var folderBanner: some View {
        if library.gamesRoot == nil {
            VStack(alignment: .leading, spacing: 12) {
                Label("Chọn thư mục chứa game", systemImage: "folder.badge.plus")
                    .font(.headline)
                Text("Chọn một thư mục trong Files (có thể chứa thư mục con phân loại). App tự quét và nhớ thư mục này.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button { onPickFolder() } label: {
                    Text("Chọn thư mục")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(.white)
                }
                .buttonStyle(PressableButtonStyle())
            }
            .padding(16)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.cardStroke))
        } else if library.isScanning {
            let p = library.scanProgress
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Đang quét \(library.gamesRoot?.lastPathComponent ?? "")…")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    if p.total > 0 {
                        Text("\(p.done)/\(p.total)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                    }
                }
                ProgressView(value: Double(min(p.done, p.total)), total: Double(max(p.total, 1)))
                    .tint(Theme.accent)
                    .animation(.easeOut(duration: 0.3), value: p.done)
            }
            .padding(14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .transition(.move(edge: .top).combined(with: .opacity))
        } else if let msg = library.statusMessage {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(Theme.accent)
                Text(msg)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    withAnimation(Theme.spring) { library.statusMessage = nil }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Ẩn thông báo")
            }
            .padding(12)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .transition(.opacity)
        }
    }

    private var emptyLibrary: some View {
        VStack(spacing: 14) {
            Image(systemName: "gamecontroller")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.secondary)
                .symbolEffect(.pulse, options: .repeating)
            if library.gamesRoot != nil {
                Text("Không tìm thấy game nào")
                    .font(.headline)
                Text("Chép game vào \"On My iPhone → Game Hub → GameHub/\(library.gamesRoot?.lastPathComponent ?? "Games")\" trong Files rồi quét lại.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Quét lại") { library.refresh() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        .padding(.horizontal, 32)
    }

    // MARK: - Chơi tiếp

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Chơi tiếp")
                .font(.title3.weight(.bold))
                .padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(recentGames) { game in
                        RecentGameCard(game: game) { onPlay(game) }
                            .contextMenu { contextMenu(for: game) }
                            .scrollTransition(axis: .horizontal) { content, phase in
                                content
                                    .scaleEffect(phase.isIdentity ? 1 : 0.92)
                                    .opacity(phase.isIdentity ? 1 : 0.6)
                            }
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
        }
        .transition(.opacity)
    }

    // MARK: - Lọc + lưới

    private var filterBar: some View {
        HStack(spacing: 8) {
            ForEach(Filter.allCases, id: \.self) { item in
                let selected = item == filter
                Button {
                    withAnimation(Theme.spring) { filter = item }
                } label: {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .foregroundStyle(selected ? .white : .secondary)
                        .background {
                            if selected {
                                Capsule()
                                    .fill(Theme.accent)
                                    .matchedGeometryEffect(id: "chip", in: chipNamespace)
                            } else {
                                Capsule().fill(Theme.card)
                            }
                        }
                }
                .buttonStyle(PressableButtonStyle(scale: 0.94))
            }
            Spacer(minLength: 0)
            Menu {
                Picker("Sắp xếp", selection: $sort.animation(Theme.spring)) {
                    Label("Chơi gần đây", systemImage: "clock").tag(Sort.recent)
                    Label("Tên A–Z", systemImage: "textformat").tag(Sort.name)
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 34, height: 34)
                    .background(Theme.card, in: Circle())
            }
            .accessibilityLabel("Sắp xếp")
        }
    }

    @ViewBuilder
    private var gameGrid: some View {
        let games = visibleGames
        if games.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text(query.isEmpty ? "Không có game nào trong mục này" : "Không tìm thấy \"\(query)\"")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
            .transition(.opacity)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 18) {
                ForEach(Array(games.enumerated()), id: \.element.id) { index, game in
                    GameCard(game: game) {
                        game.isPlayable ? onPlay(game) : onShowInfo(game)
                    }
                    .contextMenu { contextMenu(for: game) }
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 18)
                    .animation(Theme.spring.delay(Double(min(index, 12)) * 0.035), value: appeared)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            }
        }
    }

    @ViewBuilder
    private func contextMenu(for game: GameInfo) -> some View {
        if game.isPlayable {
            Button { onPlay(game) } label: { Label("Chơi", systemImage: "play.fill") }
        }
        Button { onShowInfo(game) } label: { Label("Thông tin", systemImage: "info.circle") }
        if CoverStore.shared.hasSnapshot(for: game) {
            Button { CoverStore.shared.removeSnapshot(for: game) } label: {
                Label("Xoá ảnh bìa đã chụp", systemImage: "photo.badge.minus")
            }
        }
        Divider()
        Button(role: .destructive) { pendingDelete = game } label: {
            Label("Xoá game…", systemImage: "trash")
        }
    }
}

// MARK: - Thẻ game

private struct GameCard: View {
    let game: GameInfo
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Color.clear
                    .aspectRatio(4 / 3, contentMode: .fit)
                    .overlay { GameCoverView(game: game, maxPixel: 480) }
                    .saturation(game.isPlayable ? 1 : 0)
                    .opacity(game.isPlayable ? 1 : 0.55)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.cardStroke))
                    .overlay(alignment: .topTrailing) {
                        if !game.isPlayable {
                            Image(systemName: "lock.fill")
                                .font(.caption.weight(.bold))
                                .padding(6)
                                .background(.ultraThinMaterial, in: Circle())
                                .padding(8)
                        }
                    }
                    .overlay(alignment: .bottomLeading) {
                        if game.playCount > 0 {
                            Label("\(game.playCount)", systemImage: "play.fill")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(.ultraThinMaterial, in: Capsule())
                                .padding(8)
                        }
                    }
                    .shadow(color: .black.opacity(0.35), radius: 8, y: 4)

                Text(game.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(game.isPlayable ? .primary : .secondary)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)

                EngineChip(engine: game.engine)
            }
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(game.isPlayable ? "Mở game" : "Xem lý do chưa hỗ trợ")
    }
}

private struct RecentGameCard: View {
    let game: GameInfo
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            GameCoverView(game: game, maxPixel: 800)
                .frame(width: 290, height: 165)
                .overlay {
                    LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
                }
                .overlay(alignment: .bottomLeading) {
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(game.displayTitle)
                                .font(.headline)
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            if let played = game.lastPlayed {
                                Text(played.formatted(.relative(presentation: .named)))
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                        }
                        Spacer()
                        Image(systemName: "play.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 38, height: 38)
                            .background(.white, in: Circle())
                    }
                    .padding(12)
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.cardStroke))
                .shadow(color: .black.opacity(0.4), radius: 10, y: 5)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel("Chơi tiếp \(game.displayTitle)")
    }
}
