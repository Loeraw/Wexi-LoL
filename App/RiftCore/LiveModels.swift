import Foundation

public struct ActivePlayer: Decodable, Sendable {
    public let riotId: String?
    public let summonerName: String?
    public let level: Int
    public let currentGold: Double
    public let fullRunes: Runes?
    public var abilities: [String: Ability]? = nil
    public struct Ability: Decodable, Sendable { public let abilityLevel: Int? }
    public var skillRanks: [String: Int] {
        (abilities ?? [:]).compactMapValues { $0.abilityLevel }
    }
    public struct Runes: Decodable, Sendable {
        public let keystone: Rune?
        public struct Rune: Decodable, Sendable { public let displayName: String }
    }
    public var identity: String? { riotId ?? summonerName }
}

public struct Scores: Decodable, Sendable {
    public let kills: Int
    public let deaths: Int
    public let assists: Int
    public let creepScore: Int
    public let wardScore: Double
}

public struct GameStats: Decodable, Sendable {
    public let gameTime: Double
    public let gameMode: String
}

public struct Snapshot: Sendable {
    public let player: ActivePlayer
    public let scores: Scores
    public let game: GameStats
    public init(player: ActivePlayer, scores: Scores, game: GameStats) {
        self.player = player; self.scores = scores; self.game = game
    }
    public var timeLabel: String {
        guard game.gameTime.isFinite else { return "--:--" }
        let seconds = Int(max(0, min(game.gameTime, 604800)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
    public var csPerMinute: String {
        guard game.gameTime.isFinite, game.gameTime >= 60 else { return "—" }
        return String(format: "%.1f", Double(scores.creepScore) / (game.gameTime / 60))
    }
    public static let demo = Snapshot(
        player: ActivePlayer(riotId: "Demo Player#EUW", summonerName: nil, level: 11,
                             currentGold: 1250, fullRunes: nil),
        scores: Scores(kills: 4, deaths: 2, assists: 6, creepScore: 112, wardScore: 18),
        game: GameStats(gameTime: 842, gameMode: "CLASSIC")
    )
}

public enum LiveEndpoint {
    public static func scoresURL(for player: ActivePlayer) -> URL? {
        guard let name = player.identity, !name.isEmpty else { return nil }
        var parts = URLComponents(string: "https://127.0.0.1:2999/liveclientdata/playerscores")!
        parts.queryItems = [URLQueryItem(name: player.riotId == nil ? "summonerName" : "riotId", value: name)]
        return parts.url
    }
}
