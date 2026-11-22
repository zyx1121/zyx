/// Bean, the agent in the island, and the clothes and props it wears.
///
/// Bean is drawn in square pixels on a grid 18 wide and 10 tall:
///
///     y 0-1  ......######......   round top
///     y 2-3  ...##EE#####EE##..   eyes, x 5-6 and x 12-13
///     y 4-6  .################.   body, little arms at x 1 and x 16
///     y 7    ....###########...
///     y 8-9  ....##.......##...   feet, x 4-5 and x 13-14
///
/// Every agent gets its own color and outfit from its session id, so the
/// same session always looks the same.
public enum Wardrobe {
    /// Where an accessory goes. Bean can wear one of each at a time, and
    /// they draw in this order, so glasses sit over a blush and a hat over
    /// both.
    public enum Slot: Int, CaseIterable, Sendable {
        case feet, body, face, eyes, head, leftHand, rightHand
    }

    public struct Accessory: Sendable, Identifiable {
        public let id: String
        public let slot: Slot
        /// The top left of `art` on Bean's grid.
        public let x: Int
        public let y: Int
        /// One string per row; a palette key per pixel, "." for none.
        public let art: [String]
    }

    /// A pixel's color, 0xRRGGBB, or nil where nothing is drawn.
    public typealias Grid = [[UInt32?]]

    /// The colors accessories and Bean's eyes use, by their key in `art`.
    public static let palette: [Character: UInt32] = [
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

    /// Bean's body colors; "C" in `bean` takes one of them.
    public static let colors: [UInt32] = [0x5BC8A8, 0x6AA8F0, 0xB08AE0, 0xF2B84B, 0xEE7C9A, 0x9CCB54]

    public static let bean = [
        "......CCCCCC......",
        "....CCCCCCCCCC....",
        "...CCWKCCCCCWKCC..",
        "...CCWWCCCCCWWCC..",
        "...CCCCCCCCCCCCC..",
        ".CCCCCCCCCCCCCCCC.",
        "...CCCCCCCCCCCCC..",
        "....CCCCCCCCCCC...",
        "....CC.......CC...",
        "....CC.......CC...",
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

    /// Bean in `color` wearing `items`, one per slot (a later item replaces
    /// an earlier one in the same slot), drawn in slot order. `x` and `y`
    /// give where Bean's grid starts inside the returned picture, which
    /// grows to fit whatever reaches past Bean.
    public static func dress(_ items: [Accessory], color: UInt32 = colors[0]) -> (x: Int, y: Int, grid: Grid) {
        var worn: [Slot: Accessory] = [:]
        for item in items { worn[item.slot] = item }
        let layers = [(0, 0, bean)] + Slot.allCases.compactMap { slot in
            worn[slot].map { ($0.x, $0.y, $0.art) }
        }
        let minX = layers.map(\.0).min()!, minY = layers.map(\.1).min()!
        let maxX = layers.map { $0.0 + ($0.2.map(\.count).max() ?? 0) }.max()!
        let maxY = layers.map { $0.1 + $0.2.count }.max()!
        var grid = Grid(repeating: Array(repeating: nil, count: maxX - minX), count: maxY - minY)
        for (x, y, art) in layers {
            for (row, line) in art.enumerated() {
                for (column, key) in line.enumerated() {
                    guard let pixel = key == "C" ? color : palette[key] else { continue }
                    grid[y + row - minY][x + column - minX] = pixel
                }
            }
        }
        return (-minX, -minY, grid)
    }

    /// The look of one agent: a color and up to one item each for the head,
    /// the eyes, the face, the body and a hand, picked from `seed`.
    public static func look(seed: String) -> (color: UInt32, items: [Accessory]) {
        // FNV-1a: stable across launches, unlike Hasher.
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in seed.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        let groups: [[Slot]] = [[.head], [.eyes], [.face], [.body], [.feet], [.leftHand, .rightHand]]
        var items: [Accessory] = []
        var bits = hash >> 8
        for slots in groups {
            let choices = all.filter { slots.contains($0.slot) }
            // One more choice than there are items: wearing nothing there.
            let pick = Int(bits % UInt64(choices.count + 1))
            bits /= UInt64(choices.count + 1)
            if pick < choices.count { items.append(choices[pick]) }
        }
        return (colors[Int(hash % UInt64(colors.count))], items)
    }
}
