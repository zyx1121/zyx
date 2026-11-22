import Foundation

/// A running Claude Code session, as it describes itself in
/// `~/.claude/sessions/<pid>.json`.
public struct Agent: Equatable, Identifiable, Sendable {
    public enum Status: Equatable, Sendable {
        case working
        case idle
        /// Waiting for the person: a question, a dialog, a permission. The
        /// reason is Claude Code's own words, like "input needed".
        case waiting(String?)
        case other(String)

        init(_ raw: String?, waitingFor: String?) {
            switch raw {
            case "busy": self = .working
            case "idle", nil: self = .idle
            case "waiting": self = .waiting(waitingFor)
            case let raw?: self = .other(raw)
            }
        }

        public var label: String {
            switch self {
            case .working: "Working"
            case .idle: "Idle"
            case .waiting(let reason): reason.map(Self.sentence) ?? "Needs you"
            case .other(let raw): Self.sentence(raw)
            }
        }

        public var isWaiting: Bool {
            if case .waiting = self { true } else { false }
        }

        private static func sentence(_ raw: String) -> String {
            raw.prefix(1).uppercased() + raw.dropFirst().replacingOccurrences(of: "_", with: " ")
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
    /// When the status last changed, in milliseconds since 1970.
    public let since: Double

    /// Reads one session file; nil when it is not a session.
    public init?(json: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let id = object["sessionId"] as? String,
              let pid = object["pid"] as? Int else { return nil }
        self.id = id
        self.pid = Int32(pid)
        name = object["name"] as? String ?? "Claude Code"
        status = Status(object["status"] as? String, waitingFor: object["waitingFor"] as? String)
        // "0:@18.%18": session, window and pane.
        pane = (object["tmux"] as? String)?.split(separator: ".").last.map(String.init).flatMap {
            $0.hasPrefix("%") ? $0 : nil
        }
        started = object["startedAt"] as? Double ?? 0
        since = object["statusUpdatedAt"] as? Double ?? started
    }

    /// How long the status has held, short: "<1m", "12m", "2h 5m".
    public func elapsed(now: Date = Date()) -> String {
        let minutes = max(0, Int(now.timeIntervalSince1970 - since / 1000)) / 60
        if minutes < 1 { return "<1m" }
        if minutes < 60 { return "\(minutes)m" }
        return minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(minutes % 60)m"
    }

    /// The sessions whose process still runs: those waiting for the person
    /// first, then the rest, oldest first.
    public static func load(
        from directory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/sessions"),
        alive: (Int32) -> Bool = Agent.isRunning
    ) -> [Agent] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }
            .compactMap { (try? Data(contentsOf: $0)).flatMap(Agent.init(json:)) }
            .filter { alive($0.pid) }
            .sorted { ($0.status.isWaiting ? 0 : 1, $0.started) < ($1.status.isWaiting ? 0 : 1, $1.started) }
    }

    public static func isRunning(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    /// What an agent is doing to the Mac, from the stickd command it sent;
    /// nil for commands that only read, which the island does not show.
    public static func action(_ command: String) -> String? {
        switch command {
        case "click": "Clicking"
        case "move": "Moving the cursor"
        case "scroll": "Scrolling"
        case "key": "Pressing keys"
        case "type", "paste": "Typing"
        case "shot": "Looking at the screen"
        case "snap": "Reading the screen"
        case "focus": "Switching windows"
        case "exec", "invoke", "set": "Using an app"
        default: nil
        }
    }
}
