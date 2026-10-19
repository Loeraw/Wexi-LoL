import AppKit
import SwiftUI
import RiftCore

private final class LobbyScoutPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor private func localizedRankTier(_ tier: String) -> String {
    guard LanguageSettings.shared.selection == .chinese else { return L10n.text(tier) }
    return [
        "IRON": "黑铁", "BRONZE": "青铜", "SILVER": "白银", "GOLD": "黄金",
        "PLATINUM": "铂金", "EMERALD": "翡翠", "DIAMOND": "钻石",
        "MASTER": "大师", "GRANDMASTER": "宗师", "CHALLENGER": "王者"
    ][tier] ?? tier
}

private struct LobbyPlayerView: View {
    let row: LobbyPlayerRow

    var body: some View {
        HStack(spacing: 7) {
            Text(row.champion).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.68))
                .lineLimit(1).frame(width: 62, alignment: .leading)
            Text(row.riotID).font(.system(size: 11, weight: .medium)).lineLimit(1)
                .frame(width: 126, alignment: .leading)
            if let profile = row.profile {
                Text(rank(profile)).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                    .frame(width: 86, alignment: .leading)
                Text(profile.winRate.map { String(format: "%.0f%%", $0) } ?? "—")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(rateColor(profile.winRate)).frame(width: 36, alignment: .trailing)
                recent(profile.recent)
                if profile.isStale() {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 8)).foregroundStyle(.orange)
                        .help(L10n.text("OP.GG 资料可能已过期"))
                        .accessibilityLabel(L10n.text("OP.GG 资料可能已过期"))
                }
            } else if row.failed {
                Text(L10n.text("无公开数据")).font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
            } else {
                ProgressView().controlSize(.mini)
                Text(L10n.text("读取中…")).font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
            }
        }
        .frame(height: 27)
    }

    private func rank(_ profile: SummonerProfile) -> String {
        guard profile.tier != "UNRANKED" else { return L10n.text("未定级") }
        let parts = profile.tier.split(separator: " ")
        let tier = parts.first.map { localizedRankTier(String($0)) } ?? profile.tier
        let division = parts.dropFirst().joined(separator: " ")
        let lp = profile.leaguePoints.map { " · \($0) LP" } ?? ""
        return tier + (division.isEmpty ? "" : " \(division)") + lp
    }

    private func rateColor(_ rate: Double?) -> Color {
        guard let rate else { return .secondary }
        if rate >= 55 { return .mint }
        if rate < 48 { return .red.opacity(0.9) }
        return .white.opacity(0.82)
    }

    @ViewBuilder private func recent(_ values: [RecentMatchResult]) -> some View {
        HStack(spacing: 3) {
            ForEach(Array(values.prefix(5).enumerated()), id: \.offset) { _, value in
                Text(value == .win ? "W" : value == .loss ? "L" : "–")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 14, height: 14)
                    .background(value == .win ? Color.green.opacity(0.8) : value == .loss ? Color.red.opacity(0.8) : Color.gray.opacity(0.7), in: RoundedRectangle(cornerRadius: 3))
            }
            if values.isEmpty { Text("—").font(.system(size: 10)).foregroundStyle(.secondary) }
        }
        .frame(width: 86, alignment: .leading)
    }
}

private struct LobbyTeamView: View {
    let title: String
    let color: Color
    let rows: [LobbyPlayerRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(title).font(.system(size: 11, weight: .bold)).foregroundStyle(color)
                Spacer()
                Text(L10n.text("段位 · 赛季胜率 · 最近战绩"))
                    .font(.system(size: 9)).foregroundStyle(.secondary)
            }
            ForEach(rows) { LobbyPlayerView(row: $0) }
        }
        .frame(width: 410)
    }
}

private struct LobbyScoutView: View {
    let rows: [LobbyPlayerRow]
    let status: String
    let opacity: Double
    let collapsed: Bool
    let toggle: () -> Void

