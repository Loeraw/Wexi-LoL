import AppKit

@MainActor struct GameSurface {
    let frame: CGRect
    let layer: Int
    let foreground: Bool

    static func current() -> GameSurface? {
        let gamePIDs = Set(NSWorkspace.shared.runningApplications.filter {
            GameWindow.isGame(name: $0.localizedName, bundle: $0.bundleIdentifier)
        }.map(\.processIdentifier))
        guard !gamePIDs.isEmpty,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let surfaces: [(CGRect, Int, pid_t)] = windows.compactMap { item in
            guard let pid = item[kCGWindowOwnerPID as String] as? Int32, gamePIDs.contains(pid),
                  let bounds = item[kCGWindowBounds as String] as? [String: Any],
                  let cgRect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  cgRect.width >= 640, cgRect.height >= 360 else { return nil }
            let top = NSScreen.screens.first?.frame.maxY ?? 0
            let frame = CGRect(x: cgRect.minX, y: top - cgRect.maxY, width: cgRect.width, height: cgRect.height)
            return (frame, item[kCGWindowLayer as String] as? Int ?? 0, pid)
        }
        guard let selected = surfaces.max(by: { $0.0.width * $0.0.height < $1.0.width * $1.0.height }) else { return nil }
        return GameSurface(frame: selected.0, layer: selected.1, foreground: frontPID == selected.2)
    }

    var placementBounds: CGRect {
        let screen = NSScreen.screens.max { first, second in
            let a = first.frame.intersection(frame), b = second.frame.intersection(frame)
            return (a.isNull ? 0 : a.width * a.height) < (b.isNull ? 0 : b.width * b.height)
        }
        guard let screen else { return frame }
        let intersection = screen.visibleFrame.intersection(frame)
        return intersection.isNull ? screen.visibleFrame : intersection
    }

    func minimapBounds(normalized: CGRect?) -> CGRect {
        if let normalized,
           normalized.width > 0.05, normalized.height > 0.08,
           normalized.maxX <= 1.01, normalized.maxY <= 1.01 {
            return CGRect(x: frame.minX + normalized.minX * frame.width,
                          y: frame.minY + normalized.minY * frame.height,
                          width: normalized.width * frame.width,
                          height: normalized.height * frame.height)
        }
        let side = min(frame.width * 0.146, frame.height * 0.260)
        return CGRect(x: frame.maxX - side, y: frame.minY, width: side, height: side)
    }
}

