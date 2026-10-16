import Foundation

public struct HealthRelicTimerReading: Equatable, Sendable {
    public let remaining: Int
    public let x: Double

    public init(remaining: Int, x: Double) {
        self.remaining = remaining
        self.x = x
    }
}

public struct HealthRelicScan: Equatable, Sendable {
    public let scoreboardVisible: Bool
    public let readings: [HealthRelicTimerReading]

    public init(scoreboardVisible: Bool, readings: [HealthRelicTimerReading]) {
        self.scoreboardVisible = scoreboardVisible
        self.readings = readings
    }
}

public enum HealthRelicRecognition {
    private static let timerPattern = try! NSRegularExpression(
        pattern: #"(?<![0-9])([01])\s*[:：.]\s*([0-5][0-9])(?![0-9])"#
    )

    /// Extracts the health-relic countdown row shown at the top-center while
    /// the Tab scoreboard is visible. The scoreboard density check prevents
    /// ordinary HUD clocks from being accepted when Tab is closed.
    public static func scan(lines: [RecognizedLine]) -> HealthRelicScan {
        let scoreboardLines = lines.filter {
            $0.confidence >= 0.18 && $0.x >= 0.08 && $0.x <= 0.92 && $0.y >= 0.16 && $0.y <= 0.93
        }
        let yValues = scoreboardLines.map(\.y)
        let scoreboardVisible = scoreboardLines.count >= 8 &&
            ((yValues.max() ?? 0) - (yValues.min() ?? 0) >= 0.22)
        guard scoreboardVisible else { return HealthRelicScan(scoreboardVisible: false, readings: []) }

        var candidates: [(reading: HealthRelicTimerReading, y: Double, confidence: Float)] = []
        let timerLines = lines.filter {
            $0.confidence >= 0.18 && $0.x >= 0.36 && $0.x <= 0.64 && $0.y >= 0.94
        }
        for line in timerLines {
            // Vision commonly confuses a zero with O in small timer text.
            let normalized = line.text.uppercased().replacingOccurrences(of: "O", with: "0")
            let nsRange = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
            for match in timerPattern.matches(in: normalized, range: nsRange) {
                guard let minuteRange = Range(match.range(at: 1), in: normalized),
                      let secondRange = Range(match.range(at: 2), in: normalized),
                      let minutes = Int(normalized[minuteRange]),
                      let seconds = Int(normalized[secondRange]) else { continue }
                let remaining = minutes * 60 + seconds
                guard (1...90).contains(remaining) else { continue }
                let fraction = (Double(match.range.location) + Double(match.range.length) / 2) /
                    Double(max(1, normalized.utf16.count))
                let x = line.x - line.width / 2 + line.width * fraction
                candidates.append((HealthRelicTimerReading(remaining: remaining, x: x), line.y, line.confidence))
            }
        }
        guard !candidates.isEmpty else { return HealthRelicScan(scoreboardVisible: true, readings: []) }

        // Relic timers form one horizontal row. Keeping only that row rejects
        // unrelated m:ss strings that may occur in player or tooltip text.
        let best = candidates.map { seed in
            candidates.filter { abs($0.y - seed.y) <= 0.035 }
        }.max {
            if $0.count != $1.count { return $0.count < $1.count }
            return $0.reduce(0) { $0 + $1.confidence } < $1.reduce(0) { $0 + $1.confidence }
        } ?? []
        let readings = best.map(\.reading)
            .sorted { $0.x < $1.x }
            .reduce(into: [HealthRelicTimerReading]()) { result, reading in
                guard !result.contains(where: { abs($0.x - reading.x) < 0.018 }) else { return }
                result.append(reading)
            }
        return HealthRelicScan(scoreboardVisible: true, readings: Array(readings.prefix(4)))
    }
}
