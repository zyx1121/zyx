import Testing
@testable import ZyxKit

@Test func clawdIsEighteenBySixPixels() {
    let pixels = Clawd.pixels()
    #expect(pixels.count == 6)
    #expect(pixels.allSatisfy { $0.count == 18 })
    // "▐▛" opens the head: the right half of a cell, then a cell missing its
    // bottom right quarter.
    #expect(Array(pixels[0][2...5]) == [false, true, true, true])
    #expect(Array(pixels[1][2...5]) == [false, true, true, false])
}

@Test func everyGlyphIsKnown() {
    #expect(Clawd.rows.joined().allSatisfy { Clawd.quarters[$0] != nil })
}
