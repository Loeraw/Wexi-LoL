import Foundation
import CoreGraphics
import Vision

public enum GameFrameRecognition {
    private static func applyLanguages(_ preferred: [String], to request: VNRecognizeTextRequest) {
        let supported = (try? request.supportedRecognitionLanguages()) ?? []
        var seen = Set<String>()
        let available = preferred.filter { supported.contains($0) && seen.insert($0).inserted }
        request.recognitionLanguages = available.isEmpty ? ["en-US"] : available
    }
    public static func scoreboardLines(image: CGImage,
                                       recognitionLanguages: [String] = ["en-US", "zh-Hans"],
                                       scanRelicTimers: Bool = true) throws -> [RecognizedLine] {
        // The ARAM relic countdown cells sit against the very top edge while
        // Tab is held. Keep the full height; downstream recognition uses the
        // central scoreboard density to reject ordinary HUD text.
        let region = CGRect(x: 0.04, y: 0, width: 0.92, height: 1)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        applyLanguages(recognitionLanguages + ["en-US"], to: request)
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.004
        request.regionOfInterest = region
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        var lines = (request.results ?? []).compactMap { observation -> RecognizedLine? in
            guard let text = observation.topCandidates(1).first else { return nil }
            let box = observation.boundingBox
            return RecognizedLine(text: text.string,
                                  x: region.minX + box.midX * region.width,
                                  y: region.minY + box.midY * region.height,
                                  width: box.width * region.width,
                                  height: box.height * region.height,
                                  confidence: text.confidence)
        }

        // A full-frame Vision pass tends to reverse or merge the tiny timer
        // glyphs (for example 0:22 becomes 22:0). Reading Riot's four fixed
        // cells independently preserves both the digits and their slot order.
        for centerX in scanRelicTimers ? [0.469, 0.499, 0.529, 0.559] : [] {
            let cropRect = CGRect(x: Double(image.width) * (centerX - 0.018),
                                  y: 0,
                                  width: Double(image.width) * 0.036,
                                  height: Double(image.height) * 0.045).integral
            guard let crop = image.cropping(to: cropRect) else { continue }
            let cellRequest = VNRecognizeTextRequest()
            cellRequest.recognitionLevel = .accurate
            cellRequest.recognitionLanguages = ["en-US"]
            cellRequest.usesLanguageCorrection = false
            cellRequest.minimumTextHeight = 0.05
            try VNImageRequestHandler(cgImage: crop, options: [:]).perform([cellRequest])
            guard let candidate = (cellRequest.results ?? [])
                .flatMap({ $0.topCandidates(3) })
                .first(where: { $0.string.contains(":") || $0.string.contains("：") }) else { continue }
            lines.append(RecognizedLine(text: candidate.string,
                                        x: centerX,
                                        y: 0.98,
                                        width: 0.036,
                                        height: 0.02,
                                        confidence: candidate.confidence))
        }
        return lines
    }

