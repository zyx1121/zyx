import Foundation

/// Dopamine mode: `pmset -a disablesleep 1`, so the Mac stays awake with the
/// lid closed. The system setting is the only state; the app never caches it.
public enum Dopamine {
    public static let sudoersPath = "/etc/sudoers.d/zyx"

    /// Reads `SleepDisabled` from `pmset -g`. Nil when pmset does not report it.
    public static func isOn() -> Bool? {
        guard let out = try? run("/usr/bin/pmset", ["-g"]).output else { return nil }
        return parse(out)
    }

    public static func parse(_ pmsetOutput: String) -> Bool? {
        for line in pmsetOutput.split(separator: "\n") {
            let fields = line.split(whereSeparator: \.isWhitespace)
            if fields.count >= 2, fields[0] == "SleepDisabled" {
                return fields[1] == "1"
            }
        }
        return nil
    }

    /// Sets the system setting. Without the sudoers rule, asks for the admin
    /// password once, installs the rule and sets the value in the same step.
    public static func set(_ on: Bool) throws {
        let value = on ? "1" : "0"
        if try run("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "-a", "disablesleep", value]).status == 0 {
            return
        }
        guard let rule = sudoersRule(user: NSUserName()) else {
            throw DopamineError.badUser(NSUserName())
        }
        let script = installScript(rule: rule) + " && /usr/bin/pmset -a disablesleep \(value)"
        let result = try run("/usr/bin/osascript", [
            "-e", "on run argv",
            "-e", "do shell script (item 1 of argv) with prompt \"zyx needs your password once to switch Dopamine.\" with administrator privileges",
            "-e", "end run",
            script,
        ])
        if result.status != 0 { throw DopamineError.failed(result.error) }
    }

    /// The sudoers rule: this user may run exactly these 2 commands as root,
    /// without a password. Nil for a user name that is not a plain account name.
    public static func sudoersRule(user: String) -> String? {
        guard user.range(of: "^[a-z_][a-z0-9_.-]*$", options: .regularExpression) != nil else { return nil }
        return """
        # Installed by zyx (github.com/zyx1121/zyx): switch Dopamine without a password.
        \(user) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1

        """
    }

    /// A root shell command that checks the rule with visudo and installs it
    /// as root:wheel 0440. A rule that fails the check is never installed.
    public static func installScript(rule: String) -> String {
        let encoded = Data(rule.utf8).base64EncodedString()
        return "t=$(/usr/bin/mktemp /tmp/zyx-sudoers.XXXXXX)"
            + " && /bin/echo \(encoded) | /usr/bin/base64 -D > \"$t\""
            + " && /usr/sbin/visudo -cf \"$t\" >/dev/null"
            + " && /usr/bin/install -m 0440 -o root -g wheel \"$t\" \(sudoersPath)"
            + "; s=$?; /bin/rm -f \"$t\"; [ $s -eq 0 ]"
    }

    struct Result {
        let status: Int32
        let output: String
        let error: String
    }

    static func run(_ path: String, _ args: [String]) throws -> Result {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        p.standardInput = FileHandle.nullDevice
        try p.run()
        let o = out.fileHandleForReading.readDataToEndOfFile()
        let e = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return Result(
            status: p.terminationStatus,
            output: String(decoding: o, as: UTF8.self),
            error: String(decoding: e, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

public enum DopamineError: LocalizedError {
    case badUser(String)
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case let .badUser(name): "User name \(name) cannot go in a sudoers rule."
        case let .failed(message): message.isEmpty ? "pmset did not change." : message
        }
    }
}
