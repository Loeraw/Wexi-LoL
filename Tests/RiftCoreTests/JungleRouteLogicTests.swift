import XCTest
@testable import RiftCore

final class JungleRouteLogicTests: XCTestCase {
    func testFullClearClosesAtLevelFour() {
        XCTAssertFalse(JungleRouteCompletion.shouldClose(route: "fullClear", activeLevel: 3, gameTime: 220))
        XCTAssertTrue(JungleRouteCompletion.shouldClose(route: "fullClear", activeLevel: 4, gameTime: 220))
    }

    func testShortRoutesCloseAtLevelThreeAfterJungleSpawn() {
        XCTAssertFalse(JungleRouteCompletion.shouldClose(route: "levelThree", activeLevel: 3, gameTime: 80))
        XCTAssertTrue(JungleRouteCompletion.shouldClose(route: "levelThree", activeLevel: 3, gameTime: 150))
        XCTAssertTrue(JungleRouteCompletion.shouldClose(route: "invade", activeLevel: 3, gameTime: 150))
    }
}
