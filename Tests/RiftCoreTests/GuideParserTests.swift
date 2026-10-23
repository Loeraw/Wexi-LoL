import XCTest
@testable import RiftCore

final class GuideParserTests: XCTestCase {
    private func page(_ object: Any) throws -> String {
        let json = String(data: try JSONSerialization.data(withJSONObject: object), encoding: .utf8)!
        let flight = "a:" + json + "\n"
        let split = flight.index(flight.startIndex, offsetBy: flight.count / 2)
        return try [String(flight[..<split]), String(flight[split...])].map { piece in
            let data = try JSONSerialization.data(withJSONObject: [1, piece])
            return "<script>self.__next_f.push(\(String(data: data, encoding: .utf8)!))</script>"
        }.joined()
    }
    func testSplitFlightUnicodeTierZeroAndMissingRecords() throws {
        let html = try page(["props": ["query": ["patch": "16.20"], "data": [
            ["id": 1071, "tier": 0, "rarity": 4, "key": "ARAM_ScopierWeapons", "name": "更万用的瞄准镜",
             "win_rate": 54.3, "pick_rate": 12.8, "play": "1,234"],
            ["id": 9999, "tier": 5]
        ]]])
        let output = try GuideParser.parse(html)
        XCTAssertEqual(output.patch, "16.20")
        XCTAssertEqual(output.augments.count, 1)
        XCTAssertEqual(output.augments[0].tierLabel, "S")
        XCTAssertEqual(output.augments[0].winRate, 54.3)
        XCTAssertEqual(output.augments[0].pickRate, 12.8)
        XCTAssertEqual(output.augments[0].games, 1_234)
        XCTAssertTrue(output.augments[0].matches("Scopier Weapons"))
        XCTAssertTrue(output.augments[0].matches("瞄准镜"))
    }
    func testSkillSelectionUsesLargestSampleAndDoesNotInventLevels() throws {
        let html = try page(["skill_masteries": [
            ["ids": ["Q", "W", "E"], "play": 1, "builds": [["order": ["Q"], "play": 1]]],
            ["ids": ["E", "Q", "W"], "play": 100, "builds": [["order": ["E", "Q", "W"], "play": 90], ["order": ["Q"], "play": 10]]]
        ]])
        let result = try GuideParser.parse(html)
        XCTAssertEqual(result.skills?.priority, ["E", "Q", "W"])
        XCTAssertEqual(result.skills?.order.count, 3)
        XCTAssertEqual(result.skills?.samples, 90)
    }
    func testUnknownHTMLFailsInsteadOfInventingRatings() {
        XCTAssertThrowsError(try GuideParser.parse("<html>Site unavailable</html>"))
    }
    func testMayhemStatsParsesEmbeddedGlobalRatesByRiotID() throws {
        let html = try page([
            "initialRows": [
                ["id": 2031, "name": "DropBear", "wr": 54.71, "pr": 1.67, "n": 5_800_000],
                ["id": 1353, "name": "Tank Engine", "wr": "50.75", "pr": "5.17", "n": "18,000,000"],
                ["id": 9999, "wr": 120, "pr": 1, "n": 10]
            ],
            "initialMeta": ["patch": "16.20"]
        ])
        let result = try MayhemStatsParser.parse(html)
        XCTAssertEqual(result.patch, "16.20")
        XCTAssertEqual(result.stats.count, 2)
        XCTAssertEqual(result.stats[2031]?.winRate, 54.71)
        XCTAssertEqual(result.stats[2031]?.pickRate, 1.67)
        XCTAssertEqual(result.stats[1353]?.games, 18_000_000)
    }
    func testItemBuildParsesWinRateSamplesAndLocalizedMetadata() throws {
        let items: [[String: Any]] = [
            ["id": 3115, "name": "纳什之牙", "image_url": "https://cdn.example/3115.png"],
            ["id": 2510, "name": "黎明与黄昏", "image_url": "https://cdn.example/2510.png"],
            ["id": 3089, "name": "灭世者的死亡之帽", "image_url": "https://cdn.example/3089.png"]
        ]
        let html = try page(["props": ["query": ["patch": "16.20"], "data": [[
            "ids": [3115, 2510, 3089], "play": "1,234", "pick_rate": 11.6,
            "win_rate": 56.7, "metaBuildItems": items
        ]]]])
        let result = try GuideParser.parse(html)
        XCTAssertEqual(result.itemBuilds.count, 1)
        XCTAssertEqual(result.itemBuilds[0].items.map(\.id), [3115, 2510, 3089])
        XCTAssertEqual(result.itemBuilds[0].items.first?.name, "纳什之牙")
        XCTAssertEqual(result.itemBuilds[0].games, 1234)
        XCTAssertEqual(result.itemBuilds[0].winRate, 56.7, accuracy: 0.001)
    }
    func testRecommendedLoadoutChoosesLargestSampleAndReadsSpells() throws {
        let html = try page(["data": [
            ["play": 90, "pick_rate": 0.1, "win_rate": 0.51, "importClientData": [
                "primaryStyleId": 8200, "subStyleId": 8100,
                "selectedPerkIds": [8214, 8226, 8210, 8237, 8139, 8106, 5008, 5008, 5001]
            ]],
            ["play": 1_200, "pick_rate": 0.7, "win_rate": 0.53, "importClientData": [
                "primaryStyleId": 8100, "subStyleId": 8200,
                "selectedPerkIds": [8112, 8139, 8140, 8106, 8210, 8226, 5005, 5008, 5001]
            ]],
            ["children": [
                ["metaId": 4, "metaType": "spell"],
                ["metaId": 14, "metaType": "spell"]
            ]]
        ]])
        let loadout = try XCTUnwrap(GuideParser.parse(html).loadout)
        XCTAssertEqual(loadout.primaryStyleID, 8100)
        XCTAssertEqual(loadout.secondaryStyleID, 8200)
        XCTAssertEqual(loadout.selectedPerkIDs.count, 9)
        XCTAssertEqual(loadout.spellIDs, [4, 14])
        XCTAssertEqual(loadout.games, 1_200)
    }
    func testRecommendedLoadoutIncludesSelectedPerkMetadata() throws {
        let selected = [8112, 8139, 8140, 8106, 8210, 8226, 5005, 5008, 5001]
        let metadata = selected.map { id in
            ["id": id, "name": "Perk \(id)",
             "image_url": "https://cdn.example/perk/\(id).png"] as [String: Any]
        }
        let html = try page(["data": [[
            "play": 1_200, "pick_rate": 0.7, "win_rate": 0.53,
            "importClientData": ["primaryStyleId": 8100, "subStyleId": 8200,
                                 "selectedPerkIds": selected],
            "main_runes": metadata
        ]]])
        let loadout = try XCTUnwrap(GuideParser.parse(html).loadout)
        XCTAssertEqual(loadout.perks.map(\.id), selected)
        XCTAssertEqual(loadout.perks.first?.name, "Perk 8112")
    }
    func testSummonerSpellOrderPlacesFlashOnPreferredKey() {
        XCTAssertEqual(SummonerSpellOrder.ordered([4, 14], flashSlot: .d), [4, 14])
        XCTAssertEqual(SummonerSpellOrder.ordered([4, 14], flashSlot: .f), [14, 4])
        XCTAssertEqual(SummonerSpellOrder.ordered([14, 4], flashSlot: .d), [4, 14])
        XCTAssertEqual(SummonerSpellOrder.ordered([14, 4], flashSlot: .f), [14, 4])
        XCTAssertEqual(SummonerSpellOrder.ordered([7, 14], flashSlot: .f), [7, 14])
    }
    func testRecommendedLoadoutURLsSeparateRankedAndARAM() throws {
        let ranked = try XCTUnwrap(RecommendedLoadoutSource.urls(champion: "ahri", position: "mid", mode: .ranked))
        XCTAssertEqual(ranked.runes.absoluteString, "https://op.gg/lol/champions/ahri/runes/mid")
        XCTAssertEqual(ranked.build.absoluteString, "https://op.gg/lol/champions/ahri/build/mid")

        let aram = try XCTUnwrap(RecommendedLoadoutSource.urls(champion: "ahri", position: "mid", mode: .aram))
        XCTAssertEqual(aram.runes.absoluteString, "https://op.gg/lol/modes/aram/ahri/runes")
        XCTAssertEqual(aram.build.absoluteString, "https://op.gg/lol/modes/aram/ahri/build")

        XCTAssertNil(RecommendedLoadoutSource.urls(champion: "../ahri", position: "mid", mode: .aram))
    }
    func testArenaAugmentsReceiveSampleAdjustedTiersWithinRarity() throws {
        func augment(_ id: Int, _ name: String, _ rarity: Int, _ winRate: Double, _ games: String) -> [String: Any] {
            ["id": id, "name": name, "rareity": rarity, "win_rate": winRate,
             "pick_rate": 10.0, "play": games]
        }
        let gold = (0..<10).map { augment($0, "Gold \($0)", 4, 60 - Double($0), "1,000") }
        let silver = (10..<20).map { augment($0, "Silver \($0)", 1, 55 - Double($0 - 10), "500") }
        let html = try page(["props": ["query": ["patch": "16.20"],
                                        "augments": ["4": gold, "1": silver]]])
        let result = try GuideParser.parse(html)
        XCTAssertEqual(result.augments.count, 20)
        XCTAssertEqual(result.augments.first { $0.id == 0 }?.tierLabel, "S")
        XCTAssertEqual(result.augments.first { $0.id == 9 }?.tierLabel, "T4")
        XCTAssertEqual(result.augments.first { $0.id == 10 }?.rarity, 1)
        XCTAssertEqual(result.augments.first { $0.id == 0 }?.winRate, 60)
        XCTAssertEqual(result.augments.first { $0.id == 0 }?.games, 1_000)
    }
    func testBuildRecommendationPrefersOwnedPrefixThenSampleSize() throws {
        func build(_ ids: [Int], games: Int) -> ItemBuild {
            ItemBuild(items: ids.map { BuildItem(id: $0, name: "Item \($0)", imageURL: "https://cdn.example/\($0).png") },
                      winRate: 55, pickRate: 10, games: games)
        }
        let popular = build([1, 2, 3], games: 1_000)
        let matching = build([4, 5, 6], games: 500)
        XCTAssertEqual(ItemBuildRecommendation.choose(from: [matching, popular], ownedItemIDs: []), popular)
        let selected = try XCTUnwrap(ItemBuildRecommendation.choose(from: [popular, matching], ownedItemIDs: [4]))
        XCTAssertEqual(selected, matching)
        XCTAssertEqual(ItemBuildRecommendation.nextItem(in: selected, ownedItemIDs: [4])?.id, 5)
    }
    func testFetchedPublicPagesWhenProvided() throws {
        guard let path = ProcessInfo.processInfo.environment["RIFT_GUIDE_FIXTURE_DIR"] else { throw XCTSkip("Set RIFT_GUIDE_FIXTURE_DIR for live-page smoke test") }
        let augments = try GuideParser.parse(String(contentsOfFile: path + "/rift-opgg-zh-augments.html"))
        let skills = try GuideParser.parse(String(contentsOfFile: path + "/rift-opgg-skills.html"))
        XCTAssertGreaterThan(augments.augments.count, 50)
        XCTAssertGreaterThan(augments.champions.count, 100)
        XCTAssertEqual(augments.patch, skills.patch)
        XCTAssertNotNil(skills.skills)
    }
    func testFetchedMayhemStatsWhenProvided() throws {
        guard let path = ProcessInfo.processInfo.environment["RIFT_MAYHEM_STATS_FIXTURE"] else {
            throw XCTSkip("Set RIFT_MAYHEM_STATS_FIXTURE for live Mayhem stats smoke test")
        }
        let page = try MayhemStatsParser.parse(String(contentsOfFile: path))
        XCTAssertGreaterThan(page.stats.count, 150)
        XCTAssertNotNil(page.patch)
        XCTAssertTrue(page.stats.values.allSatisfy {
            (0...100).contains($0.winRate) && (0...100).contains($0.pickRate) && $0.games > 0
        })
    }
    func testFetchedModeItemPagesWhenProvided() throws {
        guard let path = ProcessInfo.processInfo.environment["RIFT_MODE_FIXTURE_DIR"] else {
            throw XCTSkip("Set RIFT_MODE_FIXTURE_DIR for multi-mode live-page smoke test")
        }
        for mode in ["aram-mayhem", "aram", "arena", "ranked"] {
            let html = try String(contentsOfFile: path + "/\(mode)-items.html")
            let page: GuidePage
            do { page = try GuideParser.parse(html) }
            catch { XCTFail("\(mode): \(error)"); continue }
            XCTAssertFalse(page.itemBuilds.isEmpty, mode)
            XCTAssertNotNil(page.patch, mode)
        }
        let arenaAugments = try GuideParser.parse(String(contentsOfFile: path + "/arena-augments.html"))
        XCTAssertGreaterThan(arenaAugments.augments.count, 20)
        XCTAssertTrue(arenaAugments.augments.allSatisfy { $0.winRate != nil && $0.games != nil })
    }
    func testFetchedLoadoutPagesWhenProvided() throws {
        guard let path = ProcessInfo.processInfo.environment["RIFT_LOADOUT_FIXTURE_DIR"] else {
            throw XCTSkip("Set RIFT_LOADOUT_FIXTURE_DIR for live loadout smoke test")
        }
        let runes = try GuideParser.parse(String(contentsOfFile: path + "/runes.html"))
        let build = try GuideParser.parse(String(contentsOfFile: path + "/build.html"))
        XCTAssertEqual(runes.loadout?.selectedPerkIDs.count, 9)
        XCTAssertEqual(runes.loadout?.perks.count, 9)
        XCTAssertTrue(runes.loadout?.perks.allSatisfy { !$0.name.isEmpty && $0.imageURL.hasPrefix("https://") } == true)
        XCTAssertEqual(build.loadout?.spellIDs.count, 2)
        XCTAssertNotEqual(build.loadout?.spellIDs.first, build.loadout?.spellIDs.last)
    }
}
