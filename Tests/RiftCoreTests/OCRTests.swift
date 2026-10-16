import XCTest
import AppKit
@testable import RiftCore

final class OCRTests: XCTestCase {
    func testAbilityRowOCRWithoutTextPlusButtons() throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1800, pixelsHigh: 1000,
                                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                   isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        NSColor.black.setFill(); NSRect(x: 0, y: 0, width: 1800, height: 1000).fill()
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 26, weight: .bold), .foregroundColor: NSColor.white]
        for (index, key) in ["Q", "W", "E", "R"].enumerated() {
            (key as NSString).draw(at: NSPoint(x: 700 + index * 65, y: 40), withAttributes: attrs)
        }
        NSGraphicsContext.restoreGraphicsState()
        let lines = try GameFrameRecognition.skillLines(image: XCTUnwrap(bitmap.cgImage))
        XCTAssertEqual(SkillHUDRecognition.anchors(lines: lines, imageAspect: 1.8).count, 4, "\(lines)")
    }
    func testActualVisionOCRWithSyntheticCards() throws {
        try checkTitles(["Scopier Weapons", "Marksmage", "Deft"])
        try checkTitles(["更万用的瞄准镜", "神射法师", "灵巧"])
    }
    private func checkTitles(_ titles: [String]) throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1800, pixelsHigh: 1000,
                                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                   isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.black.setFill()
        NSRect(x: 0, y: 0, width: 1800, height: 1000).fill()
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 32, weight: .bold), .foregroundColor: NSColor.white]
        for (i, title) in titles.enumerated() {
            let text = title as NSString
            let size = text.size(withAttributes: attributes)
            text.draw(at: NSPoint(x: Double(i + 1) * 450 - size.width / 2, y: 620), withAttributes: attributes)
        }
        NSGraphicsContext.restoreGraphicsState()
        let image = try XCTUnwrap(bitmap.cgImage)
        let catalog = [
            AugmentRating(id: 1, name: "更万用的瞄准镜", key: "ARAM_ScopierWeapons", tier: 0, rarity: 4),
            AugmentRating(id: 2, name: "神射法师", key: "ARAM_Marksmage", tier: 1, rarity: 4),
            AugmentRating(id: 3, name: "灵巧", key: "ARAM_Deft", tier: 2, rarity: 1)
        ]
        let start = Date()
        let fast = try GameFrameRecognition.fastCardTitleLines(image: image, catalog: catalog)
        let fastDuration = Date().timeIntervalSince(start)
        let slowStart = Date()
        let lines = try GameFrameRecognition.lines(image: image, catalog: catalog) + GameFrameRecognition.cardTitleLines(image: image, catalog: catalog)
        print("Synthetic title OCR: fast=\(fastDuration)s previous=\(Date().timeIntervalSince(slowStart))s")
        let fastCards = AugmentRecognition.visibleCards(lines: fast, catalog: catalog)
        // The small crop can confuse Chinese homographs; the slow path must
        // recover them instead of accepting a guessed first-frame rating.
        if titles.first == "Scopier Weapons" {
            XCTAssertEqual(fastCards.map(\.id), [1, 2, 3])
            XCTAssertTrue(AugmentRecognition.isExactTriple(fastCards, lines: fast, catalog: catalog))
        } else {
            XCTAssertTrue(Set(fastCards.map(\.id)).isSuperset(of: [2, 3]))
        }
        XCTAssertEqual(AugmentRecognition.visibleCards(lines: fast + lines, catalog: catalog).map(\.id), [1, 2, 3])
        XCTAssertEqual(AugmentRecognition.cardIDs(lines: lines, catalog: catalog), [1, 2, 3], "OCR observations: \(lines)")
    }
}
