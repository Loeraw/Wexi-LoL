import Foundation

public struct ChampionOption: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String

    /// Riot's numeric champion id, used to match League Client champ-select
    /// sessions to OP.GG's stable champion slug without OCR.
    public let numericID: Int?

    public init(id: String, name: String, numericID: Int? = nil) {
        self.id = id
        self.name = name
        self.numericID = numericID
    }
}
public struct AugmentRating: Identifiable, Equatable, Sendable {
    public let id: Int
    public let name: String
    public let key: String
    public let tier: Int
    public let rarity: Int
    public var englishName: String? = nil
    public var alternateNames: [String] = []
    public let winRate: Double?
    public let pickRate: Double?
    public let games: Int?

    public init(id: Int, name: String, key: String, tier: Int, rarity: Int,
                englishName: String? = nil, winRate: Double? = nil,
                pickRate: Double? = nil, games: Int? = nil,
                alternateNames: [String] = []) {
        self.id = id; self.name = name; self.key = key; self.tier = tier; self.rarity = rarity
        self.englishName = englishName; self.winRate = winRate; self.pickRate = pickRate; self.games = games
        self.alternateNames = alternateNames
    }
    public var tierLabel: String { tier == 0 ? "S" : "T\(tier)" }
    public var rarityLabel: String {
        switch rarity { case 1: return "白银"; case 4: return "黄金"; case 8: return "棱彩"; default: return "未知稀有度" }
    }
    public func matches(_ text: String) -> Bool {
        let normalized: (String) -> String = { $0.lowercased().filter { $0.isLetter || $0.isNumber } }
        return text.isEmpty || ([name, key, englishName ?? ""] + alternateNames)
            .contains { normalized($0).contains(normalized(text)) }
    }
}
public struct SkillGuide: Equatable, Sendable {
    public let priority: [String]
    public let order: [String]
    public let samples: Int
}
public struct BuildItem: Identifiable, Equatable, Sendable {
    public let id: Int
    public let name: String
    public let imageURL: String

    public init(id: Int, name: String, imageURL: String) {
        self.id = id; self.name = name; self.imageURL = imageURL
    }
}
public struct ItemBuild: Equatable, Sendable {
    public let items: [BuildItem]
    public let winRate: Double
    public let pickRate: Double
    public let games: Int

    public init(items: [BuildItem], winRate: Double, pickRate: Double, games: Int) {
        self.items = items; self.winRate = winRate; self.pickRate = pickRate; self.games = games
    }
}
public enum ItemBuildRecommendation {
    /// Prefer the most-played route compatible with completed core items. This
    /// avoids presenting a tiny-sample high win rate as the default build.
    public static func choose(from builds: [ItemBuild], ownedItemIDs: [Int]) -> ItemBuild? {
        let owned = Set(ownedItemIDs)
        return builds.max { lhs, rhs in
            let left = score(lhs, owned: owned), right = score(rhs, owned: owned)
            if left.compatible != right.compatible { return !left.compatible && right.compatible }
            if left.matched != right.matched { return left.matched < right.matched }
            return lhs.games < rhs.games
        }
    }

    public static func nextItem(in build: ItemBuild, ownedItemIDs: [Int]) -> BuildItem? {
        let owned = Set(ownedItemIDs)
        return build.items.first { !owned.contains($0.id) }
    }

    private static func score(_ build: ItemBuild, owned: Set<Int>) -> (matched: Int, compatible: Bool) {
        let ids = build.items.map(\.id)
        let matched = ids.prefix { owned.contains($0) }.count
        let routeItemsOwned = ids.filter { owned.contains($0) }
        return (matched, routeItemsOwned.allSatisfy { ids.prefix(matched).contains($0) })
    }
}
public struct GuidePage: Sendable {
    public var champions: [ChampionOption] = []
    public var augments: [AugmentRating] = []
    public var skills: SkillGuide?
    public var itemBuilds: [ItemBuild] = []
    public var loadout: RecommendedLoadout?
    public var patch: String?
}

