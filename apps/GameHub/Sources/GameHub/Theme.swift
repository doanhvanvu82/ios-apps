import SwiftUI

/// Hệ màu + animation dùng chung cho toàn app.
enum Theme {
    static let background = LinearGradient(
        colors: [Color(red: 0.06, green: 0.06, blue: 0.10), Color(red: 0.02, green: 0.02, blue: 0.04)],
        startPoint: .top, endPoint: .bottom)
    static let card = Color.white.opacity(0.06)
    static let cardStroke = Color.white.opacity(0.08)
    static let accent = Color(red: 0.45, green: 0.55, blue: 1.0)

    static let spring = Animation.spring(response: 0.38, dampingFraction: 0.82)
    static let snappy = Animation.spring(response: 0.25, dampingFraction: 0.9)
}

extension EngineKind {
    /// Màu nhấn riêng theo engine — dùng cho chip, ảnh bìa sinh tự động.
    var accent: Color {
        switch self {
        case .rpgMakerMV: return Color(red: 1.0, green: 0.58, blue: 0.25)
        case .renpyWeb, .renpyNative, .renpyOtherVersion: return Color(red: 1.0, green: 0.42, blue: 0.62)
        case .tyranoBuilder: return Color(red: 0.95, green: 0.35, blue: 0.35)
        case .unityWebGL, .unityWindows, .unityIL2CPP: return Color(red: 0.55, green: 0.68, blue: 0.80)
        case .godotWebGL, .godotNative, .godot: return Color(red: 0.30, green: 0.62, blue: 1.0)
        case .kirikiWeb, .kirikiNative, .kirikiri: return Color(red: 0.66, green: 0.48, blue: 1.0)
        case .flashWeb, .flashNative, .flashSWF: return Color(red: 1.0, green: 0.80, blue: 0.25)
        case .genericWeb: return Color(red: 0.30, green: 0.85, blue: 0.70)
        case .adobeAIR, .gameMaker, .unrealEngine, .pixelGameMaker, .exhibit, .unknown: return Color(white: 0.6)
        }
    }

    var symbol: String {
        switch self {
        case .renpyWeb: return "text.book.closed"
        case .rpgMakerMV: return "shield"
        case .tyranoBuilder: return "theatermasks"
        case .unityWebGL: return "cube.transparent"
        case .godotWebGL: return "globe.americas.fill"
        case .kirikiWeb: return "books.vertical.fill"
        case .flashWeb: return "bolt.fill"
        case .genericWeb: return "globe"
        case .godotNative: return "circle.hexagongrid.fill"
        case .kirikiNative: return "books.vertical"
        case .flashNative: return "bolt.circle"
        case .unityWindows: return "cube"
        case .unityIL2CPP: return "cube.fill"
        case .unrealEngine: return "u.square"
        case .pixelGameMaker: return "square.grid.3x3"
        case .exhibit: return "film.stack"
        case .renpyNative: return "text.book"
        case .renpyOtherVersion: return "book.closed"
        case .kirikiri: return "chevron.left.forwardslash.chevron.right"
        case .godot: return "circle.hexagongrid"
        case .flashSWF: return "bolt"
        case .adobeAIR: return "wind"
        case .gameMaker: return "square.stack.3d.up"
        case .unknown: return "questionmark.folder"
        }
    }

    /// Tên ngắn cho chip trên thẻ game (displayName đầy đủ quá dài).
    var shortName: String {
        switch self {
        case .renpyWeb, .renpyNative, .renpyOtherVersion: return "Ren'Py"
        case .rpgMakerMV: return "RPG Maker"
        case .tyranoBuilder: return "Tyrano"
        case .unityWebGL, .unityWindows, .unityIL2CPP: return "Unity"
        case .godotWebGL, .godotNative, .godot: return "Godot"
        case .kirikiWeb, .kirikiNative, .kirikiri: return "KiriKiri"
        case .flashWeb, .flashNative, .flashSWF: return "Flash"
        case .genericWeb: return "HTML5"
        case .adobeAIR: return "AIR"
        case .gameMaker: return "GameMaker"
        case .unrealEngine: return "Unreal"
        case .pixelGameMaker: return "PGMMV"
        case .exhibit: return "ExHIBIT"
        case .unknown: return "?"
        }
    }
}

/// Nút co nhẹ + rung khi bấm.
struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .brightness(configuration.isPressed ? -0.04 : 0)
            .animation(Theme.snappy, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { AppSettings.impact(0.5) }
            }
    }
}

/// Chip engine nhỏ (màu theo engine).
struct EngineChip: View {
    let engine: EngineKind

    var body: some View {
        Label(engine.shortName, systemImage: engine.symbol)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(engine.isPlayable ? engine.accent : .secondary)
            .background((engine.isPlayable ? engine.accent : .gray).opacity(0.16), in: Capsule())
    }
}

/// Nút tròn nhỏ trên nền kính — dùng trong màn chơi game.
struct GlassCircleButton: View {
    let systemImage: String
    var size: CGFloat = 32
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.44, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(.white.opacity(0.12), in: Circle())
        }
        .buttonStyle(PressableButtonStyle(scale: 0.9))
    }
}
