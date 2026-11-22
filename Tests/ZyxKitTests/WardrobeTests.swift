import Testing
@testable import ZyxKit

@Test func wardrobeClawdMatchesTheBlockCharacters() {
    // Each terminal pixel is 2 square pixels tall; the last terminal row is empty.
    let doubled = Clawd.pixels().flatMap { [$0, $0] }.prefix(10)
    let drawn = Wardrobe.clawd.map { $0.map { $0 == "C" } }
    #expect(Array(doubled) == drawn)
}

@Test func everyAccessoryUsesThePalette() {
    for item in Wardrobe.all {
        #expect(item.art.joined().allSatisfy { $0 == "." || Wardrobe.palette[$0] != nil }, "\(item.id)")
    }
    #expect(Set(Wardrobe.all.map(\.id)).count == Wardrobe.all.count)
}

@Test func sunglassesCoverBothEyes() {
    let (x, y, grid) = Wardrobe.dress([Wardrobe.named("sunglasses")!])
    let black = Wardrobe.palette["D"]
    #expect(grid[y + 2][x + 5] == black)
    #expect(grid[y + 2][x + 13] == black)
}

@Test func oneItemPerSlotAndHatsOverGlasses() {
    let dressed = Wardrobe.dress(["crown", "top-hat", "sunglasses"].compactMap(Wardrobe.named))
    // The top hat replaced the crown, so the picture starts 6 rows above Clawd.
    #expect(dressed.y == 6)
    let plain = Wardrobe.dress([])
    #expect(plain.x == 0 && plain.y == 0 && plain.grid.count == 10)
}