public struct RecommendedLoadout: Equatable, Sendable {
    public let primaryStyleID: Int
    public let secondaryStyleID: Int
    public let selectedPerkIDs: [Int]
    public let spellIDs: [Int]
    public let games: Int
    public let pickRate: Double?
    public let winRate: Double?
    public let perks: [RecommendedPerk]

    public init(primaryStyleID: Int, secondaryStyleID: Int, selectedPerkIDs: [Int],
                spellIDs: [Int] = [], games: Int = 0, pickRate: Double? = nil,
                winRate: Double? = nil, perks: [RecommendedPerk] = []) {
        self.primaryStyleID = primaryStyleID
        self.secondaryStyleID = secondaryStyleID
        self.selectedPerkIDs = selectedPerkIDs
        self.spellIDs = spellIDs
        self.games = games
        self.pickRate = pickRate
        self.winRate = winRate
        self.perks = perks
    }

    public func withSpellIDs(_ ids: [Int]) -> RecommendedLoadout {
        RecommendedLoadout(primaryStyleID: primaryStyleID, secondaryStyleID: secondaryStyleID,
                           selectedPerkIDs: selectedPerkIDs, spellIDs: ids, games: games,
                           pickRate: pickRate, winRate: winRate, perks: perks)
    }

    public func withPerks(_ values: [RecommendedPerk]) -> RecommendedLoadout {
        RecommendedLoadout(primaryStyleID: primaryStyleID, secondaryStyleID: secondaryStyleID,
                           selectedPerkIDs: selectedPerkIDs, spellIDs: spellIDs, games: games,
                           pickRate: pickRate, winRate: winRate, perks: values)
    }
}

public struct RecommendedPerk: Identifiable, Equatable, Sendable {
    public let id: Int
    public let name: String
    public let imageURL: String

    public init(id: Int, name: String, imageURL: String) {
        self.id = id
        self.name = name
        self.imageURL = imageURL
    }
}

public enum FlashSlot: String, CaseIterable, Identifiable, Sendable {
    case d
    case f

    public var id: String { rawValue }
    public var title: String { rawValue.uppercased() }
}

public enum SummonerSpellOrder {
    public static let flashID = 4

    /// LCU's first spell slot is D and its second spell slot is F.
    public static func ordered(_ spellIDs: [Int], flashSlot: FlashSlot) -> [Int] {
        guard spellIDs.count == 2, let flashIndex = spellIDs.firstIndex(of: flashID) else {
            return spellIDs
        }
        let desiredIndex = flashSlot == .d ? 0 : 1
        guard flashIndex != desiredIndex else { return spellIDs }
        return [spellIDs[1], spellIDs[0]]
    }
}

public enum LoadoutGameMode: String, Sendable {
    case ranked
    case aram
}

public enum RecommendedLoadoutSource {
    public static func urls(champion: String, position: String,
                            mode: LoadoutGameMode) -> (runes: URL, build: URL)? {
        guard champion.range(of: #"^[a-z0-9]+$"#, options: .regularExpression) != nil else {
            return nil
        }
        let base: String
        let suffix: String
        switch mode {
        case .ranked:
            guard position.range(of: #"^[a-z]+$"#, options: .regularExpression) != nil else { return nil }
            base = "https://op.gg/lol/champions/\(champion)"
            suffix = "/\(position)"
        case .aram:
            base = "https://op.gg/lol/modes/aram/\(champion)"
            suffix = ""
        }
        guard let runes = URL(string: "\(base)/runes\(suffix)"),
              let build = URL(string: "\(base)/build\(suffix)") else { return nil }
        return (runes, build)
    }
}

public struct MayhemAugmentStats: Equatable, Sendable {
    public let id: Int
    public let winRate: Double
    public let pickRate: Double
    public let games: Int

    public init(id: Int, winRate: Double, pickRate: Double, games: Int) {
        self.id = id
        self.winRate = winRate
        self.pickRate = pickRate
        self.games = games
    }
}

public struct MayhemAugmentStatsPage: Equatable, Sendable {
    public let patch: String?
    public let stats: [Int: MayhemAugmentStats]

