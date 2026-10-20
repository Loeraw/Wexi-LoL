import CoreGraphics
import Foundation

public enum MinimapFrameRecognition {
    /// Finds the left edge of the square minimap frame in the lower-right HUD.
    /// The result uses normalized game-window coordinates with a bottom-left origin.
    public static func normalizedFrame(image: CGImage) -> CGRect? {
        let width = image.width, height = image.height
        guard width >= 640, height >= 360 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(data: &pixels, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width,
                                      space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return normalizedFrame(width: width, height: height, grayscale: pixels)
    }

    public static func normalizedFrame(width: Int, height: Int, grayscale: [UInt8]) -> CGRect? {
        guard width >= 640, height >= 360, grayscale.count >= width * height else { return nil }
        let minimumSide = Int(Double(height) * 0.16)
        let maximumSide = Int(Double(height) * 0.36)
        let firstX = max(Int(Double(width) * 0.70), width - maximumSide)
        let lastX = min(Int(Double(width) * 0.94), width - minimumSide)
        let band = max(40, Int(Double(height) * 0.40))
        var bestX = 0, bestScore = 0.0

        for x in firstX...lastX {
            var firstEdge = 0, lastEdge = 0
            for y in 0..<band {
                let first = y * width + x
                let last = (height - 1 - y) * width + x
                firstEdge += abs(Int(grayscale[first]) - Int(grayscale[first + 1]))
                lastEdge += abs(Int(grayscale[last]) - Int(grayscale[last + 1]))
            }
            // Bitmap row orientation can differ between capture sources.
            let score = Double(max(firstEdge, lastEdge)) / Double(band)
            if score > bestScore { bestScore = score; bestX = x }
        }
        guard bestScore >= 8 else { return nil }
        let side = width - bestX
        guard side >= minimumSide, side <= maximumSide else { return nil }
        return CGRect(x: Double(bestX) / Double(width), y: 0,
                      width: Double(side) / Double(width), height: Double(side) / Double(height))
    }
}
