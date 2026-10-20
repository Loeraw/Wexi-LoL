import XCTest
@testable import RiftCore

final class ContextualHintsTests: XCTestCase {
    private let order = ["Q", "W", "E", "W", "W", "R", "W", "Q", "W", "Q", "R", "Q", "Q", "E", "E"]
    func testActivePlayerDecodesRealAbilityLevels() throws {
        let json = #"{"level":4,"currentGold":12,"abilities":{"Q":{"abilityLevel":1},"W":{"abilityLevel":1},"E":{"abilityLevel":1},"R":{"abilityLevel":0},"Passive":{"displayName":"Passive"}}}"#
        let player = try JSONDecoder().decode(ActivePlayer.self, from: Data(json.utf8))
        XCTAssertEqual(player.skillRanks, ["Q":1,"W":1,"E":1,"R":0])
        XCTAssertEqual(SkillRecommendation.next(level: player.level, ranks: player.skillRanks, order: order), "W")
    }
    func testHintDisappearsAfterSpendingPoint() {
        XCTAssertEqual(SkillRecommendation.next(level: 4, ranks: ["Q":1,"W":1,"E":1,"R":0], order: order), "W")
        XCTAssertNil(SkillRecommendation.next(level: 4, ranks: ["Q":1,"W":2,"E":1,"R":0], order: order))
    }
    func testSeveralBankedPointsAndManualDeviation() {
        XCTAssertEqual(SkillRecommendation.next(level: 3, ranks: ["Q":0,"W":0,"E":0,"R":0], order: order), "Q")
        XCTAssertEqual(SkillRecommendation.next(level: 3, ranks: ["Q":1,"W":0,"E":0,"R":0], order: order), "W")
        XCTAssertEqual(SkillRecommendation.next(level: 4, ranks: ["Q":2,"W":0,"E":1,"R":0], order: order), "W")
    }
    func testMissingOrInconsistentRanksFailClosed() {
        XCTAssertNil(SkillRecommendation.next(level: 4, ranks: [:], order: order))
        XCTAssertNil(SkillRecommendation.next(level: 4, ranks: ["Q":1,"W":-1,"E":1,"R":0], order: order))
        XCTAssertNil(SkillRecommendation.next(level: 1, ranks: ["Q":1,"W":1,"E":1,"R":0], order: order))
    }
    func testLateLevelsUsePriorityOnlyForStandardChampions() {
        let ranks = ["Q":5,"W":5,"E":3,"R":2]
        XCTAssertNil(SkillRecommendation.next(level: 16, ranks: ranks, order: order))
        XCTAssertEqual(SkillRecommendation.next(level: 16, ranks: ranks, order: order, priority: ["W","Q","E"], standardRanks: true), "R")
        XCTAssertEqual(SkillRecommendation.next(level: 17, ranks: ["Q":5,"W":5,"E":3,"R":3], order: order, priority: ["W","Q","E"], standardRanks: true), "E")
        XCTAssertNil(SkillRecommendation.next(level: 18, ranks: ["Q":5,"W":5,"E":5,"R":3], order: order, priority: ["W","Q","E"], standardRanks: true))
    }
    private func line(_ text: String, x: Double, y: Double) -> RecognizedLine {
        RecognizedLine(text: text, x: x, y: y, width: 0.012, height: 0.012, confidence: 0.99)
    }
    func testSkillAnchorRequiresVisiblePlusAndCompleteKeyRow() {
        let keys = ["Q", "W", "E", "R"].enumerated().map { line($0.element, x: 0.4 + Double($0.offset) * 0.035, y: 0.04) }
        XCTAssertEqual(SkillHUDRecognition.plusAnchors(lines: keys), [:])
        let plus = line("+", x: 0.435, y: 0.12)
        XCTAssertEqual(SkillHUDRecognition.plusAnchors(lines: keys + [plus]), ["W": HintAnchor(x: 0.435, y: 0.12)])
        XCTAssertEqual(SkillHUDRecognition.plusAnchors(lines: Array(keys.dropLast()) + [plus]), [:])
        XCTAssertEqual(SkillHUDRecognition.plusAnchors(lines: keys + [line("+", x: 0.7, y: 0.5)]), [:])
    }
    func testCardRatingsStayAttachedToDetectedTitles() {
        let catalog = [AugmentRating(id: 1, name: "Alpha", key: "Alpha", tier: 0, rarity: 1),
                       AugmentRating(id: 2, name: "Bravo", key: "Bravo", tier: 1, rarity: 1),
                       AugmentRating(id: 3, name: "Charlie", key: "Charlie", tier: 2, rarity: 1)]
        let cards = AugmentRecognition.cards(lines: [line("Charlie", x: 0.74, y: 0.55), line("Alpha", x: 0.26, y: 0.55), line("Bravo", x: 0.5, y: 0.55)], catalog: catalog)
        XCTAssertEqual(cards.map(\.id), [1, 2, 3])
        XCTAssertEqual(cards.map { $0.anchor.x }, [0.26, 0.5, 0.74])
        XCTAssertTrue(cards.allSatisfy { $0.anchor.y > 0.55 })
        XCTAssertTrue(AugmentRecognition.cards(lines: [], catalog: catalog).isEmpty)
    }
    func testGraphicUpgradeButtonsDoNotRequireOCRPlus() {
        let labels = ["Q", "W", "E", "R"].enumerated().map { line($0.element, x: 0.4 + Double($0.offset) * 0.035, y: 0.04) }
        let anchors = SkillHUDRecognition.anchors(lines: labels, imageAspect: 16.0 / 9.0)
        XCTAssertEqual(anchors.count, 4)
        XCTAssertEqual(anchors["W"]?.x ?? 0, 0.435, accuracy: 0.001)
        XCTAssertGreaterThan(anchors["W"]?.y ?? 0, 0.04)
        XCTAssertTrue(SkillHUDRecognition.anchors(lines: labels.map {
            line($0.text, x: $0.x, y: 0.6)
        }, imageAspect: 16.0 / 9.0).isEmpty)
    }
    func testUnknownCardDoesNotSuppressKnownNeighbours() {
        let catalog = [AugmentRating(id: 1, name: "Alpha", key: "Alpha", tier: 0, rarity: 1),
                       AugmentRating(id: 2, name: "Bravo", key: "Bravo", tier: 1, rarity: 1)]
        let row = [line("Alpha", x: 0.26, y: 0.55), line("Bravo", x: 0.5, y: 0.55), line("Unknown", x: 0.74, y: 0.55)]
        XCTAssertEqual(AugmentRecognition.visibleCards(lines: row, catalog: catalog).map(\.id), [1, 2])
        XCTAssertTrue(AugmentRecognition.visibleCards(lines: [row[0]], catalog: catalog).isEmpty)
        var stable = StableCards()
        XCTAssertEqual(stable.observe([1, 2]), [])
        XCTAssertEqual(stable.observe([1, 2]), [1, 2])
        XCTAssertEqual(stable.observe([2]), [1, 2])
        XCTAssertEqual(stable.observe([]), [])
    }

