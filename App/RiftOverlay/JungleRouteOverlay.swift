import AppKit
import SwiftUI
import RiftCore

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
    @Published private(set) var sessionCompleted = false
    private var previousGameTime: Double?
    init() {
        enabled = UserDefaults.standard.bool(forKey: "jungleRouteEnabled.v1")
        side = JungleStartSide(rawValue: UserDefaults.standard.string(forKey: "jungleRouteSide.v1") ?? "blue") ?? .blue
        route = JungleRouteChoice(rawValue: UserDefaults.standard.string(forKey: "jungleRouteChoice.v1") ?? "fullClear") ?? .fullClear
    }

    func updateSession(gameMode: String, gameTime: Double?, activeLevel: Int) {
        guard gameMode.uppercased() == "CLASSIC", let gameTime else {
            previousGameTime = nil
            sessionCompleted = false
            return
        }
        if let previousGameTime, gameTime + 10 < previousGameTime {
            sessionCompleted = false
        }
        previousGameTime = gameTime
        if !sessionCompleted,
           JungleRouteCompletion.shouldClose(route: route.rawValue, activeLevel: activeLevel, gameTime: gameTime) {
            sessionCompleted = true
        }
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
        guard store.enabled, !store.sessionCompleted, gameMode.uppercased() == "CLASSIC",
              let game, game.foreground else { hide(); return }
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

private final class JungleRouteControlPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct JungleRouteControlView: View {
    @ObservedObject var store: JungleRouteStore

    private func choiceButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(L10n.text(title))
                .font(.system(size: 11, weight: selected ? .bold : .medium))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(selected ? Color.mint.opacity(0.85) : Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(selected ? .black : .white)
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 8) {
                Text(L10n.text("打野路线")).font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                Spacer()
                Toggle(L10n.text("在小地图显示打野路线"), isOn: $store.enabled)
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
            }
            HStack(spacing: 6) {
                ForEach(JungleStartSide.allCases) { option in
                    choiceButton(option.titleKey, selected: store.side == option) { store.side = option }
                }
            }
            HStack(spacing: 6) {
                ForEach(JungleRouteChoice.allCases) { option in
                    choiceButton(option.titleKey, selected: store.route == option) { store.route = option }
                }
            }
        }
        .padding(10)
        .background(Color.black.opacity(0.84), in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.white.opacity(0.18), lineWidth: 1))
    }
}

@MainActor final class JungleRouteControlController {
    private var panel: JungleRouteControlPanel?

    func update(store: JungleRouteStore, gameMode: String, minimapFrame: CGRect?, game: GameSurface?) {
        guard !store.sessionCompleted, gameMode.uppercased() == "CLASSIC",
              let game, game.foreground else { hide(); return }
        let panel = self.panel ?? makePanel(store: store)
        let minimap = game.minimapBounds(normalized: minimapFrame)
        let width = min(390.0, max(330.0, minimap.width * 1.05))
        let height = 104.0
        let x = min(game.frame.maxX - width - 8, max(game.frame.minX + 8, minimap.maxX - width))
        let y = min(game.frame.maxY - height - 8, minimap.maxY + 8)
        let frame = CGRect(x: x, y: y, width: width, height: height)
        panel.level = NSWindow.Level(rawValue: max(Int(CGShieldingWindowLevel()) + 2, game.layer + 2))
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        panel.orderFrontRegardless()
    }

    func hide() { panel?.orderOut(nil) }

    private func makePanel(store: JungleRouteStore) -> JungleRouteControlPanel {
        let panel = JungleRouteControlPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = NSHostingView(rootView: JungleRouteControlView(store: store))
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.isFloatingPanel = true; panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = false; panel.animationBehavior = .none
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .canJoinAllApplications]
        panel.title = L10n.text("打野路线")
        self.panel = panel
        return panel
    }
}
