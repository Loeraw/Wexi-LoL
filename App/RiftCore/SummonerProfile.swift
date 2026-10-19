import Foundation

public enum OPGGRegion: String, CaseIterable, Codable, Sendable {
    case na, me, euw, eune, oce, kr, jp, br, las, lan, ru, tr, sea, tw, vn

    public var displayName: String { rawValue.uppercased() }

    public static func from(platformID: String) -> OPGGRegion? {
        switch platformID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "NA", "NA1": return .na
        case "ME", "ME1": return .me
        case "EUW", "EUW1": return .euw
        case "EUNE", "EUN1": return .eune
        case "OCE", "OC1": return .oce
        case "KR": return .kr
        case "JP", "JP1": return .jp
        case "BR", "BR1": return .br
        case "LAS", "LA2": return .las
        case "LAN", "LA1": return .lan
        case "RU": return .ru
        case "TR", "TR1": return .tr
        case "SEA", "SG2", "PH2", "TH2": return .sea
        case "TW", "TW2": return .tw
        case "VN", "VN2": return .vn
        default: return nil
        }
    }

    public static func inferred(fromRiotID riotID: String) -> OPGGRegion? {
        guard let hash = riotID.lastIndex(of: "#"), hash < riotID.index(before: riotID.endIndex) else { return nil }
        return from(platformID: String(riotID[riotID.index(after: hash)...]))
    }
}

public enum SummonerProfileURL {
    public static func make(riotID: String, region: OPGGRegion) -> URL? {
        guard let hash = riotID.lastIndex(of: "#"), hash != riotID.startIndex,
              hash < riotID.index(before: riotID.endIndex) else { return nil }
        let gameName = riotID[..<hash]
        let tag = riotID[riotID.index(after: hash)...]
        let slug = "\(gameName)-\(tag)"
        return URL(string: "https://op.gg/lol/summoners")?
            .appendingPathComponent(region.rawValue)
            .appendingPathComponent(slug)
    }
}

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
    /// Time at which OP.GG says this profile snapshot was last refreshed.
    public let updatedAt: Date?

    public init(riotID: String, tier: String, leaguePoints: Int?, wins: Int, losses: Int,
                winRate: Double?, recent: [RecentMatchResult], updatedAt: Date? = nil) {
        self.riotID = riotID; self.tier = tier; self.leaguePoints = leaguePoints
        self.wins = wins; self.losses = losses; self.winRate = winRate; self.recent = recent
        self.updatedAt = updatedAt
    }

    public func isStale(referenceDate: Date = Date(), maxAge: TimeInterval = 36 * 60 * 60) -> Bool {
        guard let updatedAt else { return true }
        return referenceDate.timeIntervalSince(updatedAt) > maxAge
    }
}

public enum RiotIDIdentity {
    /// OP.GG may return the canonical capitalization or Unicode width for a Riot ID.
    /// Keep accents significant because they can identify different accounts.
    public static func matches(_ lhs: String, _ rhs: String) -> Bool {
        guard let lhs = components(lhs), let rhs = components(rhs) else { return false }
        return normalized(lhs.name) == normalized(rhs.name) && normalized(lhs.tag) == normalized(rhs.tag)
    }

    private static func components(_ value: String) -> (name: String, tag: String)? {
        guard let hash = value.lastIndex(of: "#"), hash != value.startIndex,
              hash < value.index(before: value.endIndex) else { return nil }
        return (String(value[..<hash]), String(value[value.index(after: hash)...]))
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
            .folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
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
        guard let riotID = person?["name"] as? String,
              !riotID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            // OP.GG can return an HTTP 200 document for a missing profile or
            // an interstitial. Do not present that document as an unranked
            // player just because it contains unrelated structured data.
            throw SummonerProfileParseError.missingStructuredData
        }
        let profilePage = graph.first { ($0["@type"] as? String) == "ProfilePage" }
        let description = profilePage?["description"] as? String ?? ""
        let rank = parseRank(description)
        let updatedAt = (profilePage?["dateModified"] as? String).flatMap(parseDate)

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
                               recent: Array(recent.prefix(10)), updatedAt: updatedAt)
    }

    private static func parseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
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
