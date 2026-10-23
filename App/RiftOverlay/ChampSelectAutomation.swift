import Foundation
import Security
import RiftCore
import OSLog

private struct LeagueClientConnection: Equatable {
    let port: Int
    let password: String
    let scheme: String

    static func discover(fileManager: FileManager = .default) -> LeagueClientConnection? {
        let home = fileManager.homeDirectoryForCurrentUser
        let candidates = [
            URL(fileURLWithPath: "/Applications/League of Legends.app/Contents/LoL/lockfile"),
            home.appendingPathComponent("Applications/League of Legends.app/Contents/LoL/lockfile"),
            home.appendingPathComponent("Library/Application Support/Riot Games/League of Legends/lockfile")
        ]
        for url in candidates {
            guard let text = try? String(contentsOf: url, encoding: .utf8),
                  let connection = parse(text) else { continue }
            return connection
        }
        return nil
    }

    static func parse(_ text: String) -> LeagueClientConnection? {
        let fields = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ":", maxSplits: 4, omittingEmptySubsequences: false)
        guard fields.count == 5, let port = Int(fields[2]), (1...65535).contains(port),
              !fields[3].isEmpty else { return nil }
        let scheme = fields[4].lowercased()
        guard scheme == "https" || scheme == "http" else { return nil }
        return LeagueClientConnection(port: port, password: String(fields[3]), scheme: scheme)
    }
}

/// LCU uses a local self-signed certificate. Trust is restricted to the exact
/// loopback host and port obtained from League's short-lived lockfile.
private final class LeagueClientTrust: NSObject, URLSessionDelegate {
    let port: Int
    init(port: Int) { self.port = port }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let space = challenge.protectionSpace
        guard space.authenticationMethod == NSURLAuthenticationMethodServerTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        guard space.host == "127.0.0.1", space.port == port,
              let trust = space.serverTrust else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}

private enum LeagueClientError: LocalizedError {
    case unavailable
    case invalidResponse
    case rejected(Int)

    var errorDescription: String? {
        switch self {
        case .unavailable: return "League Client 未运行"
        case .invalidResponse: return "League Client 返回了无效数据"
        case .rejected(let code): return "League Client 拒绝请求（\(code)）"
        }
    }
}

private final class LeagueClientAPI {
    private let connection: LeagueClientConnection
    private let trust: LeagueClientTrust
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 3
        configuration.timeoutIntervalForResource = 5
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.connectionProxyDictionary = [:]
        return URLSession(configuration: configuration, delegate: trust, delegateQueue: nil)
    }()

    init(connection: LeagueClientConnection) {
        self.connection = connection
        trust = LeagueClientTrust(port: connection.port)
    }
    deinit { session.invalidateAndCancel() }

    func get<T: Decodable>(_ path: String, as type: T.Type = T.self) async throws -> T {
        let data = try await request(path, method: "GET")
        return try JSONDecoder().decode(T.self, from: data)
    }

    func send(_ path: String, method: String, json: [String: Any]? = nil) async throws {
        let body = try json.map { try JSONSerialization.data(withJSONObject: $0) }
        _ = try await request(path, method: method, body: body)
    }

    private func request(_ path: String, method: String, body: Data? = nil) async throws -> Data {
        guard let url = URL(string: "\(connection.scheme)://127.0.0.1:\(connection.port)\(path)") else {
            throw LeagueClientError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 3
        let credentials = Data("riot:\(connection.password)".utf8).base64EncodedString()
        request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw LeagueClientError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw LeagueClientError.rejected(http.statusCode) }
        return data
    }
}

private struct ChampSelectSession: Decodable {
    struct Player: Decodable {
        let cellId: Int
        let championId: Int
        let assignedPosition: String?
        let spell1Id: Int?
        let spell2Id: Int?
    }
    let localPlayerCellId: Int
    let myTeam: [Player]

    var localPlayer: Player? { myTeam.first { $0.cellId == localPlayerCellId } }
}

private struct GameflowSession: Decodable {
    struct GameData: Decodable {
        struct Queue: Decodable { let gameMode: String? }
        let gameMode: String?
        let queue: Queue?
    }
    let gameData: GameData?

    var gameMode: String? { gameData?.queue?.gameMode ?? gameData?.gameMode }
}

private struct LeagueRunePage: Decodable {
    let id: Int
    let name: String
}

private struct LeagueChampionSummary: Decodable {
    let id: Int
    let name: String
    let alias: String
}

