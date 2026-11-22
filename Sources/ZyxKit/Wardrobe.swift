/// Clothes and props for Clawd, in Clawd's own pixels.
///
/// Clawd's terminal pixels are twice as tall as wide, so here each one is
/// 2 square pixels stacked. On that grid, 18 wide and 10 tall:
///
///     y 0-1  ...#############..   head
///     y 2-3  ...##.#######.##..   eyes, holes at x 5 and x 13
///     y 4-5  .#################   arms, x 1-2 and x 16-17
///     y 6-7  ...#############..   belly
///     y 8-9  ...#.#.......#.#..   legs, x 3, 5, 13 and 15
///
/// An accessory is a small picture placed on that grid; it may reach past
/// it, above the head or out of a hand.
public enum Wardrobe {
    /// Where an accessory goes. Clawd can wear one of each at a time, and
    /// they draw in this order, so glasses sit over a blush and a hat over
    /// both.
    public enum Slot: Int, CaseIterable, Sendable {
        case feet, body, face, eyes, head, leftHand, rightHand
    }

    public struct Accessory: Sendable, Identifiable {
        public let id: String
        public let slot: Slot
        /// The top left of `art` on Clawd's grid.
        public let x: Int
        public let y: Int
        /// One string per row; a palette key per pixel, "." for none.
        public let art: [String]
    }

    /// A pixel's color, 0xRRGGBB, or nil where nothing is drawn.
    public typealias Grid = [[UInt32?]]

    /// The colors accessories use, by their key in `art`.
    public static let palette: [Character: UInt32] = [
        "C": 0xD77757, // Clawd
        "K": 0x1B1B1F, // black
        "D": 0x4A4A56, // charcoal: reads as black on the black island
        "W": 0xF4F1EA, // white
        "R": 0xE5484D, // red
        "Y": 0xF5C443, // gold
        "P": 0xF59AB5, // pink
        "B": 0x4C7DF0, // blue
        "N": 0x7A4A2A, // brown
        "S": 0xB8C0CC, // steel
        "G": 0x46A758, // green
    ]

    public static let clawd = [
        "...CCCCCCCCCCCCC..",
        "...CCCCCCCCCCCCC..",
        "...CC.CCCCCCC.CC..",
        "...CC.CCCCCCC.CC..",
        ".CCCCCCCCCCCCCCCCC",
        ".CCCCCCCCCCCCCCCCC",
        "...CCCCCCCCCCCCC..",
        "...CCCCCCCCCCCCC..",
        "...C.C.......C.C..",
        "...C.C.......C.C..",
    ]

