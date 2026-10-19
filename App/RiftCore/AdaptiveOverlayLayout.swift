import Foundation

/// Resolution-independent helpers shared by the overlay windows and OCR.
public enum AdaptiveOverlayLayout {
    /// Keeps controls readable at small window sizes while avoiding oversized
    /// panels on high-resolution displays. The original layout was authored at
    /// 2560×1440.
    public static func scale(width: Double, height: Double) -> Double {
        guard width.isFinite, height.isFinite, width > 0, height > 0 else { return 1 }
        return min(1.15, max(0.80, min(width / 2560, height / 1440)))
    }

    /// League centers most fixed-aspect UI inside a 16:9 region on ultrawide
    /// displays. Narrower displays use their full width.
    public static func contentX(_ normalizedX: Double, width: Double, height: Double) -> Double {
        guard width.isFinite, height.isFinite, width > 0, height > 0 else { return normalizedX }
        let contentWidth = min(width, height * 16 / 9)
        let inset = (width - contentWidth) / 2
        return (inset + min(1, max(0, normalizedX)) * contentWidth) / width
    }
}

/// Finds player-name anchors in a captured loading screen or Tab scoreboard.
/// Riot IDs include a tag (Name#TAG), while the game UI commonly displays only
/// the game name, so both forms are matched.
public enum PlayerUIAnchorRecognition {
    public static func anchors(lines: [RecognizedLine], riotIDs: [String]) -> [String: HintAnchor] {
        let usable = lines.enumerated().filter {
            $0.element.confidence >= 0.22 && (0.02...0.98).contains($0.element.x) &&
                (0.02...0.98).contains($0.element.y)
        }
        var candidates: [(riotID: String, lineIndex: Int, line: RecognizedLine, score: Double)] = []
        for riotID in riotIDs {
            let full = normalized(riotID)
            let gameNamePart = riotID.split(separator: "#", maxSplits: 1).first.map(String.init) ?? riotID
            let gameName = normalized(gameNamePart)
            guard gameName.count >= 3 else { continue }
            for (index, line) in usable {
                let text = normalized(line.text)
                guard !text.isEmpty else { continue }
                let quality: Double
                if text == full { quality = 8 }
                else if text == gameName { quality = 7 }
                else if text.contains(full), full.count >= 5 { quality = 6 }
                else if (text.hasPrefix(gameName) || text.hasSuffix(gameName)), gameName.count >= 3 { quality = 5.5 }
                else if text.contains(gameName), gameName.count >= 5 { quality = 5 }
                else { continue }
                let lengthPenalty = Double(abs(text.count - gameName.count)) * 0.015
                candidates.append((riotID, index, line, quality + Double(line.confidence) - lengthPenalty))
            }
        }

        var result: [String: HintAnchor] = [:]
        var usedLines = Set<Int>()
        for candidate in candidates.sorted(by: { $0.score > $1.score }) {
            guard result[candidate.riotID] == nil, !usedLines.contains(candidate.lineIndex) else { continue }
            result[candidate.riotID] = HintAnchor(x: candidate.line.x, y: candidate.line.y)
            usedLines.insert(candidate.lineIndex)
        }
        return result
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                      locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }
}
