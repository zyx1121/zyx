import Testing
@testable import ZyxKit

@Test func everyAccessoryUsesThePalette() {
    for item in Wardrobe.all {
        #expect(item.art.joined().allSatisfy { $0 == "." || Wardrobe.palette[$0] != nil }, "\(item.id)")
    }
    #expect(Set(Wardrobe.all.map(\.id)).count == Wardrobe.all.count)
    #expect(Wardrobe.bean.allSatisfy { $0.count == 18 })
}

@Test func sunglassesCoverBothEyes() {
    let (x, y, grid) = Wardrobe.dress([Wardrobe.named("sunglasses")!])
    let black = Wardrobe.palette["D"]
    #expect(grid[y + 2][x + 5] == black)
    #expect(grid[y + 2][x + 13] == black)
}

@Test func oneItemPerSlotAndHatsOverGlasses() {
    let dressed = Wardrobe.dress(["crown", "top-hat", "sunglasses"].compactMap(Wardrobe.named))
    // The top hat replaced the crown, so the picture starts 6 rows above Bean.
    #expect(dressed.y == 6)
    let plain = Wardrobe.dress([], color: 0x123456)
    #expect(plain.x == 0 && plain.y == 0 && plain.grid.count == 10)
    #expect(plain.grid[5][1] == 0x123456)
}

@Test func aSessionAlwaysLooksTheSame() {
    let one = Wardrobe.look(seed: "e969af17-becf-48c6-a01f-6c87788c0152")
    let again = Wardrobe.look(seed: "e969af17-becf-48c6-a01f-6c87788c0152")
    #expect(one.color == again.color && one.items.map(\.id) == again.items.map(\.id))
    #expect(Set(one.items.map(\.slot)).count == one.items.count)
    // Different sessions mostly look different.
    let looks = Set((0..<20).map { seed in
        let look = Wardrobe.look(seed: "session-\(seed)")
        return "\(look.color) \(look.items.map(\.id))"
    })
    #expect(looks.count > 15)
}
