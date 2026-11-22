import CoreGraphics
import Testing
@testable import ZyxKit

@Test func macBookAirNotch() {
    // Measured on a 13-inch MacBook Air M2 at its default scaled size.
    let frame = CGRect(x: 0, y: 0, width: 1710, height: 1112)
    let left = CGRect(x: 0, y: 1074.5, width: 751, height: 37.5)
    let right = CGRect(x: 959, y: 1074.5, width: 751, height: 37.5)
    #expect(Notch.rect(frame: frame, left: left, right: right, top: 37.5)
        == CGRect(x: 751, y: 1074.5, width: 208, height: 37.5))
}

@Test func noNotch() {
    let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    #expect(Notch.rect(frame: frame, left: nil, right: nil, top: 0) == nil)
}

@Test func hoverEntersOnNotchAndLeavesPastGrown() {
    let notch = CGRect(x: 751, y: 1074.5, width: 208, height: 37.5)
    let grown = Notch.grown(notch, by: CGSize(width: 40, height: 12))
    #expect(grown == CGRect(x: 731, y: 1062.5, width: 248, height: 49.5))
    // The top edge, where the cursor rests when pushed up.
    #expect(Notch.hovers(CGPoint(x: 855, y: 1112), notch: notch, grown: grown, hovering: false))
    // Beside the notch: not yet in, but still in once hovering.
    let side = CGPoint(x: 740, y: 1100)
    #expect(!Notch.hovers(side, notch: notch, grown: grown, hovering: false))
    #expect(Notch.hovers(side, notch: notch, grown: grown, hovering: true))
    #expect(!Notch.hovers(CGPoint(x: 855, y: 1000), notch: notch, grown: grown, hovering: true))
}
