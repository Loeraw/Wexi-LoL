import AppKit
import SwiftUI
import RiftCore

private final class ItemBuildPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct BuildItemCell: View {
    let item: BuildItem
    let owned: Bool
    let next: Bool

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                AsyncImage(url: URL(string: item.imageURL)) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Image(systemName: "shippingbox.fill")
                            .font(.system(size: 20)).foregroundStyle(.white.opacity(0.6))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.white.opacity(0.08))
                    }
                }
                .frame(width: 42, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(next ? Color.mint : .white.opacity(0.18), lineWidth: next ? 2 : 1))
                if owned {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13)).foregroundStyle(.mint)
                        .background(Color.black, in: Circle())
                        .offset(x: 4, y: -4)
                }
            }
            Text(item.name)
                .font(.system(size: 10, weight: next ? .semibold : .regular))
                .foregroundStyle(next ? .mint : .white.opacity(0.86))
                .lineLimit(1)
                .frame(width: 98)
            Text(next ? L10n.text("下一件") : " ")
                .font(.system(size: 9, weight: .semibold)).foregroundStyle(.mint)
        }
    }
}

private struct ItemBuildOverlayView: View {
    let build: ItemBuild
    let ownedItemIDs: [Int]
    let opacity: Double

    var body: some View {
        let nextID = ItemBuildRecommendation.nextItem(in: build, ownedItemIDs: ownedItemIDs)?.id
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(L10n.text("推荐出装")).font(.system(size: 13, weight: .bold))
                Spacer()
                Text(L10n.text("胜率 %.1f%%", build.winRate))
                    .font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.mint)
                Color.clear.frame(width: 22, height: 1)
            }
            HStack(spacing: 8) {
                ForEach(build.items) { item in
                    BuildItemCell(item: item, owned: ownedItemIDs.contains(item.id), next: item.id == nextID)
                }
            }
            Text(L10n.text("OP.GG · 选用率 %.1f%% · %d 场", build.pickRate, build.games))
                .font(.system(size: 9)).foregroundStyle(.white.opacity(0.55))
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .frame(width: 342)
        .background(Color.black.opacity(0.88 * opacity), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.13), lineWidth: 1))
        .preferredColorScheme(.dark)
    }
}

private struct ItemBuildOverlayControlView: View {
    let collapsed: Bool
    let opacity: Double
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            Image(systemName: collapsed ? "shippingbox.fill" : "chevron.up")
                .font(.system(size: 11, weight: .bold))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.88 * opacity), in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.92))
        .help(L10n.text(collapsed ? "显示推荐出装" : "隐藏推荐出装"))
        .accessibilityLabel(L10n.text(collapsed ? "显示推荐出装" : "隐藏推荐出装"))
        .preferredColorScheme(.dark)
    }
}

@MainActor final class ItemBuildOverlayController {
    private var panel: ItemBuildPanel?
    private var controlPanel: ItemBuildPanel?
    private var signature = ""
    private var controlSignature = ""
    private var collapsed = false
    private var wasEnabled = true

    func update(model: OverlayModel, guide: GuideStore, recognition: AutoRecognition,
                calibration: SkillCalibration, game: GameSurface?) {
        guard model.itemBuildEnabled else {
            wasEnabled = false
            hide()
            return
        }
        if !wasEnabled {
            wasEnabled = true
            collapsed = false
            signature = ""
            controlSignature = ""
        }
        guard !calibration.active,
              recognition.cardHints.isEmpty, recognition.detectedChampion == guide.championKey,
              let build = ItemBuildRecommendation.choose(from: guide.itemBuilds, ownedItemIDs: recognition.ownedItemIDs),
              let game, game.foreground else {
            hide()
            return
        }
        let panel = self.panel ?? makePanel()
        let nextSignature = build.items.map { String($0.id) }.joined(separator: ",")
            + ":\(recognition.ownedItemIDs.sorted())"
            + ":\(LanguageSettings.shared.selection.rawValue):\(Int(model.opacity * 100))"
        if signature != nextSignature {
            signature = nextSignature
            panel.contentView = NSHostingView(rootView: ItemBuildOverlayView(
                build: build, ownedItemIDs: recognition.ownedItemIDs, opacity: model.opacity
            ))
        }
        let size = NSSize(width: 342, height: 132)
        let bounds = game.placementBounds
        let frame = NSRect(x: bounds.minX + 18, y: bounds.maxY - size.height - 82,
                           width: size.width, height: size.height)
        let level = NSWindow.Level(rawValue: max(Int(CGShieldingWindowLevel()) + 1, game.layer + 1))
        panel.level = level
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        panel.alphaValue = model.opacity
        if collapsed { panel.orderOut(nil) }
        else { panel.orderFrontRegardless() }

        let control = controlPanel ?? makeControlPanel()
        let nextControlSignature = "\(collapsed):\(LanguageSettings.shared.selection.rawValue):\(Int(model.opacity * 100))"
        if controlSignature != nextControlSignature {
            controlSignature = nextControlSignature
            control.contentView = NSHostingView(rootView: ItemBuildOverlayControlView(
                collapsed: collapsed, opacity: model.opacity,
                toggle: { [weak self] in self?.toggleCollapsed() }
            ))
        }
        let controlSize = NSSize(width: 26, height: 26)
        let controlFrame = NSRect(
            x: collapsed ? frame.minX : frame.maxX - controlSize.width - 8,
            y: frame.maxY - controlSize.height - 7,
            width: controlSize.width, height: controlSize.height
        )
        control.level = NSWindow.Level(rawValue: level.rawValue + 1)
        if control.frame != controlFrame { control.setFrame(controlFrame, display: true) }
        control.alphaValue = model.opacity
        control.orderFrontRegardless()
    }

    func hide() { panel?.orderOut(nil); controlPanel?.orderOut(nil) }

    private func toggleCollapsed() {
        collapsed.toggle()
        controlSignature = ""
    }

    private func makePanel() -> ItemBuildPanel {
        let panel = ItemBuildPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.isFloatingPanel = true; panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true; panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .canJoinAllApplications]
        panel.title = L10n.text("Wexi LoL 推荐出装")
        self.panel = panel
        return panel
    }

    private func makeControlPanel() -> ItemBuildPanel {
        let panel = ItemBuildPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.isFloatingPanel = true; panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = false; panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .canJoinAllApplications]
        panel.title = L10n.text("Wexi LoL 推荐出装")
        self.controlPanel = panel
        return panel
    }
}
