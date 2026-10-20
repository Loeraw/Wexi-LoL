import AppKit
import SwiftUI
import RiftCore

private final class ObjectiveTimerPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct ObjectiveTimerList: View {
    let rows: [ObjectiveCountdown]
    let opacity: Double
    let scale: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8 * scale) {
                    Image(systemName: icon(row.kind)).frame(width: 16 * scale).foregroundStyle(color(row.kind))
                    Text(label(row)).lineLimit(1)
                    Spacer(minLength: 12)
                    Text(clock(row.remaining)).monospacedDigit().foregroundStyle(.white)
                }
                .font(.system(size: 13 * scale, weight: .semibold, design: .rounded))
            }
        }
        .foregroundStyle(.white.opacity(0.92))
        .padding(.horizontal, 12 * scale)
        .padding(.vertical, 9 * scale)
        .frame(width: 194 * scale)
        .background(Color.black.opacity(0.86 * opacity), in: RoundedRectangle(cornerRadius: 10 * scale))
        .overlay(RoundedRectangle(cornerRadius: 10 * scale).stroke(Color.white.opacity(0.13), lineWidth: 1))
    }

    private func label(_ row: ObjectiveCountdown) -> String {
        switch row.kind {
        case .dragon: return L10n.text("小龙")
        case .elderDragon: return L10n.text("远古巨龙")
        case .voidGrubs: return L10n.text("虚空巢虫")
        case .riftHerald: return L10n.text("峡谷先锋")
        case .baron: return L10n.text("纳什男爵")
        case .healthRelic:
            return row.slot.map { L10n.text("血包 %d", $0) } ?? L10n.text("血包首次刷新")
        }
    }

    private func icon(_ kind: ObjectiveKind) -> String {
        switch kind {
        case .dragon, .elderDragon: return "flame.fill"
        case .voidGrubs: return "circle.hexagongrid.fill"
        case .riftHerald: return "eye.fill"
        case .baron: return "crown.fill"
        case .healthRelic: return "cross.fill"
        }
    }

    private func color(_ kind: ObjectiveKind) -> Color {
        switch kind {
        case .dragon: return .orange
        case .elderDragon: return .purple
        case .voidGrubs: return .indigo
        case .riftHerald: return .cyan
        case .baron: return .purple
        case .healthRelic: return .green
        }
    }

    private func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", max(0, seconds) / 60, max(0, seconds) % 60)
    }
}

private struct HealthRelicMapTimers: View {
    let rows: [ObjectiveCountdown]
    let opacity: Double
    let scale: CGFloat
    // Normalized pad centers measured from the in-game Bridge of Progress
    // minimap. Values use bottom-left map coordinates, blue to red.
    private let anchors: [(x: Double, y: Double)] = [
        (0.324, 0.390),
        (0.417, 0.467),
        (0.583, 0.533),
        (0.676, 0.610)
    ]

    private var timers: [(slot: Int, remaining: Int)] {
        rows.flatMap { row -> [(slot: Int, remaining: Int)] in
            if let slot = row.slot { return [(slot, row.remaining)] }
            // Before the first 1:45 spawn all four relics share one timer.
            return (1...4).map { ($0, row.remaining) }
        }
    }

    var body: some View {
        GeometryReader { proxy in
            ForEach(timers, id: \.slot) { timer in
                let anchor = anchors[timer.slot - 1]
                Text(clock(timer.remaining))
                    .font(.system(size: 13 * scale, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .shadow(color: .black, radius: 1, x: 0, y: 1)
                    .padding(.horizontal, 5 * scale).padding(.vertical, 2 * scale)
                    .background(Color.black.opacity(0.82 * opacity), in: RoundedRectangle(cornerRadius: 5 * scale))
                    .position(x: proxy.size.width * anchor.x,
                              y: proxy.size.height * (1 - anchor.y))
            }
        }
    }

    private func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", max(0, seconds) / 60, max(0, seconds) % 60)
    }
}

@MainActor final class ObjectiveTimerOverlayController {
    private var panel: ObjectiveTimerPanel?
    private var signature = ""

    func update(store: ObjectiveTimerStore, model: OverlayModel, game: GameSurface?) {
        guard store.enabled, !store.rows.isEmpty, let game, game.foreground else {
            panel?.orderOut(nil)
            return
        }
        let panel = self.panel ?? makePanel()
        let scale = CGFloat(AdaptiveOverlayLayout.scale(
            width: Double(game.frame.width), height: Double(game.frame.height), preference: model.overlayScale
        ))
        let nextSignature = store.rows.map { "\($0.kind.rawValue):\($0.slot ?? 0):\($0.remaining)" }.joined(separator: "|")
            + ":\(scale):\(LanguageSettings.shared.selection.rawValue):\(Int(model.opacity * 100))"
        if signature != nextSignature {
            signature = nextSignature
            if store.isAram {
                panel.contentView = NSHostingView(rootView: HealthRelicMapTimers(
                    rows: store.rows, opacity: model.opacity, scale: scale
                ))
            } else {
                panel.contentView = NSHostingView(rootView: ObjectiveTimerList(
                    rows: store.rows, opacity: model.opacity, scale: scale
                ))
            }
        }
        let frame: NSRect
        if store.isAram {
            // The HUD is anchored to the full game window. placementBounds
            // excludes the macOS Dock and shifts the overlay up and right.
            let bounds = game.frame
            let side = min(bounds.width * 0.151, bounds.height * 0.268)
            frame = NSRect(x: bounds.maxX - side, y: bounds.minY, width: side, height: side)
        } else {
            let bounds = game.placementBounds
            let height = CGFloat(store.rows.count * 28 + 18) * scale
            let width = 194 * scale
            frame = NSRect(x: bounds.maxX - width - 16 * scale,
                           y: bounds.maxY - height - 82 * scale,
                           width: width, height: height)
        }
        let level = NSWindow.Level(rawValue: max(Int(CGShieldingWindowLevel()) + 1, game.layer + 1))
        panel.level = level
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        panel.alphaValue = model.opacity
        panel.orderFrontRegardless()
    }

    func hide() { panel?.orderOut(nil) }

    private func makePanel() -> ObjectiveTimerPanel {
        let panel = ObjectiveTimerPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .canJoinAllApplications]
        panel.title = L10n.text("Wexi LoL 目标计时")
        self.panel = panel
        return panel
    }
}