    public init(patch: String?, stats: [Int: MayhemAugmentStats]) {
        self.patch = patch
        self.stats = stats
    }
}

public enum MayhemStatsParser {
    /// Reads the JSON already embedded in HexMayhem's public augment page.
    /// IDs are Riot augment IDs, so localized names never need fuzzy matching.
    public static func parse(_ html: String) throws -> MayhemAugmentStatsPage {
        let pattern = #"<script[^>]*>\s*self\.__next_f\.push\((.*?)\)\s*;?\s*</script>"#
        let regex = try NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
        let ns = html as NSString
        var flight = ""
        for match in regex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let raw = ns.substring(with: match.range(at: 1))
            guard let array = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [Any],
                  array.count > 1, let kind = array[0] as? Int, kind == 1,
                  let value = array[1] as? String else { continue }
            flight += value
        }

        var patch: String?
        var stats: [Int: MayhemAugmentStats] = [:]
        func walk(_ object: Any) {
            if let dict = object as? [String: Any] {
                if let meta = dict["initialMeta"] as? [String: Any],
                   let value = meta["patch"] as? String,
                   value.range(of: #"^\d+\.\d+(\.\d+)?$"#, options: .regularExpression) != nil {
                    patch = value
                }
                if let rows = (dict["initialRows"] as? [[String: Any]])
                    ?? (dict["initialAugments"] as? [[String: Any]]) {
                    for row in rows {
                        guard let id = integer(row["id"]),
                              let winRate = number(row["wr"]), (0...100).contains(winRate),
                              let pickRate = number(row["pr"]), (0...100).contains(pickRate),
                              let games = integer(row["n"]), games > 0 else { continue }
                        stats[id] = MayhemAugmentStats(id: id, winRate: winRate,
                                                      pickRate: pickRate, games: games)
                    }
                }
                for value in dict.values { walk(value) }
            } else if let array = object as? [Any] {
                array.forEach(walk)
            }
        }
        for line in flight.split(separator: "\n") {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let payload = line[line.index(after: colon)...]
            if let object = try? JSONSerialization.jsonObject(with: Data(payload.utf8), options: .fragmentsAllowed) {
                walk(object)
            }
        }
        guard !stats.isEmpty else { throw GuideParseError.pageStructureChanged }
        return MayhemAugmentStatsPage(patch: patch, stats: stats)
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value.replacingOccurrences(of: ",", with: "")) }
        return nil
    }

    private static func integer(_ value: Any?) -> Int? {
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value.replacingOccurrences(of: ",", with: "")) }
        return nil
    }
}
public enum GuideParseError: Error { case pageStructureChanged }

