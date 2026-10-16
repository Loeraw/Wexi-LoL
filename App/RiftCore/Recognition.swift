import Foundation

public struct LiveRosterPlayer: Decodable, Sendable {
    public let riotId: String?
    public let summonerName: String?
    public let rawChampionName: String?
    public let championName: String
    public let level: Int
    public let team: String?
    public let items: [LivePlayerItem]?
}

public struct LivePlayerItem: Decodable, Sendable {
    public let itemID: Int
    public let count: Int?
}

public enum ChampionRecognition {
    public static func key(active: ActivePlayer, roster: [LiveRosterPlayer]) -> String? {
        guard let own = ownPlayer(active: active, roster: roster) else { return nil }
        guard let raw = own.rawChampionName,
              raw.hasPrefix("game_character_displayname_") else { return nil }
        let name = String(raw.dropFirst("game_character_displayname_".count)).lowercased()
        guard !name.isEmpty, name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }
        return name == "monkeyking" ? "wukong" : name
    }

    public static func ownedItemIDs(active: ActivePlayer, roster: [LiveRosterPlayer]) -> [Int] {
        guard let items = ownPlayer(active: active, roster: roster)?.items else { return [] }
        return items.flatMap { item in Array(repeating: item.itemID, count: max(1, item.count ?? 1)) }
    }

    private static func ownPlayer(active: ActivePlayer, roster: [LiveRosterPlayer]) -> LiveRosterPlayer? {
        if let riotID = active.riotId, !riotID.isEmpty {
            return roster.first { $0.riotId == riotID }
        } else if let name = active.summonerName, !name.isEmpty {
            return roster.first { $0.summonerName == name }
        }
        return nil
    }
}

/// Coordinates are normalized to the captured game window; Vision's origin is bottom-left.
public struct RecognizedLine: Sendable {
    public let text: String
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    public let confidence: Float
    public init(text: String, x: Double, y: Double, width: Double, height: Double, confidence: Float) {
        self.text = text; self.x = x; self.y = y; self.width = width; self.height = height; self.confidence = confidence
    }
}