    var body: some View {
        if collapsed {
            Button(action: toggle) {
                Label(L10n.text("显示玩家资料"), systemImage: "person.2.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.90 * opacity), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.16), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.9))
            .preferredColorScheme(.dark)
        } else {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.text("当前对局玩家")).font(.system(size: 14, weight: .bold))
                Text(L10n.text("OP.GG · 全球")).font(.system(size: 9)).foregroundStyle(.secondary)
                Spacer()
                Text(status).font(.system(size: 9)).foregroundStyle(.secondary)
                Button(action: toggle) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold)).frame(width: 22, height: 18)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain).help(L10n.text("隐藏玩家资料"))
            }
            HStack(alignment: .top, spacing: 16) {
                LobbyTeamView(title: L10n.text("蓝方"), color: .cyan,
                              rows: rows.filter { $0.team == "ORDER" })
                Divider().frame(height: 150)
                LobbyTeamView(title: L10n.text("红方"), color: .red.opacity(0.9),
                              rows: rows.filter { $0.team != "ORDER" })
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(width: 866, height: 190)
        .foregroundStyle(.white.opacity(0.92))
        .background(Color.black.opacity(0.90 * opacity), in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.white.opacity(0.14), lineWidth: 1))
        .preferredColorScheme(.dark)
        }
    }
}

private struct InGamePlayerBadge: View {
    let row: LobbyPlayerRow
    let showsTopChampions: Bool
    let championNames: [String: String]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let profile = row.profile {
                HStack(spacing: 5) {
                    Text(shortRank(profile))
                    Text(profile.winRate.map { String(format: "%.0f%%", $0) } ?? "—")
                        .foregroundStyle(rateColor(profile.winRate))
                    if profile.isStale() {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9)).foregroundStyle(.orange)
                            .help(L10n.text("OP.GG 资料可能已过期"))
                            .accessibilityLabel(L10n.text("OP.GG 资料可能已过期"))
                    }
                }
                .font(.system(size: 13, weight: .bold, design: .rounded))
                HStack(spacing: 5) {
                    ForEach(Array(profile.recent.prefix(5).enumerated()), id: \.offset) { _, value in
                        Text(value == .win ? "W" : value == .loss ? "L" : "–")
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .foregroundStyle(value == .win ? Color.green : value == .loss ? Color.red : Color.gray)
                    }
                    if profile.recent.isEmpty { Text("—").foregroundStyle(.secondary) }
                }
                if showsTopChampions, !profile.topChampions.isEmpty {
                    HStack(spacing: 5) {
                        ForEach(Array(profile.topChampions.prefix(3).enumerated()), id: \.offset) { _, champion in
                            Text("\(championNames[champion.key] ?? champion.name) \(Int(champion.usageRate.rounded()))%")
                                .lineLimit(1)
                                .minimumScaleFactor(0.55)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.cyan.opacity(0.92))
                }
            } else if row.failed {
                Text(L10n.text("无公开数据")).font(.system(size: 12, weight: .medium))
            } else {
                Text(L10n.text("读取中…")).font(.system(size: 12, weight: .medium))
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .frame(width: showsTopChampions ? 196 : 164,
               height: showsTopChampions ? 68 : 50, alignment: .leading)
        .foregroundStyle(.white.opacity(0.94))
        .background(Color.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.18), lineWidth: 1))
    }

    private func shortRank(_ profile: SummonerProfile) -> String {
        guard profile.tier != "UNRANKED" else { return L10n.text("未定级") }
        let parts = profile.tier.split(separator: " ")
        let tier = parts.first.map { localizedRankTier(String($0)) } ?? profile.tier
        let division = parts.dropFirst().joined(separator: " ")
        return tier + (division.isEmpty ? "" : " \(division)")
    }

    private func rateColor(_ rate: Double?) -> Color {
        guard let rate else { return .secondary }
        if rate >= 55 { return .green }
        if rate < 48 { return .red }
        return .white.opacity(0.9)
    }
}

private struct InGameScoutView: View {
    let rows: [LobbyPlayerRow]
    let anchors: [String: HintAnchor]
    let opacity: Double
    let showsTopChampions: Bool
    let championNames: [String: String]
    let scale: CGFloat

    var body: some View {
        GeometryReader { proxy in
            ForEach(rows) { row in
                InGamePlayerBadge(row: row, showsTopChampions: showsTopChampions,
                                  championNames: championNames)
                    .opacity(opacity)
                    .scaleEffect(scale)
                    .position(position(for: row, size: proxy.size))
            }
        }
        .preferredColorScheme(.dark)
    }