    public static let all: [Accessory] = [
        // Head: sits on y -1 and up, centered on x 9.
        Accessory(id: "top-hat", slot: .head, x: 4, y: -6, art: [
            "..DDDDDDD..",
            "..DDDDDDD..",
            "..DDDDDDD..",
            "..DDDDDDD..",
            "..RRRRRRR..",
            "DDDDDDDDDDD",
        ]),
        Accessory(id: "crown", slot: .head, x: 5, y: -4, art: [
            "Y...Y...Y",
            "YY.YYY.YY",
            "YYYYRYYYY",
            "YYYYYYYYY",
        ]),
        Accessory(id: "party-hat", slot: .head, x: 6, y: -7, art: [
            "...Y...",
            "..PPP..",
            "..PBP..",
            ".PPPPP.",
            ".PYPPB.",
            "PPPPPPP",
            "PBPPPYP",
        ]),
        Accessory(id: "beanie", slot: .head, x: 3, y: -5, art: [
            "......W......",
            "....BBBBB....",
            "..BBBBBBBBB..",
            ".BBBBBBBBBBB.",
            "WWWWWWWWWWWWW",
        ]),
        // Eyes: the holes are at x 5 and x 13, y 2-3.
        Accessory(id: "sunglasses", slot: .eyes, x: 3, y: 2, art: [
            "DDDDDDDDDDDDD",
            ".DWD.....DWD.",
        ]),
        Accessory(id: "round-glasses", slot: .eyes, x: 3, y: 1, art: [
            ".WWW.....WWW.",
            "WW.WWWWWWW.WW",
            "W..W.....W..W",
            ".WWW.....WWW.",
        ]),
        Accessory(id: "heart-glasses", slot: .eyes, x: 3, y: 0, art: [
            "PP.PP...PP.PP",
            "PPPPPPPPPPPPP",
            ".PPP.....PPP.",
            "..P.......P..",
        ]),
        // Face: below the eyes.
        Accessory(id: "blush", slot: .face, x: 4, y: 4, art: [
            "PP.......PP",
        ]),
        Accessory(id: "mustache", slot: .face, x: 6, y: 4, art: [
            ".NN.NN.",
            "NN...NN",
        ]),
        // Body: the belly, y 6-7.
        Accessory(id: "scarf", slot: .body, x: 3, y: 5, art: [
            "RRRRRRRRRRRRR",
            "RWRWRWRWRWRWR",
            "..........RR.",
            "..........WR.",
            "..........RR.",
        ]),
        Accessory(id: "bow-tie", slot: .body, x: 7, y: 6, art: [
            "RR.RR",
            "RRYRR",
            "RR.RR",
        ]),
        // Feet: under the legs, y 10 and down.
        Accessory(id: "sneakers", slot: .feet, x: 2, y: 9, art: [
            ".R.R.......R.R.",
            "RRRRR.....RRRRR",
            "WWWWW.....WWWWW",
        ]),
        Accessory(id: "boots", slot: .feet, x: 2, y: 8, art: [
            ".N.N.......N.N.",
            ".N.N.......N.N.",
            "NNNNN.....NNNNN",
        ]),
        // Hands: the left arm ends at x 1, the right at x 17, both y 4-5.
        Accessory(id: "sword", slot: .leftHand, x: -1, y: -3, art: [
            ".S.",
            ".S.",
            ".S.",
            ".S.",
            ".S.",
            ".S.",
            "YYY",
            ".N.",
            ".N.",
            ".Y.",
        ]),
        Accessory(id: "balloon", slot: .leftHand, x: -3, y: -7, art: [
            ".RR.",
            "RRRR",
            "RRWR",
            "RRRR",
            ".RR.",
            "..S.",
            "..S.",
            "..S.",
            "...S",
            "...S",
            "...S",
        ]),
        Accessory(id: "coffee", slot: .rightHand, x: 18, y: 1, art: [
            ".S..",
            "..S.",
            "WWWW.",
            "WWW.W",
            "WWW.W",
            "WWWW.",
        ]),
        Accessory(id: "flower", slot: .rightHand, x: 18, y: -1, art: [
            ".P.",
            "PYP",
            ".P.",
            ".G.",
            "GG.",
            ".G.",
            ".G.",
        ]),
    ]

    public static func named(_ id: String) -> Accessory? {
        all.first { $0.id == id }
    }

    /// Clawd wearing `items`, one per slot (a later item replaces an earlier
    /// one in the same slot), drawn in slot order. `x` and `y` give where
    /// Clawd's grid starts inside the returned picture, which grows to fit
    /// whatever reaches past Clawd.
    public static func dress(_ items: [Accessory]) -> (x: Int, y: Int, grid: Grid) {
        var worn: [Slot: Accessory] = [:]
        for item in items { worn[item.slot] = item }
        let layers = [(0, 0, clawd)] + Slot.allCases.compactMap { slot in
            worn[slot].map { ($0.x, $0.y, $0.art) }
        }
        let minX = layers.map(\.0).min()!, minY = layers.map(\.1).min()!
        let maxX = layers.map { $0.0 + ($0.2.map(\.count).max() ?? 0) }.max()!
        let maxY = layers.map { $0.1 + $0.2.count }.max()!
        var grid = Grid(repeating: Array(repeating: nil, count: maxX - minX), count: maxY - minY)
        for (x, y, art) in layers {
            for (row, line) in art.enumerated() {
                for (column, key) in line.enumerated() {
                    guard let color = palette[key] else { continue }
                    grid[y + row - minY][x + column - minX] = color
                }
            }
        }
        return (-minX, -minY, grid)
    }
}
