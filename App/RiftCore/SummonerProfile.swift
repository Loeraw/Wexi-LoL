import Foundation

public enum RecentMatchResult: String, Equatable, Sendable {
    case win = "WIN"
    case loss = "LOSE"
    case other = "OTHER"
}

public struct SummonerProfile: Equatable, Sendable {
    public let riotID: String
    public let tier: String
    public let leaguePoints: Int?
    public let wins: Int
    public let losses: Int
    public let winRate: Double?
    public let recent: [RecentMatchResult]

    public init(riotID: String, tier: String, leaguePoints: Int?, wins: Int, losses: Int,
                winRate: Double?, recent: [RecentMatchResult]) {
        self.riotID = riotID; self.tier = tier; self.leaguePoints = leaguePoints
        self.wins = wins; self.losses = losses; self.winRate = winRate; self.recent = recent
    }
}

public enum SummonerProfileParseError: Error { case missingStructuredData }

/// Reads OP.GG's public JSON-LD profile summary. JSON-LD is preferred over
/// scraping CSS classes because it is intended for machine-readable consumers.
public enum SummonerProfileParser {
    public static func parse(_ html: String) throws -> SummonerProfile {
        let pattern = #"<script[^>]*type=["']application/ld\+json["'][^>]*>(.*?)</script>"#
        let regex = try NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive])
        let ns = html as NSString
        var graph: [[String: Any]] = []
        for match in regex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let raw = ns.substring(with: match.range(at: 1))
            guard let root = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any],
                  let entries = root["@graph"] as? [[String: Any]] else { continue }
            graph += entries
        }
        guard !graph.isEmpty else { throw SummonerProfileParseError.missingStructuredData }
        let person = graph.first { ($0["@type"] as? String) == "Person" }
        let riotID = person?["name"] as? String ?? ""
        let description = graph.first { ($0["@type"] as? String) == "ProfilePage" }?["description"] as? String ?? ""
        let rank = parseRank(description)

        let recentList = graph.first {
            ($0["@type"] as? String) == "ItemList" && (($0["@id"] as? String)?.hasSuffix("#recent-games") == true)
        }
        let rows = (recentList?["itemListElement"] as? [[String: Any]] ?? []).sorted {
            ($0["position"] as? NSNumber)?.intValue ?? 0 < ($1["position"] as? NSNumber)?.intValue ?? 0
        }
        let recent = rows.compactMap { row -> RecentMatchResult? in
            guard let item = row["item"] as? [String: Any],
                  let properties = item["additionalProperty"] as? [[String: Any]],
                  let value = properties.first(where: { ($0["name"] as? String) == "result" })?["value"] as? String else { return nil }
            if value == "WIN" { return .win }
            if value == "LOSE" { return .loss }
            return .other
        }
        return SummonerProfile(riotID: riotID, tier: rank.tier, leaguePoints: rank.lp,
                               wins: rank.wins, losses: rank.losses, winRate: rank.winRate,
                               recent: Array(recent.prefix(10)))
    }

    private static func parseRank(_ description: String) -> (tier: String, lp: Int?, wins: Int, losses: Int, winRate: Double?) {
        let pattern = #"current SOLORANKED rank is (.+?) with ([\d,]+) wins, ([\d,]+) losses, and a ([\d.]+)% win rate"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: description, range: NSRange(description.startIndex..., in: description)),
              let rankRange = Range(match.range(at: 1), in: description),
              let winsRange = Range(match.range(at: 2), in: description),
              let lossesRange = Range(match.range(at: 3), in: description),
              let rateRange = Range(match.range(at: 4), in: description) else {
            return ("UNRANKED", nil, 0, 0, nil)
        }
        let rankText = String(description[rankRange])
        let detailPattern = #"^(.+?)(?: Division \d+)? ([\d,]+) LP$"#
        let detail = try? NSRegularExpression(pattern: detailPattern, options: [.caseInsensitive])
        let detailMatch = detail?.firstMatch(in: rankText, range: NSRange(rankText.startIndex..., in: rankText))
        let tier: String
        let lp: Int?
        if let detailMatch,
           let tierRange = Range(detailMatch.range(at: 1), in: rankText),
           let lpRange = Range(detailMatch.range(at: 2), in: rankText) {
            tier = String(rankText[tierRange]).uppercased()
            lp = Int(rankText[lpRange].replacingOccurrences(of: ",", with: ""))
        } else {
            tier = rankText.uppercased(); lp = nil
        }
        return (tier,
                lp,
                Int(description[winsRange].replacingOccurrences(of: ",", with: "")) ?? 0,
                Int(description[lossesRange].replacingOccurrences(of: ",", with: "")) ?? 0,
                Double(description[rateRange]))
    }
}
