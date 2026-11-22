/// Clawd, the Claude Code mascot, as Claude Code prints it: 3 rows of block
/// characters (the same rows as the Claude Code block on ui.winlab.tw).
public enum Clawd {
    public static let rows = [" ▐▛███▛█ ", "▝▜██████▀", " ▝▝   ▝▝ "]

    /// The body color, `--claude` on ui.winlab.tw.
    public static let rgb = (red: 0xD7, green: 0x77, blue: 0x57)

    /// Each character is a terminal cell of 2 by 2 quarter blocks, in the
    /// order top left, top right, bottom left, bottom right.
    static let quarters: [Character: [Bool]] = [
        " ": [false, false, false, false], "█": [true, true, true, true],
        "▌": [true, false, true, false], "▐": [false, true, false, true],
        "▀": [true, true, false, false], "▄": [false, false, true, true],
        "▘": [true, false, false, false], "▝": [false, true, false, false],
        "▖": [false, false, true, false], "▗": [false, false, false, true],
        "▛": [true, true, true, false], "▜": [true, true, false, true],
        "▙": [true, false, true, true], "▟": [false, true, true, true],
        "▚": [true, false, false, true], "▞": [false, true, true, false],
    ]

    /// The rows as a grid of pixels, twice as wide and twice as tall as the
    /// characters: `pixels[y][x]`, y from the top. A terminal cell is twice
    /// as tall as it is wide, so each pixel is too.
    public static func pixels(_ rows: [String] = rows) -> [[Bool]] {
        rows.flatMap { row -> [[Bool]] in
            let cells = row.map { quarters[$0] ?? quarters[" "]! }
            return [cells.flatMap { [$0[0], $0[1]] }, cells.flatMap { [$0[2], $0[3]] }]
        }
    }
}
