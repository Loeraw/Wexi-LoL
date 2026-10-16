import Foundation

public struct HintAnchor: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

public enum SkillRecommendation {
    public static func next(level: Int, ranks: [String: Int], order: [String], priority: [String] = [], standardRanks: Bool = false) -> String? {
        let keys = ["Q", "W", "E", "R"]
        guard (1...30).contains(level), keys.allSatisfy({ ranks[$0].map { (0...6).contains($0) } == true }) else { return nil }
        let spent = keys.reduce(0) { $0 + ranks[$1]! }
        guard spent < level else { return nil }
        // Use only ranks actually present in the source's sequence. This also
        // respects special champion progressions without assuming R at level 6.
        let sequence = Array(order.prefix(level))
        guard sequence.allSatisfy({ keys.contains($0) }) else { return nil }
        var desired: [String: Int] = [:]
        for key in sequence {
            desired[key, default: 0] += 1
            if desired[key]! > ranks[key]! { return key }
        }
        // Some sources publish only levels 1–15. For standard champions only,
        // finish ranks using the published priority and the game's rank limits.
        if standardRanks, level > order.count, level <= 18,
           Set(priority) == Set(["Q", "W", "E"]), priority.count == 3,
           ranks["R"]! <= 3, ["Q", "W", "E"].allSatisfy({ ranks[$0]! <= 5 }) {
            let r = ranks["R"]!
            if r < 3 && level >= [6, 11, 16][r] { return "R" }
            return priority.first { ranks[$0]! < min(5, (level + 1) / 2) }
        }
        return nil
    }
}

/// Accept explicit plus glyphs aligned above a complete, evenly-spaced QWER row.
/// Do not invent screen coordinates when OCR cannot find the actual upgrade row.
public enum SkillHUDRecognition {
    /// Upgrade buttons are often graphic arrows, not OCR-readable plus signs.
    /// Infer their row from the detected key labels and square ability spacing.
    public static func anchors(lines: [RecognizedLine], imageAspect: Double) -> [String: HintAnchor] {
        let explicit = plusAnchors(lines: lines)
        guard imageAspect.isFinite, (1...4).contains(imageAspect) else { return explicit }
        let keys = ["Q", "W", "E", "R"]
        let labels = lines.filter { $0.confidence >= 0.5 && $0.y < 0.2 && (0.2...0.8).contains($0.x) }
        var rows: [[RecognizedLine]] = []
        for q in labels where q.text.uppercased() == "Q" {
            var row = [q]
            for key in keys.dropFirst() {
                let matches = labels.filter { $0.text.uppercased() == key && abs($0.y - q.y) < 0.015 && $0.x > row.last!.x }
                guard matches.count == 1 else { row = []; break }
                row.append(matches[0])
            }
            guard row.count == 4 else { continue }
            let gaps = (1..<4).map { row[$0].x - row[$0 - 1].x }
            guard gaps.allSatisfy({ (0.012...0.08).contains($0) }), gaps.max()! / gaps.min()! < 1.3 else { continue }
            rows.append(row)
        }
        guard rows.count == 1, let row = rows.first else { return explicit }
        let spacing = (row[3].x - row[0].x) / 3
        var result = explicit
        for (index, line) in row.enumerated() where result[keys[index]] == nil {
            result[keys[index]] = HintAnchor(x: line.x, y: min(0.3, line.y + spacing * imageAspect * 1.15))
        }
        return result
    }
    public static func plusAnchors(lines: [RecognizedLine]) -> [String: HintAnchor] {
        let keys = ["Q", "W", "E", "R"]
        let labels = lines.filter { $0.confidence >= 0.65 && $0.y < 0.2 && (0.2...0.8).contains($0.x) }
        var result: [String: HintAnchor] = [:]
        for q in labels where q.text.uppercased() == "Q" {
            var row = [q]
            for key in keys.dropFirst() {
                let matches = labels.filter { $0.text.uppercased() == key && abs($0.y - q.y) < 0.015 && $0.x > row.last!.x }
                guard matches.count == 1 else { row = []; break }
                row.append(matches[0])
            }
            guard row.count == 4 else { continue }
            let gaps = (1..<4).map { row[$0].x - row[$0 - 1].x }
            guard gaps.allSatisfy({ (0.015...0.08).contains($0) }), gaps.max()! / gaps.min()! < 1.3 else { continue }
            var candidate: [String: HintAnchor] = [:]
            for (index, label) in row.enumerated() {
                let plus = lines.filter {
                    ["+", "＋"].contains($0.text.trimmingCharacters(in: .whitespaces)) && $0.confidence >= 0.5 &&
                    abs($0.x - label.x) < gaps.min()! * 0.35 && $0.y > label.y + 0.008 && $0.y < label.y + 0.15
                }
                if plus.count == 1 { candidate[keys[index]] = HintAnchor(x: plus[0].x, y: plus[0].y) }
            }
            guard !candidate.isEmpty else { continue }
            if !result.isEmpty { return [:] }
            result = candidate
        }
        return result
    }
}

public struct RecognizedCard: Sendable, Equatable {
    public let id: Int
    public let anchor: HintAnchor
    public init(id: Int, anchor: HintAnchor) { self.id = id; self.anchor = anchor }
}
