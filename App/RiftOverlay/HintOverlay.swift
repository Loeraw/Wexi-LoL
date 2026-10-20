import AppKit
import SwiftUI
import RiftCore

@MainActor final class SkillCalibration: ObservableObject {
    @Published var active = false
    @Published var message = "技能＋优先自动定位；识别不到时可拖动校准一次。"
    @Published var anchors: [String: HintAnchor] = [:]
    private var saved: [String: HintAnchor] = [:]
    private var moved = Set<String>()
    private var savedAspect: Double?
    var currentAspect: Double?
    private let keys = ["Q", "W", "E", "R"]

    init() {
        let defaults = UserDefaults.standard
        if defaults.data(forKey: "skillPlusAnchors.v1") == nil,
           let previous = UserDefaults(suiteName: "dev.local.riftoverlay") {
            if let anchors = previous.data(forKey: "skillPlusAnchors.v1") {
                defaults.set(anchors, forKey: "skillPlusAnchors.v1")
            }
            if let aspect = previous.object(forKey: "skillPlusAspect.v1") {
                defaults.set(aspect, forKey: "skillPlusAspect.v1")
            }
        }
        if let data = UserDefaults.standard.data(forKey: "skillPlusAnchors.v1"),
           let values = try? JSONDecoder().decode([String: HintAnchor].self, from: data),
           keys.allSatisfy({ key in values[key].map { (0...1).contains($0.x) && (0...1).contains($0.y) } == true }) {
            saved = values; anchors = values
            savedAspect = UserDefaults.standard.object(forKey: "skillPlusAspect.v1") as? Double
            message = "已保存技能＋位置；更改游戏界面缩放后请重新校准。"
        }
    }
    func start() {
        anchors = saved.isEmpty ? Dictionary(uniqueKeysWithValues: keys.enumerated().map {
            ($0.element, HintAnchor(x: 0.43 + Double($0.offset) * 0.035, y: 0.14))
        }) : saved
        moved = []; active = true
        message = "切回游戏，将四个标记分别拖到 Q/W/E/R 的＋，然后按 ⌥⌘K 保存。"
    }
    func move(_ key: String, to point: HintAnchor) {
        guard active else { return }
        anchors[key] = point; moved.insert(key)
    }
    func finish() {
        guard active else { return }
        guard keys.allSatisfy({ moved.contains($0) }), let aspect = currentAspect else {
            message = "请先在游戏内分别拖动四个标记，再保存位置。"; return
        }
        saved = anchors; savedAspect = aspect
        UserDefaults.standard.set(try? JSONEncoder().encode(saved), forKey: "skillPlusAnchors.v1")
        UserDefaults.standard.set(aspect, forKey: "skillPlusAspect.v1")
        active = false; message = "已保存技能＋位置；更改游戏界面缩放后请重新校准。"
    }
    func cancel() { anchors = saved; active = false; message = "校准已取消。" }
    func anchor(for key: String, aspect: Double) -> HintAnchor? {
        guard let savedAspect, abs(aspect / savedAspect - 1) < 0.03 else { return nil }
        return saved[key]
    }
}

private final class HintPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct HintBadge: View {
    let text: String
    let calibration: Bool
    let scale: CGFloat
    var body: some View {
        Text(text).font(.system(size: (calibration ? 14 : 15) * scale, weight: .bold, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(calibration ? Color.white : Color(red: 0.4, green: 0.95, blue: 0.78))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 7 * scale))
            .overlay(RoundedRectangle(cornerRadius: 7 * scale).stroke(calibration ? .orange : .mint, lineWidth: 1.5))
            .padding(2 * scale)
    }
}

@MainActor final class HintOverlayController: NSObject, NSWindowDelegate {
    private var panels: [String: HintPanel] = [:]
    private var texts: [String: String] = [:]
    private var placementInProgress = false
    private weak var calibration: SkillCalibration?
    private var gameFrame: CGRect?
    private var retainedCards: [RecognizedCard] = []
    private var cardsLastSeenAt = Date.distantPast
    private let cardRetentionInterval: TimeInterval = 0.7

    func windowDidMove(_ notification: Notification) {
        guard !placementInProgress, let calibration, calibration.active,
              let window = notification.object as? HintPanel,
              let item = panels.first(where: { $0.value === window }), item.key.hasPrefix("cal-"),
              let gameFrame else { return }
        let point = HintAnchor(x: min(1, max(0, (window.frame.midX - gameFrame.minX) / gameFrame.width)),
                               y: min(1, max(0, (window.frame.midY - gameFrame.minY) / gameFrame.height)))
        calibration.move(String(item.key.dropFirst(4)), to: point)
    }
    func hideAll() { panels.values.forEach { $0.orderOut(nil) } }

