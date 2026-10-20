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
    let side: JungleStartSide
    let route: JungleRouteChoice
    let opacity: Double

    private var points: [CGPoint] {
        let blue: [CGPoint]
        switch route {
        case .fullClear: blue = [.init(x: 0.28, y: 0.27), .init(x: 0.20, y: 0.39), .init(x: 0.34, y: 0.45), .init(x: 0.48, y: 0.57), .init(x: 0.61, y: 0.67), .init(x: 0.73, y: 0.57)]
        case .levelThree: blue = [.init(x: 0.28, y: 0.27), .init(x: 0.20, y: 0.39), .init(x: 0.34, y: 0.45), .init(x: 0.53, y: 0.50)]
        case .invade: blue = [.init(x: 0.28, y: 0.27), .init(x: 0.34, y: 0.45), .init(x: 0.62, y: 0.69), .init(x: 0.74, y: 0.72)]
        }
        return side == .blue ? blue : blue.map { CGPoint(x: 1 - $0.x, y: 1 - $0.y) }
    }

    var body: some View {
        GeometryReader { proxy in
            let positions = points.map { CGPoint(x: $0.x * proxy.size.width, y: (1 - $0.y) * proxy.size.height) }
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
                gameMode: String, game: GameSurface?) {
        guard store.enabled, gameMode.uppercased() == "CLASSIC", let game, game.foreground else { hide(); return }
        let panel = self.panel ?? makePanel()
        let layout = layouts.adjustment(for: .jungleRoute, frame: game.frame)
        let bounds = game.frame
        let baseSide = min(bounds.width * 0.151, bounds.height * 0.268)
        let side = baseSide * layout.scale * model.overlayScale
        let next = "\(store.side.rawValue):\(store.route.rawValue):\(side):\(layout.opacity):\(model.opacity)"
        if signature != next {
            signature = next
            panel.contentView = NSHostingView(rootView: JungleRouteMapView(
                side: store.side, route: store.route, opacity: model.opacity * layout.opacity
            ))
        }
        let frame = CGRect(x: bounds.maxX - side + layout.offsetX * bounds.width,
                           y: bounds.minY + layout.offsetY * bounds.height, width: side, height: side)
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
