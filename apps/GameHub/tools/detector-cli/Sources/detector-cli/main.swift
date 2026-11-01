import Foundation

// detector-cli <thư-mục-game>... → mỗi dòng một JSON:
// {"path", "engine", "name", "playable", "reason", "entry", "packed"}
for path in CommandLine.arguments.dropFirst() {
    let detected = EngineDetector.detect(in: URL(fileURLWithPath: path, isDirectory: true))
    let engine = detected.engine
    let row: [String: Any] = [
        "path": path,
        "engine": String(describing: engine),
        "name": engine.displayName,
        "playable": engine.isPlayable,
        "reason": engine.unsupportedReason ?? "",
        "entry": detected.entryPath ?? NSNull(),
        "packed": detected.isAsar,
    ]
    let data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
}