    public static func skillLines(image: CGImage) throws -> [RecognizedLine] {
        let region = CGRect(x: 0.2, y: 0, width: 0.6, height: 0.22)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.customWords = ["Q", "W", "E", "R", "D", "F"]
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.003
        request.regionOfInterest = region
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        var lines: [RecognizedLine] = []
        for observation in request.results ?? [] {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let text = candidate.string.uppercased()
            // Vision often joins Q W E R with D F and item hotkeys. Keep the
            // individual ability tokens instead of rejecting the entire row.
            let compact = text.filter { !$0.isWhitespace }
            let joinedKeys = !compact.isEmpty && compact.count <= 10 && compact.allSatisfy { "QWERDF1234567+＋".contains($0) }
            let indices = text.indices.filter { index in
                guard "QWER+＋".contains(text[index]) else { return false }
                if joinedKeys { return true }
                let before = index == text.startIndex || !text[text.index(before: index)].isLetter
                let afterIndex = text.index(after: index)
                let after = afterIndex == text.endIndex || !text[afterIndex].isLetter
                return before && after
            }
            for index in indices {
                let range = index..<text.index(after: index)
                guard let box = try? candidate.boundingBox(for: range)?.boundingBox else { continue }
                lines.append(RecognizedLine(text: String(text[index]),
                                            x: region.minX + box.midX * region.width,
                                            y: region.minY + box.midY * region.height,
                                            width: box.width * region.width,
                                            height: box.height * region.height,
                                            confidence: candidate.confidence))
            }
        }
        return lines
    }
    /// A single small title-strip pass for the common three-card layout.
    public static func fastCardTitleLines(image: CGImage, catalog: [AugmentRating],
                                          recognitionLanguages: [String] = ["zh-Hans", "en-US"]) throws -> [RecognizedLine] {
        guard !catalog.isEmpty else { return [] }
        let rect = CGRect(x: 0.12 * Double(image.width), y: 0.28 * Double(image.height),
                          width: 0.76 * Double(image.width), height: 0.24 * Double(image.height)).integral
        guard let crop = image.cropping(to: rect) else { return [] }
        return try lines(image: crop, catalog: catalog, recognitionLanguages: recognitionLanguages, fast: true).map { line in
            RecognizedLine(text: line.text,
                           x: (rect.minX + line.x * rect.width) / Double(image.width),
                           y: (Double(image.height) - rect.maxY + line.y * rect.height) / Double(image.height),
                           width: line.width * rect.width / Double(image.width),
                           height: line.height * rect.height / Double(image.height), confidence: line.confidence)
        }
    }
    /// Read each choice column separately so small titles are not lost in a
    /// full-frame OCR pass. Coordinates are mapped back to the game window.
    public static func cardTitleLines(image: CGImage, catalog: [AugmentRating],
                                     recognitionLanguages: [String] = ["zh-Hans", "en-US"]) throws -> [RecognizedLine] {
        guard !catalog.isEmpty else { return [] }
        var result: [RecognizedLine] = []
        for (left, right) in [(0.12, 0.38), (0.38, 0.62), (0.62, 0.88)] {
            let rect = CGRect(x: left * Double(image.width), y: 0.15 * Double(image.height),
                              width: (right - left) * Double(image.width), height: 0.60 * Double(image.height)).integral
            guard let crop = image.cropping(to: rect) else { continue }
            let observations = try lines(image: crop, catalog: catalog, recognitionLanguages: recognitionLanguages)
            result += observations.map { line in
                RecognizedLine(text: line.text,
                               x: (rect.minX + line.x * rect.width) / Double(image.width),
                               y: (Double(image.height) - rect.maxY + line.y * rect.height) / Double(image.height),
                               width: line.width * rect.width / Double(image.width),
                               height: line.height * rect.height / Double(image.height), confidence: line.confidence)
            }
        }
        return result
    }
    public static func cardIDs(image: CGImage, catalog: [AugmentRating],
                               recognitionLanguages: [String] = ["zh-Hans", "en-US"]) throws -> [Int] {
        AugmentRecognition.cardIDs(lines: try lines(image: image, catalog: catalog,
                                                    recognitionLanguages: recognitionLanguages), catalog: catalog)
    }
    public static func lines(image: CGImage, catalog: [AugmentRating],
                             recognitionLanguages: [String] = ["zh-Hans", "en-US"],
                             fast: Bool = false) throws -> [RecognizedLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = fast ? .fast : .accurate
        applyLanguages(recognitionLanguages, to: request)
        request.usesLanguageCorrection = false
        request.customWords = catalog.flatMap { [$0.name, $0.englishName ?? ""] + $0.alternateNames }.filter { !$0.isEmpty }
        request.minimumTextHeight = 0.008
        // No file write or upload: the frame and recognized strings are transient.
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        var lines = (request.results ?? []).compactMap { observation -> RecognizedLine? in
            guard let text = observation.topCandidates(1).first else { return nil }
            let box = observation.boundingBox
            return RecognizedLine(text: text.string, x: box.midX, y: box.midY, width: box.width, height: box.height, confidence: text.confidence)
        }
        // Long names may wrap to two lines. Join only nearby lines in the same column.
        let original = lines
        for upper in original {
            for lower in original where lower.y < upper.y && upper.y - lower.y < max(upper.height, lower.height) * 2.2 && abs(upper.x - lower.x) < 0.035 {
                lines.append(RecognizedLine(text: upper.text + " " + lower.text, x: upper.x, y: upper.y,
                                            width: max(upper.width, lower.width), height: upper.height,
                                            confidence: min(upper.confidence, lower.confidence)))
            }
        }
        return lines
    }
}
