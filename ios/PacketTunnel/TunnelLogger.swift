import Foundation

/// Structured log entry written to the shared App Group container (logs.jsonl).
struct TunnelLogEntry: Codable {
    let id: String
    let timestampMs: Int64
    let level: String
    let category: String
    let message: String
    var repeatCount: Int

    static func make(level: String, category: String, message: String) -> TunnelLogEntry {
        TunnelLogEntry(
            id: UUID().uuidString,
            timestampMs: Int64(Date().timeIntervalSince1970 * 1000),
            level: level,
            category: category,
            message: message,
            repeatCount: 1
        )
    }
}

/// Writes structured logs to the App Group shared container (logs.jsonl).
/// Each line is a JSON object.  The Flutter side reads and clears this file.
class TunnelLogger {

    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.example.flutterVpnGo.TunnelLogger", qos: .utility)
    private let maxLines = 1000
    private var lastEntry: TunnelLogEntry?

    init(appGroupId: String) {
        let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupId)
        fileURL = (container ?? URL(fileURLWithPath: NSTemporaryDirectory()))
            .appendingPathComponent("logs.jsonl")
    }

    func log(level: String, category: String, message: String) {
        // Also print to os_log for debugging in Xcode
        print("[VpnGo/\(level.uppercased())] [\(category)] \(message)")

        queue.async { [weak self] in
            guard let self = self else { return }
            // Group repeated messages
            if var last = self.lastEntry,
               last.level == level, last.category == category, last.message == message {
                last.repeatCount += 1
                self.lastEntry = last
                self.rewriteLast(entry: last)
                return
            }
            let entry = TunnelLogEntry.make(level: level, category: category, message: message)
            self.lastEntry = entry
            self.append(entry: entry)
        }
    }

    func debug(_ cat: String, _ msg: String)   { log(level: "debug",   category: cat, message: msg) }
    func info(_ cat: String, _ msg: String)    { log(level: "info",    category: cat, message: msg) }
    func warning(_ cat: String, _ msg: String) { log(level: "warning", category: cat, message: msg) }
    func error(_ cat: String, _ msg: String)   { log(level: "error",   category: cat, message: msg) }

    func clear() {
        queue.async { try? "".write(to: self.fileURL, atomically: true, encoding: .utf8) }
    }

    private func append(entry: TunnelLogEntry) {
        guard let line = encodeLine(entry) else { return }
        guard let handle = try? FileHandle(forWritingTo: fileURL) else {
            try? line.write(to: fileURL, atomically: true, encoding: .utf8)
            return
        }
        handle.seekToEndOfFile()
        handle.write(Data(line.utf8))
        try? handle.close()
        trimIfNeeded()
    }

    private func rewriteLast(entry: TunnelLogEntry) {
        guard let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8) else { return }
        var lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        if !lines.isEmpty, let newLine = encodeLine(entry) {
            lines[lines.count - 1] = newLine.trimmingCharacters(in: .newlines)
            try? lines.joined(separator: "\n").write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }

    private func trimIfNeeded() {
        guard let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8) else { return }
        var lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        if lines.count > maxLines {
            lines = Array(lines.suffix(maxLines))
            try? lines.joined(separator: "\n").write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }

    private func encodeLine(_ entry: TunnelLogEntry) -> String? {
        guard let data = try? JSONEncoder().encode(entry),
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str + "\n"
    }
}
