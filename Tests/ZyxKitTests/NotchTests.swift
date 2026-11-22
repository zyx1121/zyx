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
