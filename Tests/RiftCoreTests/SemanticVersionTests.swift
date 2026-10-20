import XCTest
@testable import RiftCore

final class SemanticVersionTests: XCTestCase {
    func testVersionComparisonHandlesPrefixesAndDifferentLengths() {
        XCTAssertTrue(SemanticVersion.isNewer("v0.5.8", than: "0.5.7"))
        XCTAssertTrue(SemanticVersion.isNewer("1.0", than: "0.9.9"))
        XCTAssertFalse(SemanticVersion.isNewer("0.5.7", than: "v0.5.7"))
        XCTAssertFalse(SemanticVersion.isNewer("0.5.7", than: "0.5.8"))
    }
}
