import XCTest
@testable import RiftCore

final class ObjectiveTimerTests: XCTestCase {
    func testInitialRiftSpawnTimers() {
        let timers = ObjectiveTimerEngine.rift(gameTime: 250, events: [])
        XCTAssertEqual(timers.first(where: { $0.kind == .dragon })?.remaining, 50)
        XCTAssertEqual(timers.first(where: { $0.kind == .voidGrubs })?.remaining, 110)
        XCTAssertEqual(timers.first(where: { $0.kind == .riftHerald })?.remaining, 590)
        XCTAssertEqual(timers.first(where: { $0.kind == .baron })?.remaining, 950)
    }

    func testDragonAndBaronRespawnsUseKillEvents() {
        let events = [
            LiveGameEvent(id: 1, name: "DragonKill", time: 500, dragonType: "Fire"),
            LiveGameEvent(id: 2, name: "BaronKill", time: 1300)
        ]
        let timers = ObjectiveTimerEngine.rift(gameTime: 600, events: events)
        XCTAssertEqual(timers.first(where: { $0.kind == .dragon })?.remaining, 200)
        XCTAssertEqual(timers.first(where: { $0.kind == .baron })?.remaining, 1060)
    }

    func testSoulAndElderUseSixMinuteRespawn() {
        let events = (0..<4).map {
            LiveGameEvent(id: $0, name: "DragonKill", time: Double(300 + $0 * 320), dragonType: "Fire", killerName: "Blue Player")
        }
        let timers = ObjectiveTimerEngine.rift(gameTime: 1300, events: events,
                                                playerTeams: [ObjectiveTimerEngine.normalize("Blue Player"): "ORDER"])
        XCTAssertEqual(timers.first(where: { $0.kind == .elderDragon })?.remaining, 320)
        XCTAssertNil(timers.first(where: { $0.kind == .dragon }))
    }

    func testAramRelicsIncludeInitialAndManualTimers() {
        XCTAssertEqual(ObjectiveTimerEngine.aram(gameTime: 45, relicDeadlines: [:]),
                       [ObjectiveCountdown(kind: .healthRelic, remaining: 60, slot: 2),
                        ObjectiveCountdown(kind: .healthRelic, remaining: 60, slot: 3),
                        ObjectiveCountdown(kind: .healthRelic, remaining: 105, slot: 1),
                        ObjectiveCountdown(kind: .healthRelic, remaining: 105, slot: 4)])
        XCTAssertEqual(ObjectiveTimerEngine.aram(gameTime: 120, relicDeadlines: [:]),
                       [ObjectiveCountdown(kind: .healthRelic, remaining: 30, slot: 1),
                        ObjectiveCountdown(kind: .healthRelic, remaining: 30, slot: 4)])
        XCTAssertEqual(ObjectiveTimerEngine.aram(gameTime: 200, relicDeadlines: [3: 290]),
                       [ObjectiveCountdown(kind: .healthRelic, remaining: 90, slot: 3)])
    }

    func testEventPayloadUsesRiotCapitalizedKeys() throws {
        let data = Data(#"{"Events":[{"EventID":7,"EventName":"DragonKill","EventTime":321.5,"DragonType":"Earth","KillerName":"A#EUW"}]}"#.utf8)
        let decoded = try JSONDecoder().decode(LiveEventData.self, from: data)
        XCTAssertEqual(decoded.events.first?.id, 7)
        XCTAssertEqual(decoded.events.first?.dragonType, "Earth")
    }

    func testHealthRelicRecognitionRequiresVisibleScoreboard() {
        let clock = RecognizedLine(text: "0:42", x: 0.5, y: 0.90, width: 0.05, height: 0.02, confidence: 0.9)
        XCTAssertEqual(HealthRelicRecognition.scan(lines: [clock]),
                       HealthRelicScan(scoreboardVisible: false, readings: []))
    }

    func testHealthRelicRecognitionReadsTimerRow() {
        var lines = (0..<10).map { index in
            RecognizedLine(text: "Player \(index)", x: index.isMultiple(of: 2) ? 0.3 : 0.7,
                           y: 0.20 + Double(index) * 0.055, width: 0.15, height: 0.02, confidence: 0.8)
        }
        lines.append(RecognizedLine(text: "0:41 1:20 0:09 1:02", x: 0.5, y: 0.98,
                                    width: 0.20, height: 0.02, confidence: 0.9))
        let scan = HealthRelicRecognition.scan(lines: lines)
        XCTAssertTrue(scan.scoreboardVisible)
        XCTAssertEqual(scan.readings.map(\.remaining), [41, 80, 9, 62])
    }

    func testHealthRelicRecognitionIgnoresCentralMatchTimers() {
        var lines = (0..<10).map { index in
            RecognizedLine(text: "Player \(index)", x: index.isMultiple(of: 2) ? 0.3 : 0.7,
                           y: 0.20 + Double(index) * 0.055, width: 0.15, height: 0.02, confidence: 0.8)
        }
        lines.append(RecognizedLine(text: "0:41 1:20", x: 0.5, y: 0.82,
                                    width: 0.10, height: 0.02, confidence: 0.9))
        XCTAssertEqual(HealthRelicRecognition.scan(lines: lines).readings, [])
    }
}