public enum AugmentRecognition {
    public static func normalized(_ string: String) -> String {
        string.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased().filter { $0.isLetter || $0.isNumber }
    }
    private static func aliases(_ item: AugmentRating) -> Set<String> {
        Set(([item.name, item.englishName ?? "", item.key.replacingOccurrences(of: "ARAM_", with: "")] + item.alternateNames)
            .map(normalized).filter { $0.count >= 2 })
    }
    public static func match(_ text: String, catalog: [AugmentRating]) -> Int? {
        let needle = normalized(text)
        guard needle.count >= 2 else { return nil }
        let exact = catalog.filter { aliases($0).contains(needle) }
        if exact.count == 1 { return exact[0].id }
        // One OCR typo is tolerated only in longer English names, with a unique best match.
        guard needle.count >= 8, needle.allSatisfy({ $0.isASCII }) else { return nil }
        let near = catalog.filter { item in
            aliases(item).contains { $0.allSatisfy { $0.isASCII } && distance(needle, $0) <= 1 }
        }
        return near.count == 1 ? near[0].id : nil
    }
    public static func choiceScreenVisible(lines: [RecognizedLine]) -> Bool {
        lines.contains { line in
            let text = normalized(line.text)
            let headings = [
                "选择强化", "選擇增幅裝置", "selectanaugment", "chooseanaugment", "chooseyouraugment",
                "증강체선택", "오그먼트를선택", "オーグメントを選択", "optimisationchoisir", "choisissezuneoptimisation",
                "augmentierungauswahlen", "eligeunaumento", "escolhaumaprimoramento", "выберитеусиление",
                "guclendirmesec", "chọnnângcấp"
            ]
            return line.y > 0.25 && headings.contains { text.contains(normalized($0)) }
        }
    }
    public static func hasChoiceEvidence(lines: [RecognizedLine], catalog: [AugmentRating]) -> Bool {
        if choiceScreenVisible(lines: lines) { return true }
        return lines.contains { line in
            line.confidence >= 0.5 && (0.12...0.88).contains(line.x) &&
            (0.18...0.88).contains(line.y) && line.height >= 0.008 &&
            match(line.text, catalog: catalog) != nil
        }
    }
    /// A full, geometrically valid row of exact dictionary matches can be
    /// shown on its first frame. Partial or fuzzy results still need confirmation.
    public static func isExactTriple(_ cards: [RecognizedCard], lines: [RecognizedLine], catalog: [AugmentRating]) -> Bool {
        guard cards.count == 3, Set(cards.map(\.id)).count == 3 else { return false }
        let valid = Self.cards(lines: lines, catalog: catalog)
        guard valid.map(\.id) == cards.map(\.id) else { return false }
        return cards.allSatisfy { card in
            guard let item = catalog.first(where: { $0.id == card.id }) else { return false }
            return lines.contains { line in
                line.confidence >= 0.5 && aliases(item).contains(normalized(line.text)) &&
                abs(line.x - card.anchor.x) < 0.01 &&
                abs(line.y + line.height / 2 + 0.025 - card.anchor.y) < 0.01
            }
        }
    }
    private static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        guard abs(a.count - b.count) <= 1 else { return 2 }
        var previous = Array(0...b.count)
        for i in a.indices {
            var current = [i + 1] + Array(repeating: 0, count: b.count)
            for j in b.indices {
                current[j + 1] = min(previous[j + 1] + 1, current[j] + 1, previous[j] + (a[i] == b[j] ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count]
    }
    /// Accept only three distinct, horizontally separated titles at approximately the same height.
    /// This avoids interpreting descriptions, chat, or an already-selected augment as a choice screen.
    public static func cardIDs(lines: [RecognizedLine], catalog: [AugmentRating]) -> [Int] {
        cards(lines: lines, catalog: catalog).map(\.id)
    }
    public static func cards(lines: [RecognizedLine], catalog: [AugmentRating]) -> [RecognizedCard] {
        let candidates: [(RecognizedLine, Int)] = lines.compactMap { line in
            guard line.confidence >= 0.5, (0.12...0.88).contains(line.x),
                  (0.25...0.85).contains(line.y), line.height >= 0.008,
                  let id = match(line.text, catalog: catalog) else { return nil }
            // Vision often reports 0.5 for correctly read short names. Accept these only
            // with an exact dictionary match; fuzzy matches require stronger confidence.
            if line.confidence < 0.65 {
                guard let item = catalog.first(where: { $0.id == id }), aliases(item).contains(normalized(line.text)) else { return nil }
            }
            return (line, id)
        }
        var groups: [[Int]: [RecognizedCard]] = [:]
        for anchor in candidates {
            let row = candidates.filter { abs($0.0.y - anchor.0.y) < 0.045 }.sorted { $0.0.x < $1.0.x }
            var unique: [(RecognizedLine, Int)] = []
            for item in row where !unique.contains(where: { $0.1 == item.1 }) { unique.append(item) }
            guard unique.count == 3,
                  unique[1].0.x - unique[0].0.x > 0.13,
                  unique[2].0.x - unique[1].0.x > 0.13 else { continue }
            groups[unique.map { $0.1 }] = unique.map {
                RecognizedCard(id: $0.1, anchor: HintAnchor(x: $0.0.x, y: min(0.94, $0.0.y + $0.0.height / 2 + 0.025)))
            }
        }
        return groups.count == 1 ? groups.values.first! : []
    }

    /// A missing catalogue entry must not suppress reliable neighbouring cards.
    /// Partial results require exact names plus a choice heading, or two separate
    /// titles on the same central horizontal row. Never use fuzzy partial matches.
    public static func visibleCards(lines: [RecognizedLine], catalog: [AugmentRating]) -> [RecognizedCard] {
        let full = cards(lines: lines, catalog: catalog)
        if !full.isEmpty { return full }
        let heading = choiceScreenVisible(lines: lines)
        let candidates: [(RecognizedLine, Int)] = lines.compactMap { line in
            guard line.confidence >= 0.5, (0.12...0.88).contains(line.x), (0.18...0.88).contains(line.y), line.height >= 0.008,
                  let id = match(line.text, catalog: catalog),
                  let item = catalog.first(where: { $0.id == id }), aliases(item).contains(normalized(line.text)) else { return nil }
            return (line, id)
        }
        var groups: [[Int]: [RecognizedCard]] = [:]
        for anchor in candidates {
            let row = candidates.filter { abs($0.0.y - anchor.0.y) < 0.045 }.sorted { $0.0.x < $1.0.x }
            var unique: [(RecognizedLine, Int)] = []
            for item in row where !unique.contains(where: { $0.1 == item.1 }) { unique.append(item) }
            guard (heading ? 1...3 : 2...3).contains(unique.count) else { continue }
            guard (1..<unique.count).allSatisfy({ unique[$0].0.x - unique[$0 - 1].0.x > 0.12 }) else { continue }
            groups[unique.map { $0.1 }] = unique.map {
                RecognizedCard(id: $0.1, anchor: HintAnchor(x: $0.0.x, y: min(0.94, $0.0.y + $0.0.height / 2 + 0.025)))
            }
        }
        return groups.count == 1 ? groups.values.first! : []
    }
}

public struct StableCards {
    private struct Pending {
        var id: Int
        var count: Int
    }

    private var committed: [RecognizedCard?] = Array(repeating: nil, count: 3)
    private var pending: [Pending?] = Array(repeating: nil, count: 3)
    private var hiddenFrames = 0
    public init() {}

    /// Keeps the three augment columns independent. A missing OCR result never
    /// erases a previously confirmed neighbour; a changed column is committed
    /// after two matching frames, or immediately for an exact three-card row.
    public mutating func observe(_ cards: [RecognizedCard], choiceVisible: Bool,
                                 exactTriple: Bool = false) -> [RecognizedCard] {
        guard choiceVisible else {
            hiddenFrames += 1
            pending = Array(repeating: nil, count: 3)
            if hiddenFrames >= 12 {
                committed = Array(repeating: nil, count: 3)
                hiddenFrames = 12
            }
            return []
        }
        hiddenFrames = 0

        var observed: [Int: RecognizedCard] = [:]
        for card in cards {
            guard let slot = slot(for: card.anchor.x) else { continue }
            if let existing = observed[slot] {
                let centers = [0.26, 0.50, 0.74]
                if abs(card.anchor.x - centers[slot]) < abs(existing.anchor.x - centers[slot]) {
                    observed[slot] = card
                }
            } else {
                observed[slot] = card
            }
        }

        if exactTriple, observed.count == 3,
           Set(observed.values.map(\.id)).count == 3 {
            for slot in 0..<3 { committed[slot] = observed[slot] }
            pending = Array(repeating: nil, count: 3)
            return resolved
        }

        for slot in 0..<3 {
            guard let card = observed[slot] else {
                pending[slot] = nil
                continue
            }
            if committed[slot]?.id == card.id {
                committed[slot] = card
                pending[slot] = nil
                continue
            }
            guard !committed.enumerated().contains(where: { $0.offset != slot && $0.element?.id == card.id }) else {
                pending[slot] = nil
                continue
            }
            if pending[slot]?.id == card.id {
                pending[slot]?.count += 1
            } else {
                pending[slot] = Pending(id: card.id, count: 1)
            }
            if pending[slot]?.count ?? 0 >= 2 {
                committed[slot] = card
                pending[slot] = nil
            }
        }
        return resolved
    }

    /// Convenience API retained for non-UI callers and tests.
    public mutating func observe(_ ids: [Int], exactTriple: Bool = false) -> [Int] {
        guard ids.count <= 3, Set(ids).count == ids.count else {
            return observe([], choiceVisible: false).map(\.id)
        }
        let centers = [0.26, 0.50, 0.74]
        let cards = ids.enumerated().map {
            RecognizedCard(id: $0.element, anchor: HintAnchor(x: centers[$0.offset], y: 0.62))
        }
        return observe(cards, choiceVisible: !ids.isEmpty, exactTriple: exactTriple).map(\.id)
    }

    private var resolved: [RecognizedCard] { committed.compactMap { $0 } }

    private func slot(for x: Double) -> Int? {
        guard (0.12...0.88).contains(x) else { return nil }
        if x < 0.38 { return 0 }
        if x < 0.62 { return 1 }
        return 2
    }
}
