import XCTest
import SwiftUI
@testable import LightCal

final class SmokeTests: XCTestCase {
    func testDesignTokensAreDefined() {
        XCTAssertNotNil(DesignTokens.primary)
        XCTAssertEqual(DesignTokens.minTouchSize, 44)
    }

    func testColorHexDecoding() {
        let c = Color(hex: 0x0891B2)
        let ui = UIColor(c)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertEqual(r, 8.0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(g, 0x91 / 255.0, accuracy: 0.01)
        XCTAssertEqual(b, 0xB2 / 255.0, accuracy: 0.01)
    }
}
