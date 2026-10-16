import Foundation
import RiftCore

@MainActor final class ObjectiveTimerStore: ObservableObject {
    @Published var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: Self.enabledKey) }
    }
    @Published private(set) var mode = ""
    @Published private(set) var rows: [ObjectiveCountdown] = []
    @Published private var statusKey = "等待对局数据…"
    @Published private var statusCount: Int?

    private static let enabledKey = "objectiveTimersEnabled.v1"
    private let live = LiveClient()
    private var task: Task<Void, Never>?
    private var sampledGameTime: Double?
    private var sampledAt = Date.distantPast
    private var events: [LiveGameEvent] = []
    private var playerTeams: [String: String] = [:]
    private var relicDeadlines: [Int: Double] = [:]
    private var pendingRelicReadings: [HealthRelicTimerReading]?
    private var pendingRelicConfirmations = 0
    private var lastRelicSync: Date?

    init() {
        let defaults = UserDefaults.standard
        enabled = defaults.object(forKey: Self.enabledKey) == nil ? true : defaults.bool(forKey: Self.enabledKey)
    }

    var isAram: Bool { mode == "ARAM" || mode == "KIWI" }
    var status: String {
        if let statusCount { return L10n.text(statusKey, statusCount) }
        return L10n.text(statusKey)
    }
    var modeLabel: String {
        if isAram { return L10n.text("大乱斗") }
        if mode == "CLASSIC" { return L10n.text("召唤师峡谷") }
        return L10n.text("等待对局")
    }

    func start() {
        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.poll()
                do { try await Task.sleep(nanoseconds: 750_000_000) } catch { return }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        reset()
    }

    func refreshDisplay() {
        guard enabled, let now = estimatedGameTime else {
            if !rows.isEmpty { rows = [] }
            return
        }
        let next: [ObjectiveCountdown]
        if mode == "CLASSIC" {
            next = ObjectiveTimerEngine.rift(gameTime: now, events: events, playerTeams: playerTeams)
        } else if isAram {
            relicDeadlines = relicDeadlines.filter { $0.value > now }
            next = ObjectiveTimerEngine.aram(gameTime: now, relicDeadlines: relicDeadlines)
        } else {
            next = []
        }
        if rows != next { rows = next }
    }

    func observeHealthRelicScan(_ scan: HealthRelicScan) {
        guard isAram, scan.scoreboardVisible, let now = estimatedGameTime else { return }
        let readings = scan.readings.sorted { $0.x < $1.x }
        // An empty OCR result is ambiguous (all relics alive versus small text
        // missed by Vision). Existing deadlines expire naturally, so only a
        // frame containing Riot's actual countdown text may replace them.
        // Riot renders four fixed cells from the blue outer relic to the red
        // outer relic. Available relics have no number, so map each detected
        // timer by its cell position instead of shifting a partial row.
        guard !readings.isEmpty else { return }
        if let pendingRelicReadings, readingsMatch(pendingRelicReadings, readings) {
            pendingRelicConfirmations += 1
        } else {
            pendingRelicReadings = readings
            pendingRelicConfirmations = 1
        }
        guard pendingRelicConfirmations >= 2 else {
            setStatus("正在读取 Tab 计分板…")
            return
        }

        let cellCenters = [0.469, 0.499, 0.529, 0.559]
        var availableSlots = Set(1...4)
        var synchronized: [Int: Double] = [:]
        for reading in readings {
            guard let slot = availableSlots.min(by: {
                abs(cellCenters[$0 - 1] - reading.x) < abs(cellCenters[$1 - 1] - reading.x)
            }) else { break }
            availableSlots.remove(slot)
            synchronized[slot] = now + Double(reading.remaining)
        }
        relicDeadlines = synchronized
        lastRelicSync = Date()
        setStatus("已从 Tab 计分板同步 %d 个血包倒计时。", count: readings.count)
        refreshDisplay()
    }

    private var estimatedGameTime: Double? {
        guard let sampledGameTime, Date().timeIntervalSince(sampledAt) < 4 else { return nil }
        return max(0, sampledGameTime + Date().timeIntervalSince(sampledAt))
    }

    private func poll() async {
        do {
            let state = try await live.objectiveState()
            guard !Task.isCancelled else { return }
            let incomingMode = state.game.gameMode.uppercased()
            if incomingMode != mode || (sampledGameTime.map { state.game.gameTime + 5 < $0 } ?? false) {
                relicDeadlines = [:]
                pendingRelicReadings = nil
                pendingRelicConfirmations = 0
                lastRelicSync = nil
            }
            mode = incomingMode
            sampledGameTime = state.game.gameTime
            sampledAt = Date()
            events = state.events
            playerTeams = state.playerTeams
            if mode == "CLASSIC" {
                setStatus("史诗野怪使用 Riot 对局事件自动计时。")
            } else if isAram {
                if lastRelicSync == nil {
                    setStatus("按住 Tab 约 1 秒，同步计分板上的血包倒计时。")
                }
            } else {
                setStatus("当前模式没有启用目标计时。")
            }
            refreshDisplay()
        } catch {
            guard !Task.isCancelled else { return }
            if Date().timeIntervalSince(sampledAt) >= 4 {
                reset()
                setStatus("等待对局数据…")
            }
        }
    }

    private func reset() {
        mode = ""
        sampledGameTime = nil
        sampledAt = .distantPast
        events = []
        playerTeams = [:]
        relicDeadlines = [:]
        pendingRelicReadings = nil
        pendingRelicConfirmations = 0
        lastRelicSync = nil
        rows = []
    }

    private func setStatus(_ key: String, count: Int? = nil) {
        statusKey = key
        statusCount = count
    }

    private func readingsMatch(_ lhs: [HealthRelicTimerReading], _ rhs: [HealthRelicTimerReading]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).allSatisfy {
            abs($0.x - $1.x) <= 0.035 && abs($0.remaining - $1.remaining) <= 2
        }
    }
}

