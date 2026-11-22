import Foundation

/// A Claude Code session that finished a turn, as the Stop hook reports it
/// with `zyx://done?pane=%16&title=…&message=…&active=0`.
public struct Notice: Equatable, Sendable {
    /// The tmux pane the session runs in, such as `%16`.
    public let pane: String
    /// The session name, or "Claude Code" when the session has none yet.
    public let title: String
    /// The first line of Claude's last reply.
    public let message: String
    /// Whether the pane's tmux window was the one on screen.
    public let active: Bool

    public init?(url: URL) {
        guard url.scheme == "zyx", url.host == "done",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        else { return nil }
        let query = Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { _, last in last })
        guard let pane = query["pane"], pane.hasPrefix("%"), pane.dropFirst().allSatisfy(\.isNumber),
              pane.count > 1
        else { return nil }
        self.pane = pane
        let title = query["title", default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = title.isEmpty ? "Claude Code" : title
        message = query["message", default: ""]
            .split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        active = query["active"] == "1"
    }

    /// Whether to show it: not when its window is on screen in the terminal
    /// the person is looking at.
    public func worthShowing(terminalInFront: Bool) -> Bool {
        !(active && terminalInFront)
    }

    /// The tmux commands that bring its pane on screen.
    public var jump: [[String]] {
        [["select-window", "-t", pane], ["select-pane", "-t", pane]]
    }
}
