import XCTest
@testable import RiftCore

final class SummonerProfileTests: XCTestCase {
    func testGlobalRegionMapping() {
        let expected: [String: OPGGRegion] = [
            "NA1": .na, "ME1": .me, "EUW1": .euw, "EUN1": .eune,
            "OC1": .oce, "KR": .kr, "JP1": .jp, "BR1": .br,
            "LA2": .las, "LA1": .lan, "RU": .ru, "TR1": .tr,
            "SG2": .sea, "PH2": .sea, "TH2": .sea, "TW2": .tw, "VN2": .vn
        ]
        for (platform, region) in expected {
            XCTAssertEqual(OPGGRegion.from(platformID: platform), region, platform)
        }
        XCTAssertNil(OPGGRegion.from(platformID: "PBE1"))
        XCTAssertEqual(OPGGRegion.inferred(fromRiotID: "Player#NA1"), .na)
        XCTAssertNil(OPGGRegion.inferred(fromRiotID: "Player#custom"))
    }

    func testGlobalProfileURLUsesSelectedRegionAndEscapesRiotID() {
        let url = SummonerProfileURL.make(riotID: "Name With Space#NA1", region: .na)
        XCTAssertEqual(url?.absoluteString, "https://op.gg/lol/summoners/na/Name%20With%20Space-NA1")
        XCTAssertNil(SummonerProfileURL.make(riotID: "missing-tag", region: .kr))
    }

    func testParsesRankAndRecentResultsFromJSONLD() throws {
        let json: [String: Any] = ["@context": "https://schema.org", "@graph": [
            ["@type": "ProfilePage", "description": "Palarun#EUW's current SOLORANKED rank is emerald 2 Division 2 6 LP with 68 wins, 48 losses, and a 59% win rate.", "dateModified": "2026-10-18T14:47:41+09:00"],
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
        XCTAssertNotNil(profile.updatedAt)
        XCTAssertFalse(profile.isStale(referenceDate: ISO8601DateFormatter().date(from: "2026-10-19T00:00:00Z")!))
    }

    func testUnrankedProfileStillKeepsRecentGames() throws {
        let html = #"<script type="application/ld+json">{"@graph":[{"@type":"ProfilePage","description":"No ranked data."},{"@type":"Person","name":"New#EUW"},{"@type":"ItemList","@id":"x#recent-games","itemListElement":[]}]}</script>"#
        let profile = try SummonerProfileParser.parse(html)
        XCTAssertEqual(profile.tier, "UNRANKED")
        XCTAssertNil(profile.winRate)
    }

    func testRejectsNonProfileStructuredData() throws {
        let html = #"<script type="application/ld+json">{"@graph":[{"@type":"WebPage","name":"OP.GG"}]}</script>"#
        XCTAssertThrowsError(try SummonerProfileParser.parse(html))
    }

    func testRiotIDIdentityAllowsCanonicalCaseAndWidthOnly() {
        XCTAssertTrue(RiotIDIdentity.matches("Player Name#EUW", "player name#euw"))
        XCTAssertTrue(RiotIDIdentity.matches("Ｐｌａｙｅｒ#ＥＵＷ", "Player#EUW"))
        XCTAssertFalse(RiotIDIdentity.matches("Player#EUW", "Other#EUW"))
        XCTAssertFalse(RiotIDIdentity.matches("Jose#EUW", "José#EUW"))
        XCTAssertFalse(RiotIDIdentity.matches("missing-tag", "missing-tag"))
    }

    func testProfileFreshnessTreatsMissingAndOldDatesAsStale() {
        let old = SummonerProfile(riotID: "Player#EUW", tier: "GOLD 1", leaguePoints: 1,
                                  wins: 2, losses: 3, winRate: 40, recent: [],
                                  updatedAt: Date(timeIntervalSince1970: 1_000))
        XCTAssertTrue(old.isStale(referenceDate: Date(timeIntervalSince1970: 200_000), maxAge: 10_000))
        let unknown = SummonerProfile(riotID: "Player#EUW", tier: "UNRANKED", leaguePoints: nil,
                                      wins: 0, losses: 0, winRate: nil, recent: [])
        XCTAssertTrue(unknown.isStale())
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
