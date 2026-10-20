import Foundation

public struct LiveEventData: Decodable, Sendable {
    public let events: [LiveGameEvent]

    private enum CodingKeys: String, CodingKey { case events = "Events" }

    public init(events: [LiveGameEvent]) { self.events = events }
}

public struct LiveGameEvent: Decodable, Sendable {
    public let id: Int
    public let name: String
    public let time: Double
    public let dragonType: String?
    public let killerName: String?

    private enum CodingKeys: String, CodingKey {
        case id = "EventID"
        case name = "EventName"
        case time = "EventTime"
        case dragonType = "DragonType"
        case killerName = "KillerName"
    }

    public init(id: Int, name: String, time: Double, dragonType: String? = nil, killerName: String? = nil) {
        self.id = id
        self.name = name
        self.time = time
        self.dragonType = dragonType
        self.killerName = killerName
    }
}

public enum ObjectiveKind: String, Sendable {
    case dragon
    case elderDragon
    case voidGrubs
    case riftHerald
    case baron
    case healthRelic
}

public struct ObjectiveCountdown: Equatable, Sendable {
    public let kind: ObjectiveKind
    public let remaining: Int
    public let slot: Int?

    public init(kind: ObjectiveKind, remaining: Int, slot: Int? = nil) {
        self.kind = kind
        self.remaining = remaining
        self.slot = slot
    }
}

public enum ObjectiveTimerEngine {
    /// Timers that can be derived from Riot's Live Client Data events. Grubs and
    /// Herald only have an initial spawn timer because their kills are not
    /// exposed by the documented event feed.
    public static func rift(gameTime: Double, events: [LiveGameEvent], playerTeams: [String: String] = [:]) -> [ObjectiveCountdown] {
        guard gameTime.isFinite, gameTime >= 0 else { return [] }
        var output: [ObjectiveCountdown] = []
        let dragons = events.filter { $0.name == "DragonKill" && $0.time.isFinite }
        if let last = dragons.max(by: { $0.time < $1.time }) {
            let elderWasKilled = last.dragonType?.caseInsensitiveCompare("Elder") == .orderedSame
            let nextIsElder = elderWasKilled || elementalDragonTeamCounts(dragons, teams: playerTeams).values.contains(where: { $0 >= 4 })
            append(kind: nextIsElder ? .elderDragon : .dragon,
                   target: last.time + (nextIsElder ? 360 : 300), now: gameTime, to: &output)
        } else {
            append(kind: .dragon, target: 300, now: gameTime, to: &output)
        }

        if !events.contains(where: { $0.name == "HeraldKill" }) {
            append(kind: .riftHerald, target: 840, now: gameTime, to: &output)
        }
        // Riot documents no Void Grub kill event, so only the known first spawn
        // can be timed without guessing from the player's screen.
        append(kind: .voidGrubs, target: 360, now: gameTime, to: &output)

        if let last = events.filter({ $0.name == "BaronKill" && $0.time.isFinite }).max(by: { $0.time < $1.time }) {
            append(kind: .baron, target: last.time + 360, now: gameTime, to: &output)
        } else {
            append(kind: .baron, target: 1200, now: gameTime, to: &output)
        }
        return output.sorted { $0.remaining < $1.remaining }
    }

    public static func aram(gameTime: Double, relicDeadlines: [Int: Double]) -> [ObjectiveCountdown] {
        guard gameTime.isFinite, gameTime >= 0 else { return [] }
        var output: [ObjectiveCountdown] = []
        // Slots run from the blue base toward the red base. Inner relics
        // (1 and 4) first spawn at 2:30; outer relics (2 and 3) at 1:45.
        let initialSpawnBySlot: [Int: Double] = [1: 150, 2: 105, 3: 105, 4: 150]
        for slot in 1...4 {
            let target: Double?
            if let deadline = relicDeadlines[slot], deadline > gameTime {
                target = deadline
            } else if let initialSpawn = initialSpawnBySlot[slot], initialSpawn > gameTime {
                target = initialSpawn
            } else {
                target = nil
            }
            guard let target else { continue }
            output.append(ObjectiveCountdown(kind: .healthRelic,
                                             remaining: Int(ceil(target - gameTime)),
                                             slot: slot))
        }
        return output.sorted {
            if $0.remaining != $1.remaining { return $0.remaining < $1.remaining }
            return ($0.slot ?? 0) < ($1.slot ?? 0)
        }
    }

    private static func append(kind: ObjectiveKind, target: Double, now: Double, to output: inout [ObjectiveCountdown]) {
        guard target > now else { return }
        output.append(ObjectiveCountdown(kind: kind, remaining: Int(ceil(target - now))))
    }

    private static func elementalDragonTeamCounts(_ events: [LiveGameEvent], teams: [String: String]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for event in events where event.dragonType?.caseInsensitiveCompare("Elder") != .orderedSame {
            guard let killer = event.killerName,
                  let team = teams[normalize(killer)] else { continue }
            counts[team, default: 0] += 1
        }
        return counts
    }

    public static func normalize(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