@MainActor final class ChampSelectAutomationStore: ObservableObject {
    @Published var automaticRunes: Bool {
        didSet {
            UserDefaults.standard.set(automaticRunes, forKey: "champSelect.autoRunes.v1")
            if automaticRunes && !oldValue { lastRuneKey = nil }
        }
    }
    @Published var automaticSpells: Bool {
        didSet {
            UserDefaults.standard.set(automaticSpells, forKey: "champSelect.autoSpells.v1")
            if automaticSpells && !oldValue { lastSpellKey = nil }
        }
    }
    @Published var flashSlot: FlashSlot {
        didSet {
            UserDefaults.standard.set(flashSlot.rawValue, forKey: "champSelect.flashSlot.v1")
            if flashSlot != oldValue { lastSpellKey = nil }
        }
    }
    @Published private(set) var status = "等待 League Client…"
    @Published private(set) var champion = "—"
    @Published private(set) var position = "—"
    @Published private(set) var recommendedRunes = false
    @Published private(set) var recommendedSpells: [Int] = []

    private var task: Task<Void, Never>?
    private var lastRuneKey: String?
    private var lastSpellKey: String?
    private var cache: [String: (date: Date, loadout: RecommendedLoadout)] = [:]
    private var championSummaries: [Int: LeagueChampionSummary] = [:]
    private var championSummaryConnection: LeagueClientConnection?

    init() {
        automaticRunes = UserDefaults.standard.bool(forKey: "champSelect.autoRunes.v1")
        automaticSpells = UserDefaults.standard.bool(forKey: "champSelect.autoSpells.v1")
        flashSlot = FlashSlot(rawValue: UserDefaults.standard.string(forKey: "champSelect.flashSlot.v1") ?? "") ?? .d
    }