    private func position(for row: LobbyPlayerRow, size: CGSize) -> CGPoint {
        let teamRows = rows.filter { $0.team == row.team }
        let index = teamRows.firstIndex(where: { $0.riotID == row.riotID }) ?? 0
        // OCR supplies the real row center. Keep the measured 2560×1440 values
        // only as a fallback for frames where a name is temporarily missed.
        let fallbackVisionY = 0.682 - Double(index) * 0.070
        let visionY = anchors[row.riotID]?.y ?? fallbackVisionY
        // The scoreboard remains centered in a 16:9 content area on ultrawide
        // displays, so side cards follow that area rather than the screen edge.
        let normalizedX = AdaptiveOverlayLayout.contentX(
            row.team == "ORDER" ? 0.105 : 0.895,
            width: Double(size.width), height: Double(size.height)
        )
        let badgeWidth: CGFloat = (showsTopChampions ? 196 : 164) * scale
        let safeX = row.team == "ORDER"
            ? max(CGFloat(normalizedX) * size.width, badgeWidth / 2 + 10 * scale)
            : min(CGFloat(normalizedX) * size.width, size.width - badgeWidth / 2 - 10 * scale)
        return CGPoint(x: safeX, y: size.height * (1 - visionY))
    }
}

private struct LoadingScoutCardsView: View {
    let rows: [LobbyPlayerRow]
    let anchors: [String: HintAnchor]
    let opacity: Double
    let scale: CGFloat

    var body: some View {
        GeometryReader { proxy in
            ForEach(rows) { row in
                InGamePlayerBadge(row: row, showsTopChampions: false, championNames: [:])
                    .opacity(opacity)
                    .scaleEffect(scale)
                    .position(position(for: row, size: proxy.size))
            }
        }
        .preferredColorScheme(.dark)
    }

    private func position(for row: LobbyPlayerRow, size: CGSize) -> CGPoint {
        let teamRows = rows.filter { $0.team == row.team }
        let index = teamRows.firstIndex(where: { $0.riotID == row.riotID }) ?? 0
        // Name OCR gives the actual card column. When it is unavailable, map
        // the old five-column layout into the centered 16:9 content region.
        let fallbackX = AdaptiveOverlayLayout.contentX(
            0.190 + Double(index) * 0.154,
            width: Double(size.width), height: Double(size.height)
        )
        let x = anchors[row.riotID]?.x ?? fallbackX
        // Loading screen card rows occupy matching positions in the upper and
        // lower halves. Both badges sit at the same relative height inside the
        // portrait rather than letting the Dock-trimmed frame lift row two.
        let fallbackY = row.team == "ORDER" ? 0.405 : 0.889
        // Player names sit below the useful part of each portrait. Move the
        // badge slightly above the recognized baseline so the name stays clear.
        let y = anchors[row.riotID].map { 1 - min(0.96, $0.y + 0.055) } ?? fallbackY
        return CGPoint(x: size.width * x, y: size.height * y)
    }
}

private struct LoadingScoutControlView: View {
    let collapsed: Bool
    let opacity: Double
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            Label(L10n.text(collapsed ? "显示玩家资料" : "隐藏玩家资料"),
                  systemImage: collapsed ? "person.2.fill" : "chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.84 * opacity), in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.16), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.94))
        .preferredColorScheme(.dark)
    }
}

@MainActor final class LobbyScoutOverlayController {
    private var panel: LobbyScoutPanel?
    private var controlPanel: LobbyScoutPanel?
    private var signature = ""
    private var controlSignature = ""
    private var collapsed = false
    private var matchKey = ""
    private var loadingAnchors: [String: HintAnchor] = [:]
    private var scoreboardAnchors: [String: HintAnchor] = [:]