    func testAdaptiveOverlayScaleIsBoundedAcrossResolutions() {
        XCTAssertEqual(AdaptiveOverlayLayout.scale(width: 2560, height: 1440), 1, accuracy: 0.001)
        XCTAssertEqual(AdaptiveOverlayLayout.scale(width: 1920, height: 1080), 0.8, accuracy: 0.001)
        XCTAssertEqual(AdaptiveOverlayLayout.scale(width: 3840, height: 2160), 1.15, accuracy: 0.001)
        XCTAssertEqual(AdaptiveOverlayLayout.scale(width: 0, height: 0), 1)
        XCTAssertEqual(AdaptiveOverlayLayout.scale(width: 2560, height: 1440, preference: 1.2), 1.2, accuracy: 0.001)
        XCTAssertEqual(AdaptiveOverlayLayout.scale(width: 2560, height: 1440, preference: 2), 1.35, accuracy: 0.001)
        XCTAssertEqual(AdaptiveOverlayLayout.scale(width: 0, height: 0, preference: 0.5), 0.75, accuracy: 0.001)
    }

    func testUltrawideLayoutUsesCenteredSixteenByNineContent() {
        XCTAssertEqual(AdaptiveOverlayLayout.contentX(0.5, width: 3440, height: 1440), 0.5, accuracy: 0.001)
        XCTAssertGreaterThan(AdaptiveOverlayLayout.contentX(0.1, width: 3440, height: 1440), 0.1)
        XCTAssertLessThan(AdaptiveOverlayLayout.contentX(0.9, width: 3440, height: 1440), 0.9)
        XCTAssertEqual(AdaptiveOverlayLayout.contentX(0.2, width: 1920, height: 1200), 0.2, accuracy: 0.001)
    }

    func testPlayerAnchorsMatchRiotIDNamesAndKeepLinesUnique() {
        let lines = [
            line("Player One", x: 0.24, y: 0.67),
            line("[TAG] 第二位", x: 0.76, y: 0.53),
            line("Player One More", x: 0.75, y: 0.46)
        ]
        let anchors = PlayerUIAnchorRecognition.anchors(
            lines: lines,
            riotIDs: ["Player One#EUW", "第二位#1234", "Player One More#NA1"]
        )
        XCTAssertEqual(anchors["Player One#EUW"], HintAnchor(x: 0.24, y: 0.67))
        XCTAssertEqual(anchors["第二位#1234"], HintAnchor(x: 0.76, y: 0.53))
        XCTAssertEqual(anchors["Player One More#NA1"], HintAnchor(x: 0.75, y: 0.46))
    }
}