    func start(guide: GuideStore) {
        guard task == nil else { return }
        task = Task { [weak self, weak guide] in
            while !Task.isCancelled {
                if let self, let guide { await self.poll(guide: guide) }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func poll(guide: GuideStore) async {
        guard automaticRunes || automaticSpells else {
            status = "自动配置已关闭"
            resetSessionState()
            return
        }
        guard let connection = LeagueClientConnection.discover() else {
            status = "等待 League Client…"
            championSummaryConnection = nil
            championSummaries = [:]
            resetSessionState()
            return
        }
        if championSummaryConnection != connection {
            championSummaryConnection = connection
            championSummaries = [:]
        }
        let api = LeagueClientAPI(connection: connection)
        do {
            let phase: String = try await api.get("/lol-gameflow/v1/gameflow-phase")
            guard phase == "ChampSelect" else {
                status = "League Client 已连接 · 等待选人"
                resetSessionState()
                return
            }
            let flow = try? await api.get("/lol-gameflow/v1/session", as: GameflowSession.self)
            guard let loadoutMode = Self.loadoutMode(flow?.gameMode) else {
                status = "当前模式不支持自动符文"
                return
            }
            let session: ChampSelectSession = try await api.get("/lol-champ-select/v1/session")
            guard let player = session.localPlayer, player.championId > 0 else {
                status = "选人阶段 · 等待英雄"
                return
            }
            if championSummaries.isEmpty {
                let summaries: [LeagueChampionSummary] = try await api.get("/lol-game-data/assets/v1/champion-summary.json")
                championSummaries = Dictionary(uniqueKeysWithValues: summaries.map { ($0.id, $0) })
            }
            guard let localChampion = championSummaries[player.championId] else {
                status = "已选择英雄，但英雄列表尚未加载"
                return
            }
            let loadedSlug = guide.champions.first(where: { $0.numericID == player.championId })?.id
            let slug = loadedSlug ?? localChampion.alias.lowercased().filter { $0.isLetter || $0.isNumber }
            let option = ChampionOption(id: slug, name: localChampion.name, numericID: localChampion.id)
            let role = Self.opggPosition(player.assignedPosition)
            let key = "\(loadoutMode.rawValue):\(option.id):\(role)"
            champion = localChampion.name
            position = Self.modeLabel(loadoutMode, role: role)
            status = "正在读取 OP.GG 符文与召唤师技能…"
            let loadout = try await recommendation(champion: option.id, position: role, mode: loadoutMode)
            recommendedRunes = true
            recommendedSpells = SummonerSpellOrder.ordered(loadout.spellIDs, flashSlot: flashSlot)

            var changes: [String] = []
            if automaticRunes, lastRuneKey != key {
                try await applyRunes(loadout, championName: localChampion.name, api: api)
                lastRuneKey = key
                changes.append("符文")
            }
            if automaticSpells, loadout.spellIDs.count == 2, lastSpellKey != key {
                let orderedSpells = recommendedSpells
                try await api.send("/lol-champ-select/v1/session/my-selection", method: "PATCH", json: [
                    "spell1Id": orderedSpells[0], "spell2Id": orderedSpells[1]
                ])
                recommendedSpells = orderedSpells
                lastSpellKey = key
                changes.append("召唤师技能")
            }
            status = changes.isEmpty
                ? "推荐已准备 · 本轮不会覆盖手动修改"
                : "已应用\(changes.joined(separator: "与")) · OP.GG 全球数据"
        } catch {
            Logger(subsystem: "dev.local.wexilol", category: "ChampSelect").error("Champ-select automation failed: \(String(describing: error), privacy: .public)")
            status = error.localizedDescription
        }
    }

    private func recommendation(champion: String, position: String,
                                mode: LoadoutGameMode) async throws -> RecommendedLoadout {
        let key = "\(mode.rawValue):\(champion):\(position)"
        if let cached = cache[key], Date().timeIntervalSince(cached.date) < 1800 { return cached.loadout }
        guard let urls = RecommendedLoadoutSource.urls(champion: champion, position: position, mode: mode) else {
            throw URLError(.badURL)
        }
        async let runePage = Self.fetch(urls.runes)
        async let buildPage = Self.fetch(urls.build)
        let (runes, build) = try await (runePage, buildPage)
        guard var loadout = runes.loadout ?? build.loadout else { throw GuideParseError.pageStructureChanged }
        if loadout.spellIDs.count != 2, let spellIDs = build.loadout?.spellIDs, spellIDs.count == 2 {
            loadout = loadout.withSpellIDs(spellIDs)
        }
        cache[key] = (Date(), loadout)
        return loadout
    }

    private nonisolated static func fetch(_ url: URL) async throws -> GuidePage {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("WexiLoL/0.6.2", forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let html = String(data: data, encoding: .utf8) else { throw URLError(.badServerResponse) }
        return try GuideParser.parse(html)
    }

    private func applyRunes(_ loadout: RecommendedLoadout, championName: String,
                            api: LeagueClientAPI) async throws {
        let pages: [LeagueRunePage] = try await api.get("/lol-perks/v1/pages")
        let pageName = String("Wexi LoL - \(championName)".prefix(25))
        let payload: [String: Any] = [
            "name": pageName, "current": true,
            "primaryStyleId": loadout.primaryStyleID,
            "subStyleId": loadout.secondaryStyleID,
            "selectedPerkIds": loadout.selectedPerkIDs
        ]
        let managedPages = pages.filter { Self.isManagedRunePage($0.name) }
        if let page = managedPages.first {
            try await api.send("/lol-perks/v1/pages/\(page.id)", method: "PUT", json: payload)
            for duplicate in managedPages.dropFirst() {
                try? await api.send("/lol-perks/v1/pages/\(duplicate.id)", method: "DELETE")
            }
        } else {
            try await api.send("/lol-perks/v1/pages", method: "POST", json: payload)
        }
    }

    private nonisolated static func isManagedRunePage(_ name: String) -> Bool {
        let normalized = name.lowercased()
        return normalized == "wexi lol" || normalized.hasPrefix("wexi lol - ")
    }

    private func resetSessionState() {
        lastRuneKey = nil
        lastSpellKey = nil
        champion = "—"
        position = "—"
        recommendedRunes = false
        recommendedSpells = []
    }

    private static func opggPosition(_ value: String?) -> String {
        switch value?.lowercased() {
        case "top": return "top"
        case "jungle": return "jungle"
        case "middle", "mid": return "mid"
        case "bottom", "adc": return "adc"
        case "utility", "support": return "support"
        default: return "mid"
        }
    }

    private static func loadoutMode(_ value: String?) -> LoadoutGameMode? {
        switch value?.uppercased() {
        case "CLASSIC": return .ranked
        case "ARAM": return .aram
        default: return nil
        }
    }

    private static func modeLabel(_ mode: LoadoutGameMode, role: String) -> String {
        switch mode {
        case .ranked: return role
        case .aram: return "ARAM"
        }
    }
}
