import XCTest
@testable import RiftCore

final class RecognitionTests: XCTestCase {
    private var catalog: [AugmentRating] {
        [AugmentRating(id: 1, name: "更万用的瞄准镜", key: "ARAM_ScopierWeapons", tier: 0, rarity: 4),
         AugmentRating(id: 2, name: "神射法师", key: "ARAM_Marksmage", tier: 1, rarity: 4),
         AugmentRating(id: 3, name: "灵巧", key: "ARAM_Deft", tier: 2, rarity: 1)]
    }
    private func line(_ text: String, _ x: Double, _ y: Double = 0.62, _ confidence: Float = 0.98) -> RecognizedLine {
        RecognizedLine(text: text, x: x, y: y, width: 0.15, height: 0.025, confidence: confidence)
    }
    private func card(_ id: Int, _ x: Double) -> RecognizedCard {
        RecognizedCard(id: id, anchor: HintAnchor(x: x, y: 0.65))
    }
    func testEnglishChineseAndSingleOCRTypo() {
        XCTAssertEqual(AugmentRecognition.match("Scopier Weapons!", catalog: catalog), 1)
        XCTAssertEqual(AugmentRecognition.match("Scopier Weap0ns", catalog: catalog), 1)
        XCTAssertEqual(AugmentRecognition.match("神 射 法 师", catalog: catalog), 2)
        XCTAssertEqual(AugmentRecognition.match("灵巧", catalog: catalog), 3)
        XCTAssertNil(AugmentRecognition.match("Gain range with Scopier Weapons", catalog: catalog))
        XCTAssertNil(AugmentRecognition.match("神射法", catalog: catalog))
    }
    func testLocalizedAlternateNamesMatchTheSameAugment() {
        var localized = catalog[0]
        localized.alternateNames = ["万能スコープ", "만능 조준경", "Lunette polyvalente"]
        let multilingual = [localized] + Array(catalog.dropFirst())
        XCTAssertEqual(AugmentRecognition.match("万能スコープ", catalog: multilingual), 1)
        XCTAssertEqual(AugmentRecognition.match("만능 조준경", catalog: multilingual), 1)
        XCTAssertEqual(AugmentRecognition.match("Lunette polyvalente", catalog: multilingual), 1)
    }
    func testThreeCardsOrderedByScreenPositionNotTier() {
        XCTAssertEqual(AugmentRecognition.cardIDs(lines: [line("Deft", 0.72), line("Marksmage", 0.26), line("Scopier Weapons", 0.49)], catalog: catalog), [2, 1, 3])
    }
    func testOneKnownTitleKeepsChoiceScreenEvidenceDuringReroll() {
        XCTAssertTrue(AugmentRecognition.hasChoiceEvidence(lines: [line("Marksmage", 0.50)], catalog: catalog))
        XCTAssertFalse(AugmentRecognition.hasChoiceEvidence(lines: [line("Unrelated HUD text", 0.50)], catalog: catalog))
    }
    func testPartialLowConfidenceOrVerticalListsAreRejected() {
        XCTAssertEqual(AugmentRecognition.cardIDs(lines: [line("Deft", 0.72), line("Marksmage", 0.26)], catalog: catalog), [])
        XCTAssertEqual(AugmentRecognition.cardIDs(lines: [line("Deft", 0.72, 0.62, 0.4), line("Marksmage", 0.26), line("Scopier Weapons", 0.49)], catalog: catalog), [])
        XCTAssertEqual(AugmentRecognition.cardIDs(lines: [line("Deft", 0.5, 0.5), line("Marksmage", 0.5, 0.6), line("Scopier Weapons", 0.5, 0.7)], catalog: catalog), [])
    }
    func testSlotUpdateRequiresTwoFramesAndKeepsOtherSlots() {
        var stable = StableCards()
        let initial = [card(1, 0.26), card(2, 0.50), card(3, 0.74)]
        XCTAssertEqual(stable.observe(initial, choiceVisible: true).map(\.id), [])
        XCTAssertEqual(stable.observe(initial, choiceVisible: true).map(\.id), [1, 2, 3])
        XCTAssertEqual(stable.observe([card(4, 0.26)], choiceVisible: true).map(\.id), [1, 2, 3])
        XCTAssertEqual(stable.observe([card(4, 0.26)], choiceVisible: true).map(\.id), [4, 2, 3])
        XCTAssertEqual(stable.observe([card(4, 0.26), card(3, 0.74)], choiceVisible: true).map(\.id), [4, 2, 3])
    }
    func testExactTripleIsImmediateButFuzzyOrPartialStillWaits() {
        let exact = [line("Scopier Weapons", 0.26), line("Marksmage", 0.49), line("Deft", 0.72)]
        let cards = AugmentRecognition.visibleCards(lines: exact, catalog: catalog)
        XCTAssertTrue(AugmentRecognition.isExactTriple(cards, lines: exact, catalog: catalog))
        var stable = StableCards()
        XCTAssertEqual(stable.observe(cards.map(\.id), exactTriple: true), [1, 2, 3])
        XCTAssertEqual(stable.observe([]), [])
        XCTAssertEqual(stable.observe([1, 2], exactTriple: true), [1, 2, 3])
        let fuzzy = [line("Scopier Weap0ns", 0.26), exact[1], exact[2]]
        let fuzzyCards = AugmentRecognition.visibleCards(lines: fuzzy, catalog: catalog)
        XCTAssertEqual(fuzzyCards.count, 3)
        XCTAssertFalse(AugmentRecognition.isExactTriple(fuzzyCards, lines: fuzzy, catalog: catalog))
        XCTAssertFalse(AugmentRecognition.isExactTriple(Array(cards.prefix(2)), lines: exact, catalog: catalog))
    }
    func testOwnChampionIdentityAndMonkeyKingAlias() throws {
        let player = try JSONDecoder().decode(ActivePlayer.self, from: Data(#"{"riotId":"Me#EUW","level":5,"currentGold":10}"#.utf8))
        let roster = try JSONDecoder().decode([LiveRosterPlayer].self, from: Data(#"[{"riotId":"Other#EUW","championName":"Kayle","rawChampionName":"game_character_displayname_Kayle","level":5},{"riotId":"Me#EUW","championName":"Wukong","rawChampionName":"game_character_displayname_MonkeyKing","level":5}]"#.utf8))
        XCTAssertEqual(ChampionRecognition.key(active: player, roster: roster), "wukong")
        XCTAssertNil(ChampionRecognition.key(active: player, roster: [roster[0]]))
    }

    func testOwnedItemsComeOnlyFromActivePlayer() throws {
        let active = try JSONDecoder().decode(ActivePlayer.self, from: Data(#"{"riotId":"Me#EUW","level":5,"currentGold":10}"#.utf8))
        let roster = try JSONDecoder().decode([LiveRosterPlayer].self, from: Data(#"[{"riotId":"Other#EUW","championName":"Kayle","level":5,"items":[{"itemID":999,"count":1}]},{"riotId":"Me#EUW","championName":"Kayle","level":5,"items":[{"itemID":3115,"count":1},{"itemID":2003,"count":2}]}]"#.utf8))
        XCTAssertEqual(ChampionRecognition.ownedItemIDs(active: active, roster: roster), [3115, 2003, 2003])
    }

    func testEveryRerollReplacesRatingsOnItsFirstExactFrame() {
        var stable = StableCards()
        XCTAssertEqual(stable.observe([1, 2, 3], exactTriple: true), [1, 2, 3])
        // Reroll only the middle card, then immediately reroll another slot.
        XCTAssertEqual(stable.observe([1, 4, 3], exactTriple: true), [1, 4, 3])
        XCTAssertEqual(stable.observe([5, 4, 3], exactTriple: true), [5, 4, 3])
        // A later full replacement must not reuse the first offer's ratings.
        XCTAssertEqual(stable.observe([6, 7, 8], exactTriple: true), [6, 7, 8])
    }

    func testRerollAnimationKeepsPreviousRatingsAndClosedScreenEventuallyResets() {
        var stable = StableCards()
        let initial = [card(1, 0.26), card(2, 0.50), card(3, 0.74)]
        XCTAssertEqual(stable.observe(initial, choiceVisible: true, exactTriple: true).map(\.id), [1, 2, 3])
        XCTAssertEqual(stable.observe([], choiceVisible: true).map(\.id), [1, 2, 3])
        XCTAssertEqual(stable.observe([card(9, 0.50)], choiceVisible: true).map(\.id), [1, 2, 3])
        XCTAssertEqual(stable.observe([card(9, 0.50)], choiceVisible: true).map(\.id), [1, 9, 3])
        XCTAssertEqual(stable.observe([], choiceVisible: false).map(\.id), [])
        for _ in 0..<11 { _ = stable.observe([], choiceVisible: false) }
        XCTAssertEqual(stable.observe([card(7, 0.50)], choiceVisible: true).map(\.id), [])
        XCTAssertEqual(stable.observe([card(7, 0.50)], choiceVisible: true).map(\.id), [7])
    }
}