    func update(model: OverlayModel, store: LobbyScoutStore, guide: GuideStore,
                recognition: AutoRecognition, game: GameSurface?) {
        guard model.playerScoutEnabled, !store.rows.isEmpty, let game, game.foreground else {
            hide(); return
        }
        let showLoading = store.isLoadingScreen
        // Player profiles and their layout are cached during loading. In game,
        // the physical Tab key is the only visibility gate: OCR misses must
        // never hide and re-show the cached panel while Tab remains held.
        let tabIsHeld = CGEventSource.keyState(.combinedSessionState, key: 48)
        let showScoreboard = store.isInGame && tabIsHeld
        guard showLoading || showScoreboard else { hide(); return }
        let currentMatchKey = store.rows.map { "\($0.team):\($0.riotID)" }.sorted().joined(separator: "|")
        if currentMatchKey != matchKey {
            matchKey = currentMatchKey; collapsed = false
            loadingAnchors = [:]; scoreboardAnchors = [:]
        }
        let recognizedAnchors = PlayerUIAnchorRecognition.anchors(
            lines: recognition.scoreboardLines,
            riotIDs: store.rows.map(\.riotID)
        )
        if showScoreboard, recognition.isScoreboardVisible {
            scoreboardAnchors.merge(recognizedAnchors) { _, new in new }
        }
        else if showLoading { loadingAnchors.merge(recognizedAnchors) { _, new in new } }
        let panel = self.panel ?? makePanel()
        let scale = CGFloat(AdaptiveOverlayLayout.scale(
            width: Double(game.frame.width), height: Double(game.frame.height)
        ))
        let championNames = Dictionary(uniqueKeysWithValues: guide.champions.map { ($0.id, $0.name) })
        let activeAnchors = showScoreboard ? scoreboardAnchors : loadingAnchors
        let nextSignature = "\(store.rows):\(store.status):\(collapsed):\(showScoreboard):\(store.showsRankedChampionUsage):\(championNames):\(activeAnchors):\(scale):\(LanguageSettings.shared.selection.rawValue):\(Int(model.opacity * 100))"
        if signature != nextSignature {
            signature = nextSignature
            if showScoreboard {
                panel.contentView = NSHostingView(rootView: InGameScoutView(
                    rows: store.rows, anchors: scoreboardAnchors, opacity: model.opacity,
                    showsTopChampions: store.showsRankedChampionUsage,
                    championNames: championNames, scale: scale
                ))
            } else {
                panel.contentView = NSHostingView(rootView: LoadingScoutCardsView(
                    rows: store.rows, anchors: loadingAnchors,
                    opacity: model.opacity, scale: scale
                ))
            }
        }
        // Loading cards, like the in-game scoreboard, are laid out against the
        // full game window. macOS visibleFrame excludes the Dock and shifts the
        // lower row upward by roughly 90 points.
        let bounds = game.frame
        let level = NSWindow.Level(rawValue: max(Int(CGShieldingWindowLevel()) + 2, game.layer + 2))
        let frame = NSRect(origin: bounds.origin, size: bounds.size)
        panel.level = level
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        panel.alphaValue = model.opacity
        panel.ignoresMouseEvents = true
        if showScoreboard || !collapsed { panel.orderFrontRegardless() }
        else { panel.orderOut(nil) }

        if showLoading {
            let control = controlPanel ?? makeControlPanel()
            let nextControlSignature = "\(collapsed):\(LanguageSettings.shared.selection.rawValue):\(Int(model.opacity * 100))"
            if controlSignature != nextControlSignature {
                controlSignature = nextControlSignature
                control.contentView = NSHostingView(rootView: LoadingScoutControlView(
                    collapsed: collapsed, opacity: model.opacity,
                    toggle: { [weak self] in self?.toggle() }
                ))
            }
            let controlFrame = NSRect(x: bounds.maxX - 158, y: bounds.maxY - 46, width: 140, height: 32)
            control.level = NSWindow.Level(rawValue: level.rawValue + 1)
            if control.frame != controlFrame { control.setFrame(controlFrame, display: true) }
            control.alphaValue = model.opacity
            control.orderFrontRegardless()
        } else {
            controlPanel?.orderOut(nil)
        }
    }

    func hide() { panel?.orderOut(nil); controlPanel?.orderOut(nil) }

    private func toggle() {
        collapsed.toggle()
        signature = ""; controlSignature = ""
    }

    private func makePanel() -> LobbyScoutPanel {
        let panel = LobbyScoutPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.isFloatingPanel = true; panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true; panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .canJoinAllApplications]
        panel.title = L10n.text("Wexi LoL 当前对局玩家")
        self.panel = panel
        return panel
    }

    private func makeControlPanel() -> LobbyScoutPanel {
        let panel = LobbyScoutPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.isFloatingPanel = true; panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = false; panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .canJoinAllApplications]
        panel.title = L10n.text("Wexi LoL 当前对局玩家")
        self.controlPanel = panel
        return panel
    }
}
