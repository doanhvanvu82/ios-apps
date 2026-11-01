import SwiftUI

/// Sheet thông tin game — mở khi bấm game chưa hỗ trợ, hoặc "Thông tin"
/// trong context menu.
struct GameInfoSheet: View {
    let game: GameInfo
    let onPlay: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showingLog = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GameCoverView(game: game, maxPixel: 900)
                    .frame(height: 210)
                    .frame(maxWidth: .infinity)
                    .saturation(game.isPlayable ? 1 : 0)
                    .overlay {
                        LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
                    }
                    .overlay(alignment: .bottomLeading) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(game.displayTitle)
                                .font(.title2.weight(.bold))
                                .foregroundStyle(.white)
                                .lineLimit(3)
                            EngineChip(engine: game.engine)
                        }
                        .padding(16)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                HStack(spacing: 12) {
                    stat(title: "Số lần chơi", value: "\(game.playCount)", symbol: "play.circle")
                    stat(title: "Lần cuối",
                         value: game.lastPlayed?.formatted(.relative(presentation: .named)) ?? "Chưa chơi",
                         symbol: "clock")
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Engine").font(.caption).foregroundStyle(.secondary)
                    Text(game.engine.displayName).font(.body.weight(.medium))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                if let reason = game.engine.unsupportedReason {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Chưa chơi được trên iPhone").font(.subheadline.weight(.semibold))
                            Text(reason).font(.subheadline).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                if game.isPlayable {
                    Button {
                        onPlay()
                        dismiss()
                    } label: {
                        Label("Chơi", systemImage: "play.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(PressableButtonStyle())
                }

                // Log riêng của game — xem lại lỗi của lần chơi trước sau khi đã thoát.
                Button {
                    showingLog = true
                } label: {
                    Label("Xem log của game", systemImage: "terminal")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(PressableButtonStyle())
            }
            .padding(20)
        }
        .sheet(isPresented: $showingLog) {
            DebugLogView(game: (game.folderName, game.displayTitle))
        }
        .background(Theme.background.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
    }

    private func stat(title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
