import XCTest
@testable import RiftCore

final class SummonerProfileTests: XCTestCase {
    func testParsesRankAndRecentResultsFromJSONLD() throws {
        let json: [String: Any] = ["@context": "https://schema.org", "@graph": [
            ["@type": "ProfilePage", "description": "Palarun#EUW's current SOLORANKED rank is emerald 2 Division 2 6 LP with 68 wins, 48 losses, and a 59% win rate."],
            ["@type": "Person", "name": "Palarun#EUW"],
            ["@type": "ItemList", "@id": "https://example.test#recent-games", "itemListElement": [
                ["position": 2, "item": ["additionalProperty": [["name": "result", "value": "LOSE"]]]],
                ["position": 1, "item": ["additionalProperty": [["name": "result", "value": "WIN"]]]]
            ]]
        ]]
        let data = try JSONSerialization.data(withJSONObject: json)
        let html = "<script type=\"application/ld+json\">\(String(data: data, encoding: .utf8)!)</script>"
        let profile = try SummonerProfileParser.parse(html)
        XCTAssertEqual(profile.riotID, "Palarun#EUW")
        XCTAssertEqual(profile.tier, "EMERALD 2")
        XCTAssertEqual(profile.leaguePoints, 6)
        XCTAssertEqual(profile.wins, 68)
        XCTAssertEqual(profile.losses, 48)
        XCTAssertEqual(profile.winRate, 59)
        XCTAssertEqual(profile.recent, [.win, .loss])
    }

    func testUnrankedProfileStillKeepsRecentGames() throws {
        let html = #"<script type="application/ld+json">{"@graph":[{"@type":"ProfilePage","description":"No ranked data."},{"@type":"Person","name":"New#EUW"},{"@type":"ItemList","@id":"x#recent-games","itemListElement":[]}]}</script>"#
        let profile = try SummonerProfileParser.parse(html)
        XCTAssertEqual(profile.tier, "UNRANKED")
        XCTAssertNil(profile.winRate)
    }

    func testFetchedPublicProfileWhenProvided() throws {
        guard let path = ProcessInfo.processInfo.environment["RIFT_SUMMONER_FIXTURE"] else {
            throw XCTSkip("Set RIFT_SUMMONER_FIXTURE for live-page smoke test")
        }
        let profile = try SummonerProfileParser.parse(String(contentsOfFile: path))
        XCTAssertFalse(profile.riotID.isEmpty)
        XCTAssertFalse(profile.recent.isEmpty)
    }
}