    func update(model: OverlayModel, guide: GuideStore, recognition: AutoRecognition, calibration: SkillCalibration) {
        self.calibration = calibration
        guard let game = recognition.capturedGameSurface ?? GameSurface.current(), game.foreground else {
            hideAll(); gameFrame = nil; retainedCards = []; cardsLastSeenAt = .distantPast
            setStatus("等待游戏前台 · 提示已隐藏", model: model); return
        }
        gameFrame = game.frame
        let aspect = game.frame.width / game.frame.height
        calibration.currentAspect = aspect
        var shown = Set<String>()
        if calibration.active {
            for key in ["Q", "W", "E", "R"] {
                if let anchor = calibration.anchors[key] {
                    show(id: "cal-" + key, text: key + L10n.text(" ＋ 拖动"), anchor: anchor, offset: 0,
                         size: NSSize(width: 84, height: 30), game: game, calibration: true, opacity: 1,
                         scalePreference: model.overlayScale)
                    shown.insert("cal-" + key)
                }
            }
            setStatus(calibration.message, model: model)
        } else {
            let now = Date()
            let freshFrame = now.timeIntervalSince(recognition.frameUpdatedAt) < 2
            let cards: [RecognizedCard]
            if freshFrame, !recognition.cardHints.isEmpty {
                retainedCards = recognition.cardHints
                cardsLastSeenAt = now
                cards = recognition.cardHints
            } else if freshFrame, now.timeIntervalSince(cardsLastSeenAt) < cardRetentionInterval {
                // Vision occasionally misses a title for one or two frames. Keep
                // the already confirmed badges visible across that short gap.
                cards = retainedCards
            } else {
                retainedCards = []
                cards = []
            }
            // While cards are being chosen, avoid also drawing unrelated skill hints.
            if !cards.isEmpty {
                for card in cards {
                    guard let augment = guide.augments.first(where: { $0.id == card.id }) else { continue }
                    let id = "card-\(card.id)"
                    let hasRates = augment.pickRate != nil || augment.winRate != nil
                    show(id: id, text: augmentHintText(augment), anchor: card.anchor, offset: 0,
                         size: NSSize(width: hasRates ? 248 : 42, height: 28),
                         game: game, calibration: false, opacity: model.opacity, scalePreference: model.overlayScale)
                    shown.insert(id)
                }
            } else if let skill = recognition.recommendedSkill {
                let anchor = calibration.anchor(for: skill, aspect: aspect) ?? (freshFrame ? recognition.skillAnchors[skill] : nil)
                if let anchor {
                    show(id: "skill", text: L10n.text("推荐 %@ ↓", skill), anchor: anchor, offset: 27,
                         size: NSSize(width: 90, height: 28), game: game, calibration: false,
                         opacity: model.opacity, scalePreference: model.overlayScale)
                    shown.insert("skill")
                }
            }
            if !shown.isEmpty { setStatus("正在游戏对应位置显示提示", model: model) }
            else if recognition.recommendedSkill != nil { setStatus("有技能点可用；等待定位＋，可用下方按钮校准位置。", model: model) }
            else { setStatus("等待升级或海克斯选择 · 平时不显示任何面板", model: model) }
        }
        for (id, panel) in panels where !shown.contains(id) { panel.orderOut(nil) }
        // Discard old card windows rather than accumulating a window per augment.
        for id in Array(panels.keys) where id.hasPrefix("card-") && !shown.contains(id) {
            panels.removeValue(forKey: id)?.close(); texts.removeValue(forKey: id)
        }
    }
    private func setStatus(_ text: String, model: OverlayModel) {
        if model.overlayStatus != text { model.overlayStatus = text }
    }
    private func augmentHintText(_ augment: AugmentRating) -> String {
        var parts = [augment.tierLabel]
        if let pickRate = augment.pickRate {
            parts.append(L10n.text("选用率 %.1f%%", pickRate))
        }
        if let winRate = augment.winRate {
            parts.append(L10n.text("胜率 %.1f%%", winRate))
        }
        return parts.joined(separator: " · ")
    }
    private func show(id: String, text: String, anchor: HintAnchor, offset: CGFloat, size: NSSize,
                      game: GameSurface, calibration: Bool, opacity: Double, scalePreference: Double) {
        let scale = CGFloat(AdaptiveOverlayLayout.scale(
            width: Double(game.frame.width), height: Double(game.frame.height), preference: scalePreference
        ))
        let displaySize = NSSize(width: size.width * scale, height: size.height * scale)
        let displayOffset = offset * scale
        let panel: HintPanel
        if let existing = panels[id] { panel = existing }
        else {
            panel = HintPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
            panel.isFloatingPanel = true; panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
            panel.animationBehavior = .none
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .canJoinAllApplications]
            panel.delegate = self; panels[id] = panel
        }
        panel.title = L10n.text(calibration ? "校准技能＋" : "Wexi LoL 游戏提示")
        panel.ignoresMouseEvents = !calibration
        panel.isMovableByWindowBackground = calibration
        panel.alphaValue = opacity
        let level = NSWindow.Level(rawValue: max(Int(CGShieldingWindowLevel()) + 1, game.layer + 1))
        if panel.level != level { panel.level = level }
        let contentSignature = "\(text)|\(scale)"
        if texts[id] != contentSignature {
            panel.contentView = NSHostingView(rootView: HintBadge(
                text: text, calibration: calibration, scale: scale
            ))
            texts[id] = contentSignature
        }
        let frame = NSRect(x: min(game.frame.maxX - displaySize.width, max(game.frame.minX, game.frame.minX + anchor.x * game.frame.width - displaySize.width / 2)),
                           y: min(game.frame.maxY - displaySize.height, max(game.frame.minY, game.frame.minY + anchor.y * game.frame.height + displayOffset - displaySize.height / 2)),
                           width: displaySize.width, height: displaySize.height)
        if panel.frame != frame {
            placementInProgress = true; panel.setFrame(frame, display: true); placementInProgress = false
        }
        panel.orderFrontRegardless()
    }
}
