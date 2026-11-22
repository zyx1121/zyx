import Foundation

/// A running Claude Code session, as it describes itself in
/// `~/.claude/sessions/<pid>.json`.
public struct Agent: Equatable, Identifiable, Sendable {
    public enum Status: Equatable, Sendable {
        case working
        case idle
        case other(String)

        init(_ raw: String?) {
            switch raw {
            case "busy": self = .working
            case "idle", nil: self = .idle
            case let raw?: self = .other(raw)
            }
        }

        public var label: String {
            switch self {
            case .working: "Working"
            case .idle: "Idle"
            case .other(let raw): raw.prefix(1).uppercased() + raw.dropFirst().replacingOccurrences(of: "_", with: " ")
            }
        }
    }

    public let id: String
    public let pid: Int32
    /// Claude Code's name for it; the island shows the tmux tab title instead
    /// when there is one.
    public var name: String
    public let status: Status
    /// The tmux pane, like `%18`, when the session runs in tmux.
    public let pane: String?
    public let started: Double

    /// Reads one session file; nil when it is not a session.
    public init?(json: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let id = object["sessionId"] as? String,
              let pid = object["pid"] as? Int else { return nil }
        self.id = id
        self.pid = Int32(pid)
        name = object["name"] as? String ?? "Claude Code"
        status = Status(object["status"] as? String)
        // "0:@18.%18": session, window and pane.
        pane = (object["tmux"] as? String)?.split(separator: ".").last.map(String.init).flatMap {
            $0.hasPrefix("%") ? $0 : nil
        }
        started = object["startedAt"] as? Double ?? 0
    }

    /// The sessions whose process still runs, oldest first.
    public static func load(
        from directory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/sessions"),
        alive: (Int32) -> Bool = Agent.isRunning
    ) -> [Agent] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }
            .compactMap { (try? Data(contentsOf: $0)).flatMap(Agent.init(json:)) }
            .filter { alive($0.pid) }
            .sorted { $0.started < $1.started }
    }

    public static func isRunning(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }
}
