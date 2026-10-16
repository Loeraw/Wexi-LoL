import XCTest
@testable import RiftCore

final class LiveModelsTests: XCTestCase {
    func testRiotIDSpecialCharactersSurviveQueryEncoding() throws {
        let player = try JSONDecoder().decode(ActivePlayer.self, from: Data(#"{"riotId":"峡谷 & test#EUW","level":5,"currentGold":100.5}"#.utf8))
        let url = try XCTUnwrap(LiveEndpoint.scoresURL(for: player))
        let query = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(query.count, 1)
        XCTAssertEqual(query.first?.name, "riotId")
        XCTAssertEqual(query.first?.value, "峡谷 & test#EUW")
        XCTAssertEqual(url.host, "127.0.0.1")
        XCTAssertEqual(url.port, 2999)
    }
    func testLegacyClientNameAndMissingIdentity() throws {
        let player = try JSONDecoder().decode(ActivePlayer.self, from: Data(#"{"summonerName":"Riot Tuxedo","level":1,"currentGold":0}"#.utf8))
        let url = try XCTUnwrap(LiveEndpoint.scoresURL(for: player))
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.name, "summonerName")
        let missing = try JSONDecoder().decode(ActivePlayer.self, from: Data(#"{"level":1,"currentGold":0}"#.utf8))
        XCTAssertNil(LiveEndpoint.scoresURL(for: missing))
    }
    func testEarlyGameAndInvalidTimersDoNotProduceInvalidRate() {
        let demo = Snapshot.demo
        for time in [0.0, -1, 59, .infinity, .nan] {
            let value = Snapshot(player: demo.player, scores: demo.scores, game: GameStats(gameTime: time, gameMode: "CLASSIC"))
            XCTAssertEqual(value.csPerMinute, "—")
        }
        XCTAssertEqual(demo.timeLabel, "14:02")
        XCTAssertEqual(demo.csPerMinute, "8.0")
    }
    func testMalformedDataDoesNotBecomeFabricatedZeroStats() {
        XCTAssertThrowsError(try JSONDecoder().decode(Scores.self, from: Data(#"{"kills":4}"#.utf8)))
    }
}
