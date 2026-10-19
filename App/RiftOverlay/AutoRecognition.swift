import AppKit
import ScreenCaptureKit
import RiftCore

enum GameWindow {
    static func isGame(name: String?, bundle: String?) -> Bool {
        let name = name?.lowercased() ?? "", bundle = bundle?.lowercased() ?? ""
        if !bundle.isEmpty { return bundle == "com.riotgames.leagueoflegends.gameclient" }
        return name == "leagueoflegends"
    }
    @MainActor static var frontmostPID: pid_t? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              isGame(name: app.localizedName, bundle: app.bundleIdentifier) else { return nil }
        return app.processIdentifier
    }
}

struct ScannedHints: Sendable {
    let cards: [RecognizedCard]
    let skillAnchors: [String: HintAnchor]
    let summary: String
    var exactTriple = false
    var choiceVisible = false
    var windowFrame: CGRect? = nil
    var windowLayer: Int = 0
    var relicScan: HealthRelicScan? = nil
    var scoreboardLines: [RecognizedLine] = []
}

actor CardScanner {
    private var cachedWindow: SCWindow?
    private var cachedPID: pid_t?
    private var windowUpdatedAt = Date.distantPast
    private var fallbackAt = Date.distantPast
    private var relicProbeAt = Date.distantPast

    @available(macOS 14.0, *)
    func scan(pid: pid_t, catalog: [AugmentRating], recognitionLanguages: [String],
              scanSkills: Bool, scanRelics: Bool) async throws -> ScannedHints {
        let started = Date()
        let window: SCWindow
        if let cachedWindow, cachedPID == pid, Date().timeIntervalSince(windowUpdatedAt) < 1 {
            window = cachedWindow
        } else {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            // Capture only the actual game process, never the desktop or this overlay.
            let candidates = content.windows.filter { $0.owningApplication?.processID == pid && $0.frame.width >= 640 && $0.frame.height >= 360 }
            // Metal full-screen games can publish an equally large helper window.
            // Prefer the actual game window title over a largest-area-only tie.
            let named = candidates.filter { $0.title == "League of Legends (TM) Client" }
            guard let selected = (named.isEmpty ? candidates : named).max(by: {
                if $0.isOnScreen != $1.isOnScreen { return !$0.isOnScreen }
                if $0.frame.size != $1.frame.size { return $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
                return $0.windowID < $1.windowID
            }) else { return ScannedHints(cards: [], skillAnchors: [:], summary: "未找到可捕获的游戏窗口") }
            window = selected
            cachedWindow = selected; cachedPID = pid; windowUpdatedAt = Date()
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        let scale = min(2.0, 2560.0 / window.frame.width)
        config.width = Int(window.frame.width * scale)
        config.height = Int(window.frame.height * scale)
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        let image: CGImage
        do { image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) }
        catch { cachedWindow = nil; throw error }
        try Task.checkCancellation()
        var lines = try GameFrameRecognition.fastCardTitleLines(image: image, catalog: catalog,
                                                                 recognitionLanguages: recognitionLanguages)
        var cards = AugmentRecognition.visibleCards(lines: lines, catalog: catalog)
        var usedFallback = false
        if !catalog.isEmpty && cards.count < 3 && Date().timeIntervalSince(fallbackAt) >= 1 {
            fallbackAt = Date(); usedFallback = true
            lines += try GameFrameRecognition.lines(image: image, catalog: catalog, recognitionLanguages: recognitionLanguages)
                + GameFrameRecognition.cardTitleLines(image: image, catalog: catalog, recognitionLanguages: recognitionLanguages)
            cards = AugmentRecognition.visibleCards(lines: lines, catalog: catalog)
        }
        let aspect = Double(image.width) / Double(image.height)
        let savedAspect = UserDefaults.standard.double(forKey: "skillPlusAspect.v1")
        let saved = UserDefaults.standard.data(forKey: "skillPlusAnchors.v1").flatMap { try? JSONDecoder().decode([String: HintAnchor].self, from: $0) }
        let calibrated = savedAspect > 0 && abs(aspect / savedAspect - 1) < 0.03 &&
            ["Q", "W", "E", "R"].allSatisfy { key in saved?[key].map { (0...1).contains($0.x) && (0...1).contains($0.y) } == true }
        let hud = scanSkills && !calibrated ? try GameFrameRecognition.skillLines(image: image) : []
        let anchors = SkillHUDRecognition.anchors(lines: hud, imageAspect: aspect)
        let exact = AugmentRecognition.isExactTriple(cards, lines: lines, catalog: catalog)
        let choiceVisible = !cards.isEmpty || AugmentRecognition.hasChoiceEvidence(lines: lines, catalog: catalog)
        // macOS does not reliably expose the physical Tab key state while a
        // Metal game owns the keyboard. Probe the scoreboard itself at a low
        // cadence instead, and pause this extra OCR whenever augment cards are
        // visible so augment recognition keeps priority.
        let shouldProbeRelics = scanRelics && cards.isEmpty && Date().timeIntervalSince(relicProbeAt) >= 0.35
        if shouldProbeRelics { relicProbeAt = Date() }
        let scoreboardLines = shouldProbeRelics ? try GameFrameRecognition.scoreboardLines(
            image: image, recognitionLanguages: recognitionLanguages
        ) : []
        let relicScan = shouldProbeRelics ? HealthRelicRecognition.scan(lines: scoreboardLines) : nil
        let relicSummary = relicScan.map { " · 计分板 \($0.scoreboardVisible ? "已读取" : "未展开") · 血包 \($0.readings.count)" } ?? ""
        let summary = "\(usedFallback ? "兼容扫描" : "标题快速扫描") · 卡片 \(cards.count)/3 · \(exact ? "本帧确认" : "等待确认")\(relicSummary) · \(String(format: "%.2f", Date().timeIntervalSince(started))) 秒"
        return ScannedHints(cards: cards, skillAnchors: anchors, summary: summary, exactTriple: exact,
                            choiceVisible: choiceVisible,
                            windowFrame: window.frame, windowLayer: window.windowLayer, relicScan: relicScan,
                            scoreboardLines: scoreboardLines)
    }
}

@MainActor final class AutoRecognition: ObservableObject {
    @Published var championStatus = "等待进入对局…"
    @Published var cardStatus = "自动识别需要屏幕录制权限"
    @Published var hasScreenPermission = false
    @Published var detectedChampion: String?
    @Published var detectedLevel: Int?
    @Published var skillRanks: [String: Int] = [:]
    @Published var ownedItemIDs: [Int] = []
    @Published var cardHints: [RecognizedCard] = []
    @Published var skillAnchors: [String: HintAnchor] = [:]
    @Published var scanSummary = "尚未读取游戏画面"
    @Published private(set) var scoreboardVisible = false
    @Published private(set) var scoreboardLines: [RecognizedLine] = []
    @Published private(set) var scoreboardRevision = 0
    private var capturedFrame: CGRect?
    private var capturedPID: pid_t?
    private var capturedLayer = 0
    var capturedGameSurface: GameSurface? {
        guard Date().timeIntervalSince(frameUpdatedAt) < 2, let frame = capturedFrame,
              let pid = capturedPID, GameWindow.frontmostPID == pid else { return nil }
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        return GameSurface(frame: CGRect(x: frame.minX, y: top - frame.maxY, width: frame.width, height: frame.height),
                           layer: capturedLayer, foreground: true)
    }
    private(set) var playerUpdatedAt = Date.distantPast
    private(set) var frameUpdatedAt = Date.distantPast
    private weak var guide: GuideStore?
    private weak var objectiveTimers: ObjectiveTimerStore?
    private let live = LiveClient()
    private let scanner = CardScanner()
    private var championTask: Task<Void, Never>?
    private var cardTask: Task<Void, Never>?
    private var stable = StableCards()
    private var mode: String?
    private var revision = 0
    private var wasGameForeground = false
    private var scoreboardUpdatedAt = Date.distantPast

    var isAramMode: Bool { mode == "ARAM" || mode == "KIWI" }
    var isScoreboardVisible: Bool {
        scoreboardVisible && Date().timeIntervalSince(scoreboardUpdatedAt) < 0.9
    }

    var recommendedSkill: String? {
        guard let guide, !guide.loading, detectedChampion == guide.championKey,
              Date().timeIntervalSince(playerUpdatedAt) < 2.5,
              let level = detectedLevel, let skills = guide.skills else { return nil }
        let specialRanks = ["udyr", "jayce", "elise", "nidalee", "karma", "aphelios"]
        return SkillRecommendation.next(level: level, ranks: skillRanks, order: skills.order,
                                        priority: skills.priority, standardRanks: !specialRanks.contains(guide.championKey))
    }
    var skillStatus: String {
        guard let level = detectedLevel else { return "等待技能等级数据" }
        guard ["Q", "W", "E", "R"].allSatisfy({ skillRanks[$0] != nil }) else { return "接口未提供完整技能等级" }
        let spent = ["Q", "W", "E", "R"].reduce(0) { $0 + (skillRanks[$1] ?? 0) }
        guard spent < level else { return "当前技能点已用完 · 不显示加点提示" }
        return "还有 \(level - spent) 点可加 · \(recommendedSkill.map { "推荐 " + $0 } ?? "暂无可用攻略建议")"
    }
    func start(guide: GuideStore, objectiveTimers: ObjectiveTimerStore) {
        self.guide = guide
        self.objectiveTimers = objectiveTimers
        championTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                do {
                    let result = try await self.live.champion()
                    guard !Task.isCancelled else { return }
                    if self.detectedChampion != result.key { self.resetCards() }
                    self.mode = result.mode
                    self.detectedChampion = result.key
                    self.detectedLevel = result.level
                    self.skillRanks = result.ranks
                    self.ownedItemIDs = result.itemIDs
                    self.playerUpdatedAt = Date()
                    self.championStatus = "已识别 \(result.key) · 等级 \(result.level) · \(result.mode)"
                    let championChanged = guide.championKey != result.key
                    let detectedGuideMode = GuideMode.from(liveMode: result.mode)
                    let modeChanged = detectedGuideMode.map { guide.mode != $0 } ?? false
                    if championChanged {
                        self.resetCards()
                        guide.championKey = result.key
                    }
                    if let detectedGuideMode, modeChanged {
                        self.resetCards()
                        guide.mode = detectedGuideMode
                    } else if championChanged {
                        guide.load()
                    }
                } catch {
                    guard !Task.isCancelled else { return }
                    self.detectedChampion = nil; self.detectedLevel = nil; self.mode = nil
                    self.skillRanks = [:]; self.playerUpdatedAt = .distantPast
                    self.ownedItemIDs = []
                    self.championStatus = "等待对局；当前没有可用的本地对局数据。"
                    self.resetCards()
                }
                do { try await Task.sleep(nanoseconds: 600_000_000) } catch { return }
            }
        }
        cardTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.scanIfReady()
                do { try await Task.sleep(nanoseconds: GameWindow.frontmostPID == nil ? 500_000_000 : 100_000_000) } catch { return }
            }
        }
    }
    func resetCards() {
        revision += 1; stable = StableCards(); guide?.recognized = []
        cardHints = []; skillAnchors = [:]; frameUpdatedAt = .distantPast
        scoreboardVisible = false; scoreboardLines = []; scoreboardUpdatedAt = .distantPast
        scoreboardRevision += 1
    }
    func pauseForApplicationChange() {
        let foreground = GameWindow.frontmostPID != nil
        if wasGameForeground && !foreground { resetCards() }
        wasGameForeground = foreground
    }
    func requestPermission() {
        hasScreenPermission = CGRequestScreenCaptureAccess()
        cardStatus = hasScreenPermission ? "权限已开启，请切回 LoL" : "请在系统设置的「屏幕与系统音频录制」中开启 Wexi LoL，必要时重启应用。"
    }
    func openPermissionSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") { NSWorkspace.shared.open(url) }
    }
    private func scanIfReady() async {
        guard let guide else { return }
        hasScreenPermission = CGPreflightScreenCaptureAccess()
        guard #available(macOS 14.0, *) else { cardStatus = "画面识别需要 macOS 14 或更新版本"; resetCards(); return }
        guard hasScreenPermission else { cardStatus = "等待屏幕录制授权 · 只识别 LoL 窗口，不保存或上传画面"; resetCards(); return }
        guard let pid = GameWindow.frontmostPID else { cardStatus = "当前在游戏外，已暂停；下方保留最近一次游戏内检测结果"; resetCards(); return }
        // HUD localization is independent of mode, hero lookup and augment downloads.
        // Practice Tool can use the same skill guidance to test placement.
        let scanCards = (mode == "KIWI" || mode == "ARAM" || mode == "CHERRY") &&
            detectedChampion == guide.championKey && !guide.loading && !guide.augments.isEmpty
        let catalog = scanCards ? guide.augments : []
        let isAram = mode == "KIWI" || mode == "ARAM"
        let key = guide.championKey, version = revision, catalogDate = guide.fetchedAt
        do {
            cardStatus = "正在读取游戏画面…"
            let result = try await scanner.scan(pid: pid, catalog: catalog,
                                                recognitionLanguages: LanguageSettings.shared.gameLanguage.visionLanguages,
                                                scanSkills: recommendedSkill != nil,
                                                scanRelics: true)
            guard !Task.isCancelled, revision == version, GameWindow.frontmostPID == pid else { return }
            let validCards = scanCards && !guide.loading && guide.fetchedAt == catalogDate && guide.championKey == key
            let confirmed = stable.observe(validCards ? result.cards : [],
                                            choiceVisible: validCards && result.choiceVisible,
                                            exactTriple: validCards && result.exactTriple)
            guide.recognized = confirmed.map(\.id)
            cardHints = confirmed
            skillAnchors = result.skillAnchors
            capturedFrame = result.windowFrame; capturedLayer = result.windowLayer; capturedPID = pid
            frameUpdatedAt = Date()
            if let relicScan = result.relicScan {
                scoreboardVisible = relicScan.scoreboardVisible
                // Keep the OCR lines even when the Tab scoreboard is closed.
                // The loading-screen overlay uses current player names to
                // align each profile with its champion card.
                scoreboardLines = result.scoreboardLines
                scoreboardUpdatedAt = Date()
                scoreboardRevision += 1
                if isAram { objectiveTimers?.observeHealthRelicScan(relicScan) }
            }
            scanSummary = "\(Date().formatted(date: .omitted, time: .standard)) · " + result.summary
            cardStatus = !validCards ? "技能栏识别中；海克斯评级等待模式和攻略数据" : (confirmed.isEmpty ? "尚未确认海克斯卡片" : "已识别 \(confirmed.count) 张卡片，显示对应评级")
        } catch {
            guard !Task.isCancelled, revision == version else { return }
            resetCards()
            cardStatus = "无法读取 LoL 画面，请检查屏幕录制权限。"
            scanSummary = "画面读取失败：\((error as NSError).domain) / \((error as NSError).code)"
        }
    }
    func stop() { championTask?.cancel(); cardTask?.cancel(); resetCards() }
}
