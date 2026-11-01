import Foundation

// Thay cho phần phụ thuộc iOS/app mà mã nhận diện tham chiếu tới.
enum EngineRuntime {
    case godot4, godot45, godot3, kiriki, ruffle, renpy, renpy85
    static func directory(for runtime: EngineRuntime) -> URL? { nil }
}

enum AppLog {
    static func info(_ message: String) {}
    static func warn(_ message: String) {}
    static func error(_ message: String) {}
}
