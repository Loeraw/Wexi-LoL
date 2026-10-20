import AppKit
import SwiftUI

enum OverlayLayoutKind: String, CaseIterable, Identifiable, Codable {
    case hints, itemBuild, objectiveTimers, playerScout, jungleRoute
    var id: String { rawValue }
    var titleKey: String {
        switch self {
        case .hints: return "海克斯与技能提示"
        case .itemBuild: return "推荐出装面板"
        case .objectiveTimers: return "目标计时面板"
        case .playerScout: return "玩家资料面板"
        case .jungleRoute: return "打野路线"
        }
    }
}

struct OverlayLayoutAdjustment: Codable, Equatable {
    var offsetX = 0.0
    var offsetY = 0.0
    var scale = 1.0
    var opacity = 1.0
}

@MainActor final class OverlayLayoutStore: ObservableObject {
    @Published var isEditing = false
    @Published var selected: OverlayLayoutKind = .itemBuild
    @Published private(set) var resolutionLabel = "—"
    @Published private(set) var revision = 0
    private var profiles: [String: [String: OverlayLayoutAdjustment]] = [:]
    private var activeKey = "default"
    private static let defaultsKey = "overlayLayoutProfiles.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode([String: [String: OverlayLayoutAdjustment]].self, from: data) {
            profiles = decoded
        }
    }

    func begin(frame: CGRect) {
        activeKey = Self.key(for: frame)
        resolutionLabel = activeKey
        isEditing = true
        revision += 1
    }

    func finish() { isEditing = false; save(); revision += 1 }

    func adjustment(for kind: OverlayLayoutKind, frame: CGRect) -> OverlayLayoutAdjustment {
        let key = Self.key(for: frame)
        return profiles[key]?[kind.rawValue] ?? OverlayLayoutAdjustment()
    }

    func activeAdjustment(for kind: OverlayLayoutKind) -> OverlayLayoutAdjustment {
        profiles[activeKey]?[kind.rawValue] ?? OverlayLayoutAdjustment()
    }

    func update(_ kind: OverlayLayoutKind, _ change: (inout OverlayLayoutAdjustment) -> Void) {
        var value = activeAdjustment(for: kind)
        change(&value)
        value.offsetX = min(0.5, max(-0.5, value.offsetX))
        value.offsetY = min(0.5, max(-0.5, value.offsetY))
        value.scale = min(1.6, max(0.6, value.scale))
        value.opacity = min(1, max(0.3, value.opacity))
        profiles[activeKey, default: [:]][kind.rawValue] = value
        save(); revision += 1
    }

    func resetCurrentResolution() {
        profiles.removeValue(forKey: activeKey)
        save(); revision += 1
    }

    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(profiles), forKey: Self.defaultsKey)
    }

    private static func key(for frame: CGRect) -> String {
        "\(Int(frame.width.rounded()))×\(Int(frame.height.rounded()))"
    }
}

private final class LayoutPreviewPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct LayoutPreviewView: View {
    let title: String
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.78))
            RoundedRectangle(cornerRadius: 10).stroke(Color.mint, style: StrokeStyle(lineWidth: 2, dash: [7, 4]))
            VStack(spacing: 5) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                Text(title).font(.system(size: 13, weight: .bold))
                Text(L10n.text("拖动移动 · 拖动边缘缩放")).font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
    }
}

@MainActor final class OverlayLayoutEditorController: NSObject, NSWindowDelegate {
    private var panels: [OverlayLayoutKind: LayoutPreviewPanel] = [:]
    private weak var store: OverlayLayoutStore?
    private var target = CGRect.zero
    private var applying = false

    func update(store: OverlayLayoutStore, target: CGRect) {
        self.store = store; self.target = target
        guard store.isEditing else { hide(); return }
        for kind in OverlayLayoutKind.allCases {
            let panel = panels[kind] ?? makePanel(kind)
            let adjustment = store.activeAdjustment(for: kind)
            let base = baseFrame(kind, in: target)
            let size = CGSize(width: base.width * adjustment.scale, height: base.height * adjustment.scale)
            let center = CGPoint(x: base.midX + adjustment.offsetX * target.width,
                                 y: base.midY + adjustment.offsetY * target.height)
            let frame = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                               width: size.width, height: size.height)
            applying = true
            if panel.frame != frame { panel.setFrame(frame, display: true) }
            applying = false
            panel.alphaValue = adjustment.opacity
            panel.level = .floating
            panel.orderFrontRegardless()
        }
    }

    func hide() { panels.values.forEach { $0.orderOut(nil) } }

    func windowDidMove(_ notification: Notification) { capture(notification.object as? NSWindow) }
    func windowDidResize(_ notification: Notification) { capture(notification.object as? NSWindow) }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard let kind = panels.first(where: { $0.value === sender })?.key else { return frameSize }
        let base = baseFrame(kind, in: target)
        let scale = min(Double(frameSize.width / base.width), Double(frameSize.height / base.height))
        return NSSize(width: base.width * scale, height: base.height * scale)
    }

    private func capture(_ window: NSWindow?) {
        guard !applying, let window, let store,
              let kind = panels.first(where: { $0.value === window })?.key,
              target.width > 0, target.height > 0 else { return }
        let base = baseFrame(kind, in: target)
        store.update(kind) {
            $0.offsetX = Double((window.frame.midX - base.midX) / target.width)
            $0.offsetY = Double((window.frame.midY - base.midY) / target.height)
            $0.scale = Double(window.frame.width / base.width)
        }
    }

    private func makePanel(_ kind: OverlayLayoutKind) -> LayoutPreviewPanel {
        let panel = LayoutPreviewPanel(contentRect: .zero, styleMask: [.borderless, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.isFloatingPanel = true; panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true; panel.ignoresMouseEvents = false; panel.delegate = self
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: LayoutPreviewView(title: L10n.text(kind.titleKey)))
        panel.minSize = NSSize(width: 100, height: 44)
        panels[kind] = panel
        return panel
    }

    private func baseFrame(_ kind: OverlayLayoutKind, in bounds: CGRect) -> CGRect {
        switch kind {
        case .hints:
            return CGRect(x: bounds.midX - 125, y: bounds.midY + bounds.height * 0.18, width: 250, height: 52)
        case .itemBuild:
            return CGRect(x: bounds.minX + 24, y: bounds.maxY - 220, width: 342, height: 132)
        case .objectiveTimers:
            return CGRect(x: bounds.maxX - 220, y: bounds.maxY - 250, width: 194, height: 160)
        case .playerScout:
            return CGRect(x: bounds.midX - 433, y: bounds.midY - 95, width: 866, height: 190)
        case .jungleRoute:
            let side = min(bounds.width * 0.146, bounds.height * 0.260)
            return CGRect(x: bounds.maxX - side, y: bounds.minY, width: side, height: side)
        }
    }
}