// Read JSON already included in a public OP.GG page; never execute page scripts.
// Fail closed if the site's presentation schema changes.
public enum GuideParser {
    public static func parse(_ html: String) throws -> GuidePage {
        let pattern = #"<script[^>]*>\s*self\.__next_f\.push\((.*?)\)\s*;?\s*</script>"#
        let regex = try NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
        let ns = html as NSString
        var flight = ""
        for match in regex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let raw = ns.substring(with: match.range(at: 1))
            guard let array = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [Any],
                  array.count > 1, let kind = array[0] as? Int, kind == 1,
                  let value = array[1] as? String else { continue }
            flight += value
        }
        var output = GuidePage()
        var loadoutCandidates: [RecommendedLoadout] = []
        var spellCandidates: [Int] = []
        var perkMetadata: [Int: RecommendedPerk] = [:]
        func walk(_ object: Any) {
            if let dict = object as? [String: Any] {
                if let query = dict["query"] as? [String: Any], let patch = query["patch"] as? String,
                   patch.range(of: #"^\d+\.\d+(\.\d+)?$"#, options: .regularExpression) != nil { output.patch = patch }
                if output.patch == nil, let version = dict["version"] as? String,
                   version.range(of: #"^\d+\.\d+(\.\d+)?$"#, options: .regularExpression) != nil { output.patch = version }
                if let champs = dict["champions"] as? [[String: Any]], output.champions.isEmpty {
                    output.champions = champs.compactMap { row in
                        guard let key = row["key"] as? String, let name = row["name"] as? String,
                              let championID = row["champion_id"] as? Int else { return nil }
                        return ChampionOption(id: key, name: name, numericID: championID)
                    }
                }
                if let importData = dict["importClientData"] as? [String: Any],
                   let primary = importData["primaryStyleId"] as? Int,
                   let secondary = importData["subStyleId"] as? Int,
                   let perks = importData["selectedPerkIds"] as? [Int],
                   perks.count == 9,
                   primary > 0, secondary > 0 {
                    loadoutCandidates.append(RecommendedLoadout(
                        primaryStyleID: primary, secondaryStyleID: secondary,
                        selectedPerkIDs: perks, games: count(dict["play"]) ?? 0,
                        pickRate: number(dict["pick_rate"]), winRate: number(dict["win_rate"])
                    ))
                }
                if dict["metaType"] as? String == "spell", let spellID = dict["metaId"] as? Int,
                   spellID > 0, !spellCandidates.contains(spellID) {
                    spellCandidates.append(spellID)
                }
                if let id = dict["id"] as? Int, let name = dict["name"] as? String,
                   let imageURL = dict["image_url"] as? String,
                   imageURL.hasPrefix("https://"),
                   imageURL.contains("/perk/") || imageURL.contains("/perkShard/") {
                    perkMetadata[id] = RecommendedPerk(id: id, name: name, imageURL: imageURL)
                }
                if let rows = dict["data"] as? [[String: Any]], output.augments.isEmpty {
                    output.augments = rows.compactMap { row in
                        guard let id = row["id"] as? Int, let name = row["name"] as? String,
                              let key = row["key"] as? String, let tier = row["tier"] as? Int,
                              (0...5).contains(tier), let rarity = row["rarity"] as? Int else { return nil }
                        let winRate = number(row["win_rate"]).flatMap { (0...100).contains($0) ? $0 : nil }
                        // Current Mayhem pages call champion-specific pick rate
                        // `popular`; older pages used `pick_rate`.
                        let pickRate = number(row["pick_rate"] ?? row["popular"])
                            .flatMap { (0...100).contains($0) ? $0 : nil }
                        let games = count(row["play"])
                        return AugmentRating(id: id, name: name, key: key, tier: tier, rarity: rarity,
                                             winRate: winRate, pickRate: pickRate, games: games)
                    }
                }
                if let groups = (dict["augments"] as? [String: Any]) ?? (dict["data"] as? [String: Any]),
                   output.augments.isEmpty {
                    let candidates = groups.flatMap { rarityKey, value -> [ArenaAugmentCandidate] in
                        guard let rows = value as? [[String: Any]] else { return [] }
                        let groupRarity = Int(rarityKey)
                        return rows.compactMap { row in
                            guard let id = row["id"] as? Int, let name = row["name"] as? String,
                                  let rarity = row["rareity"] as? Int ?? groupRarity,
                                  let winRate = number(row["win_rate"]), (0...100).contains(winRate),
                                  let pickRate = number(row["pick_rate"]), (0...100).contains(pickRate),
                                  let games = count(row["play"]), games > 0 else { return nil }
                            return ArenaAugmentCandidate(id: id, name: name, rarity: rarity,
                                                         winRate: winRate, pickRate: pickRate, games: games)
                        }
                    }
                    if !candidates.isEmpty { output.augments = rateArenaAugments(candidates) }
                }
                if let rows = dict["skill_masteries"] as? [[String: Any]], output.skills == nil,
                   let best = rows.max(by: { ($0["play"] as? Int ?? 0) < ($1["play"] as? Int ?? 0) }),
                   let priority = best["ids"] as? [String],
                   let builds = best["builds"] as? [[String: Any]],
                   let build = builds.max(by: { ($0["play"] as? Int ?? 0) < ($1["play"] as? Int ?? 0) }),
                   let order = build["order"] as? [String], !order.isEmpty,
                   order.allSatisfy({ ["Q", "W", "E", "R"].contains($0) }),
                   priority.allSatisfy({ ["Q", "W", "E", "R"].contains($0) }) {
                    output.skills = SkillGuide(priority: priority, order: order, samples: build["play"] as? Int ?? 0)
                }
                if let rows = dict["data"] as? [[String: Any]] {
                    let builds = rows.compactMap(parseItemBuild)
                    if !builds.isEmpty { output.itemBuilds = builds.sorted { $0.games > $1.games } }
                }
                for value in dict.values { walk(value) }
            } else if let array = object as? [Any] { array.forEach(walk) }
        }
        for line in flight.split(separator: "\n") {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let payload = line[line.index(after: colon)...]
            if let object = try? JSONSerialization.jsonObject(with: Data(payload.utf8), options: .fragmentsAllowed) { walk(object) }
        }
        output.loadout = loadoutCandidates.max {
            if $0.games != $1.games { return $0.games < $1.games }
            return ($0.pickRate ?? 0) < ($1.pickRate ?? 0)
        }
        if let loadout = output.loadout {
            let perks = loadout.selectedPerkIDs.compactMap { perkMetadata[$0] }
            output.loadout = loadout.withPerks(perks)
        }
        if let loadout = output.loadout, spellCandidates.count >= 2 {
            output.loadout = loadout.withSpellIDs(Array(spellCandidates.prefix(2)))
        }
        guard !output.augments.isEmpty || output.skills != nil || !output.itemBuilds.isEmpty || output.loadout != nil else {
            throw GuideParseError.pageStructureChanged
        }
        return output
    }

    private static func parseItemBuild(_ row: [String: Any]) -> ItemBuild? {
        guard let ids = row["ids"] as? [Int], ids.count == 3,
              let metadata = row["metaBuildItems"] as? [[String: Any]], metadata.count == ids.count,
              let winRate = number(row["win_rate"]), (0...100).contains(winRate),
              let pickRate = number(row["pick_rate"]), (0...100).contains(pickRate),
              let games = count(row["play"]), games > 0 else { return nil }
        let byID = Dictionary(metadata.compactMap { item -> (Int, BuildItem)? in
            guard let id = item["id"] as? Int, let name = item["name"] as? String,
                  let imageURL = item["image_url"] as? String, URL(string: imageURL)?.scheme == "https" else { return nil }
            return (id, BuildItem(id: id, name: name, imageURL: imageURL))
        }, uniquingKeysWith: { first, _ in first })
        let items = ids.compactMap { byID[$0] }
        guard items.count == ids.count else { return nil }
        return ItemBuild(items: items, winRate: winRate, pickRate: pickRate, games: games)
    }

    private struct ArenaAugmentCandidate {
        let id: Int
        let name: String
        let rarity: Int
        let winRate: Double
        let pickRate: Double
        let games: Int
    }

    /// OP.GG exposes Arena augment win rate, pick rate and sample size, but no
    /// S/T tier. Rank augments only against others of the same rarity and
    /// shrink small samples toward that rarity's mean before assigning tiers.
    private static func rateArenaAugments(_ candidates: [ArenaAugmentCandidate]) -> [AugmentRating] {
        Dictionary(grouping: candidates, by: \.rarity).values.flatMap { group in
            let totalGames = group.reduce(0) { $0 + $1.games }
            let mean = totalGames > 0
                ? group.reduce(0.0) { $0 + $1.winRate * Double($1.games) } / Double(totalGames)
                : 50
            let ranked = group.sorted {
                adjustedArenaRate($0, mean: mean) > adjustedArenaRate($1, mean: mean)
            }
            return ranked.enumerated().map { index, item in
                let percentile = Double(index) / Double(max(1, ranked.count))
                let tier: Int
                switch percentile {
                case ..<0.10: tier = 0
                case ..<0.30: tier = 1
                case ..<0.55: tier = 2
                case ..<0.80: tier = 3
                default: tier = 4
                }
                return AugmentRating(id: item.id, name: item.name, key: "ARENA_\(item.id)",
                                     tier: tier, rarity: item.rarity, winRate: item.winRate,
                                     pickRate: item.pickRate, games: item.games)
            }
        }
    }

    private static func adjustedArenaRate(_ item: ArenaAugmentCandidate, mean: Double) -> Double {
        let priorGames = 500.0
        return (item.winRate * Double(item.games) + mean * priorGames) / (Double(item.games) + priorGames)
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string.replacingOccurrences(of: ",", with: "")) }
        return nil
    }

    private static func count(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string.replacingOccurrences(of: ",", with: "")) }
        return nil
    }
}
