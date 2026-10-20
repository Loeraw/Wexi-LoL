import XCTest
@testable import RiftCore

final class MinimapRecognitionTests: XCTestCase {
    func testDetectsScaledBottomRightMinimapEdge() {
        let width = 1000, height = 600, side = 180, left = width - side
        var pixels = [UInt8](repeating: 40, count: width * height)
        for y in 0..<Int(Double(height) * 0.4) {
            for x in left..<width { pixels[y * width + x] = 190 }
        }
        let frame = MinimapFrameRecognition.normalizedFrame(width: width, height: height, grayscale: pixels)
        XCTAssertNotNil(frame)
        XCTAssertEqual(frame?.maxX ?? 0, 1, accuracy: 0.002)
        XCTAssertEqual((frame?.width ?? 0) * Double(width), Double(side + 1), accuracy: 1)
        XCTAssertEqual((frame?.height ?? 0) * Double(height), Double(side + 1), accuracy: 1)
    }

    func testRejectsFlatFrame() {
        let pixels = [UInt8](repeating: 80, count: 800 * 500)
        XCTAssertNil(MinimapFrameRecognition.normalizedFrame(width: 800, height: 500, grayscale: pixels))
    }
}
