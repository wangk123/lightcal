import XCTest
@testable import LightCal

final class VisionSpeechTests: XCTestCase {
    func testLabelMappingKnownFoods() {
        XCTAssertEqual(VisionFoodRecognizer.localizedName("Rice"), "米饭")
        XCTAssertEqual(VisionFoodRecognizer.localizedName("chicken"), "鸡肉")
        XCTAssertEqual(VisionFoodRecognizer.localizedName("sweet_potato"), "红薯")   // 下划线归一化
        XCTAssertEqual(VisionFoodRecognizer.localizedName("fried_rice"), "炒饭")
        XCTAssertEqual(VisionFoodRecognizer.localizedName("steak"), "牛排")
        XCTAssertEqual(VisionFoodRecognizer.localizedName("watermelon"), "西瓜")
        XCTAssertEqual(VisionFoodRecognizer.localizedName("dumpling"), "饺子")
        XCTAssertEqual(VisionFoodRecognizer.localizedName("SomeUnknownThing"), "SomeUnknownThing")
    }

    func testFoodLabelFiltering() {
        // 食物标签通过
        XCTAssertTrue(VisionFoodRecognizer.isFoodLabel("fried_rice"))
        XCTAssertTrue(VisionFoodRecognizer.isFoodLabel("chicken"))
        // 通用物体分类器的非食物类别必须被过滤（用户实拍案例：computer/computer_mouse 混入）
        XCTAssertFalse(VisionFoodRecognizer.isFoodLabel("computer"))
        XCTAssertFalse(VisionFoodRecognizer.isFoodLabel("computer_mouse"))
        XCTAssertFalse(VisionFoodRecognizer.isFoodLabel("consumer_electronics"))
        XCTAssertFalse(VisionFoodRecognizer.isFoodLabel("cord"))
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
