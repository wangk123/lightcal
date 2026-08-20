import XCTest
@testable import LightCal

final class VisionSpeechTests: XCTestCase {
    func testLabelMappingKnownFoods() {
        XCTAssertEqual(VisionFoodRecognizer.localizedName("Rice"), "米饭")
        XCTAssertEqual(VisionFoodRecognizer.localizedName("chicken"), "鸡肉")
        XCTAssertEqual(VisionFoodRecognizer.localizedName("sweet potato"), "红薯")
        XCTAssertEqual(VisionFoodRecognizer.localizedName("SomeUnknownThing"), "SomeUnknownThing")
    }

    func testCGImageFromPNGData() throws {
        // 1x1 透明 PNG
        let pngBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        let data = Data(base64Encoded: pngBase64)!
        XCTAssertNotNil(VisionFoodRecognizer.makeCGImage(data))
    }

    func testCGImageFromGarbageReturnsNil() {
        XCTAssertNil(VisionFoodRecognizer.makeCGImage(Data([0x00, 0x01])))
    }

    func testSpeechErrorEquatable() {
        XCTAssertEqual(SpeechTranscriberError.unavailable, .unavailable)
    }
}
