import AppKit
import SwiftUI

enum JungleStartSide: String, CaseIterable, Identifiable {
    case blue, red
    var id: String { rawValue }
    var titleKey: String { self == .blue ? "蓝 BUFF 起手" : "红 BUFF 起手" }
}

enum JungleRouteChoice: String, CaseIterable, Identifiable {
    case fullClear, levelThree, invade
    var id: String { rawValue }
    var titleKey: String {
        switch self {
        case .fullClear: return "六组野全清"
        case .levelThree: return "三级快速抓人"
        case .invade: return "反向入侵路线"
        }
    }
}

@MainActor final class JungleRouteStore: ObservableObject {
    @Published var enabled: Bool { didSet { UserDefaults.standard.set(enabled, forKey: "jungleRouteEnabled.v1") } }
    @Published var side: JungleStartSide { didSet { UserDefaults.standard.set(side.rawValue, forKey: "jungleRouteSide.v1") } }
    @Published var route: JungleRouteChoice { didSet { UserDefaults.standard.set(route.rawValue, forKey: "jungleRouteChoice.v1") } }
    init() {
        enabled = UserDefaults.standard.bool(forKey: "jungleRouteEnabled.v1")
        side = JungleStartSide(rawValue: UserDefaults.standard.string(forKey: "jungleRouteSide.v1") ?? "blue") ?? .blue
        route = JungleRouteChoice(rawValue: UserDefaults.standard.string(forKey: "jungleRouteChoice.v1") ?? "fullClear") ?? .fullClear
    }
}

private final class JungleRoutePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct JungleRouteMapView: View {
    let start: JungleStartSide
    let route: JungleRouteChoice
    let activeTeam: String
    let opacity: Double

    private var points: [CGPoint] {
        // ORDER-side camp centers in normalized minimap coordinates. Starting
        // buff changes only the clear order; it must not rotate the route to
        // the enemy jungle. CHAOS-side players are rotated independently.
        let gromp = CGPoint(x: 0.145, y: 0.565)
        let blue = CGPoint(x: 0.260, y: 0.530)
        let wolves = CGPoint(x: 0.255, y: 0.425)
        let raptors = CGPoint(x: 0.440, y: 0.350)
        let red = CGPoint(x: 0.520, y: 0.270)
        let krugs = CGPoint(x: 0.565, y: 0.180)
        let midRiver = CGPoint(x: 0.500, y: 0.500)
        let orderPoints: [CGPoint]
        switch (route, start) {
        case (.fullClear, .blue): orderPoints = [blue, gromp, wolves, raptors, red, krugs]
        case (.fullClear, .red): orderPoints = [red, krugs, raptors, wolves, blue, gromp]
        case (.levelThree, .blue): orderPoints = [blue, gromp, red, midRiver]
        case (.levelThree, .red): orderPoints = [red, blue, gromp, midRiver]
        case (.invade, .blue): orderPoints = [blue, gromp, midRiver, CGPoint(x: 0.740, y: 0.470)]
        case (.invade, .red): orderPoints = [red, raptors, midRiver, CGPoint(x: 0.480, y: 0.730)]
        }
        return activeTeam == "CHAOS"
            ? orderPoints.map { CGPoint(x: 1 - $0.x, y: 1 - $0.y) }
            : orderPoints
    }

    var body: some View {
        GeometryReader { proxy in
            let inset = min(proxy.size.width, proxy.size.height) * 0.045
            let mapWidth = max(1, proxy.size.width - inset * 2)
            let mapHeight = max(1, proxy.size.height - inset * 2)
            let positions = points.map { CGPoint(x: inset + $0.x * mapWidth,
                                                  y: inset + (1 - $0.y) * mapHeight) }
            ZStack {
                Canvas { context, _ in
                    guard let first = positions.first else { return }
                    var path = Path(); path.move(to: first)
                    positions.dropFirst().forEach { path.addLine(to: $0) }
                    context.stroke(path, with: .color(.mint.opacity(0.9 * opacity)), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [7, 4]))
                }
                ForEach(Array(positions.enumerated()), id: \.offset) { index, point in
                    Text("\(index + 1)").font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundStyle(.black).frame(width: 22, height: 22)
                        .background(index == 0 ? Color.yellow : Color.mint, in: Circle())
                        .overlay(Circle().stroke(.black.opacity(0.8), lineWidth: 2))
                        .position(point)
                }
            }
        }
    }
}

@MainActor final class JungleRouteOverlayController {
    private var panel: JungleRoutePanel?
    private var signature = ""
    func update(store: JungleRouteStore, model: OverlayModel, layouts: OverlayLayoutStore,
                gameMode: String, activeTeam: String, minimapFrame: CGRect?, game: GameSurface?) {
        guard store.enabled, gameMode.uppercased() == "CLASSIC", let game, game.foreground else { hide(); return }
        let panel = self.panel ?? makePanel()
        let layout = layouts.adjustment(for: .jungleRoute, frame: game.frame)
        let bounds = game.frame
        let detected = game.minimapBounds(normalized: minimapFrame)
        let side = min(detected.width, detected.height) * layout.scale
        let next = "\(store.side.rawValue):\(store.route.rawValue):\(activeTeam):\(side):\(layout.opacity):\(model.opacity)"
        if signature != next {
            signature = next
            panel.contentView = NSHostingView(rootView: JungleRouteMapView(
                start: store.side, route: store.route, activeTeam: activeTeam,
                opacity: model.opacity * layout.opacity
            ))
        }
        let frame = CGRect(x: detected.maxX - side + layout.offsetX * bounds.width,
                           y: detected.minY + layout.offsetY * bounds.height, width: side, height: side)
        panel.level = NSWindow.Level(rawValue: max(Int(CGShieldingWindowLevel()) + 1, game.layer + 1))
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        panel.alphaValue = model.opacity * layout.opacity
        panel.orderFrontRegardless()
    }
    func hide() { panel?.orderOut(nil) }
    private func makePanel() -> JungleRoutePanel {
        let panel = JungleRoutePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.isFloatingPanel = true; panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true; panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .canJoinAllApplications]
        panel.title = L10n.text("Wexi LoL 打野路线")
        self.panel = panel; return panel
    }
}
