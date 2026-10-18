import Foundation
import RiftCore
import OSLog

struct LobbyPlayerRow: Identifiable, Equatable, Sendable {
    let riotID: String
    let champion: String
    let team: String
    var profile: SummonerProfile?
    var failed = false
    var id: String { riotID }
}

private enum LeagueRegionDetector {
    static func detect() -> OPGGRegion? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "command="]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, let commands = String(data: data, encoding: .utf8) else { return nil }
        for line in commands.split(separator: "\n") where line.localizedCaseInsensitiveContains("LeagueClient") {
            for component in line.split(whereSeparator: { $0.isWhitespace }) {
                let argument = String(component).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                for prefix in ["--platform-id=", "--region="] where argument.lowercased().hasPrefix(prefix) {
                    let value = String(argument.dropFirst(prefix.count))
                    if let region = OPGGRegion.from(platformID: value) { return region }
                }
            }
        }
        return nil
    }
}

private final class OPGGSummonerClient: @unchecked Sendable {
    private let session: URLSession

    private enum FetchError: Error {
        case httpStatus(Int)
        case invalidHTML
    }

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        session = URLSession(configuration: configuration)
    }

    deinit { session.invalidateAndCancel() }

    func fetch(riotID: String, region: OPGGRegion) async throws -> SummonerProfile {
        var lastError: Error = URLError(.unknown)
        for attempt in 0..<3 {
            do { return try await fetchOnce(riotID: riotID, region: region) }
            catch {
                lastError = error
                guard attempt < 2, isTransient(error) else { throw error }
                let delay = UInt64(450 + attempt * 750) * 1_000_000
                try await Task.sleep(nanoseconds: delay)
            }
        }
        throw lastError
    }

    private func fetchOnce(riotID: String, region: OPGGRegion) async throws -> SummonerProfile {
        guard let url = SummonerProfileURL.make(riotID: riotID, region: region) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue("WexiLoL/0.5.3", forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard http.statusCode == 200 else { throw FetchError.httpStatus(http.statusCode) }
        guard let html = String(data: data, encoding: .utf8), !html.isEmpty else { throw FetchError.invalidHTML }
        return try SummonerProfileParser.parse(html)
    }

    private func isTransient(_ error: Error) -> Bool {
        if case FetchError.httpStatus(let status) = error {
            return status == 408 || status == 425 || status == 429 || (500...599).contains(status)
        }
        guard let urlError = error as? URLError else { return false }
        return [
            .timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost,
            .dnsLookupFailed, .notConnectedToInternet, .resourceUnavailable
        ].contains(urlError.code)
    }
}

@MainActor final class LobbyScoutStore: ObservableObject {
    @Published private(set) var rows: [LobbyPlayerRow] = []
    @Published private var statusKey = "等待加载界面的玩家名单…"
    @Published private var statusValues: [Int] = []
    @Published private(set) var gameTime: Double = .infinity
    @Published private(set) var activeRegion: OPGGRegion?
    @Published var regionPreference: String {
        didSet {
            guard regionPreference != oldValue else { return }
            UserDefaults.standard.set(regionPreference, forKey: "playerScoutRegion.v1")
            detectedRegion = nil
            lastRegionDetection = .distantPast
            matchSignature = ""
            fetchTask?.cancel()
        }
    }

    private let live = LiveClient()
    private let client = OPGGSummonerClient()
    private var pollTask: Task<Void, Never>?
    private var fetchTask: Task<Void, Never>?
    private var matchSignature = ""
    private var cache: [String: (Date, SummonerProfile)] = [:]
    private var detectedRegion: OPGGRegion?
    private var lastRegionDetection = Date.distantPast

    var loadedProfileCount: Int { rows.lazy.filter { $0.profile != nil }.count }
    var failedProfileCount: Int { rows.lazy.filter(\.failed).count }

    init() {
        let saved = UserDefaults.standard.string(forKey: "playerScoutRegion.v1") ?? "auto"
        regionPreference = saved == "auto" || OPGGRegion(rawValue: saved) != nil ? saved : "auto"
    }

    var isLoadingScreen: Bool { !rows.isEmpty && gameTime.isFinite && gameTime <= 1 }
    var isInGame: Bool { !rows.isEmpty && gameTime.isFinite && gameTime > 1 }
    var status: String {
        if statusKey == "scout-complete-with-failures" {
            let loaded = loadedProfileCount
            let failed = failedProfileCount
            if loaded == 0 { return L10n.text("无公开数据") + " \(failed)/\(rows.count)" }
            let base = L10n.text(gameTime > 1 ? "玩家资料已读取 · 按 Tab 显示" : "玩家资料已读取 · 进入游戏后按 Tab 显示")
            return base + " · " + L10n.text("无公开数据") + " \(failed)/\(rows.count)"
        }
        switch statusValues.count {
        case 1: return L10n.text(statusKey, statusValues[0])
        case 2: return L10n.text(statusKey, statusValues[0], statusValues[1])
        default: return L10n.text(statusKey)
        }
    }

    func start() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.poll()
                do { try await Task.sleep(nanoseconds: 350_000_000) } catch { return }
            }
        }
    }

    func stop() {
        pollTask?.cancel(); fetchTask?.cancel()
        pollTask = nil; fetchTask = nil
        rows = []; matchSignature = ""; gameTime = .infinity; activeRegion = nil
    }

    private func poll() async {
        do {
            let state = try await live.lobbyState()
            guard !Task.isCancelled else { return }
            gameTime = state.game.gameTime
            let players = state.players.compactMap { player -> LobbyPlayerRow? in
                guard let riotID = player.riotId, riotID.contains("#") else { return nil }
                return LobbyPlayerRow(riotID: riotID, champion: player.championName,
                                      team: player.team ?? "", profile: nil)
            }
            guard players.count >= 2 else { return }
            guard let region = await resolveRegion(players: players) else {
                rows = players
                activeRegion = nil
                setStatus("无法自动识别区服，请在设置中选择玩家区服。")
                return
            }
            activeRegion = region
            // The ten Riot IDs define the match cache. Champion labels can be
            // represented differently after loading; they must not trigger a
            // second OP.GG fetch when the live game begins.
            let signature = region.rawValue + "|" + players.map { "\($0.team):\($0.riotID)" }.joined(separator: "|")
            if signature != matchSignature {
                matchSignature = signature
                fetchTask?.cancel()
                rows = players.map { player in
                    var copy = player
                    let key = region.rawValue + ":" + player.riotID
                    if let cached = cache[key], Date().timeIntervalSince(cached.0) < 900 { copy.profile = cached.1 }
                    return copy
                }
                setStatus("正在读取玩家资料 0/%d…", rows.count)
                fetchTask = Task { [weak self] in await self?.fetchProfiles(signature: signature, region: region) }
            }
        } catch {
            guard !Task.isCancelled else { return }
            if !gameTime.isFinite { setStatus("等待加载界面的玩家名单…") }
        }
    }

    private func resolveRegion(players: [LobbyPlayerRow]) async -> OPGGRegion? {
        if regionPreference != "auto" { return OPGGRegion(rawValue: regionPreference) }
        if let detectedRegion { return detectedRegion }
        if Date().timeIntervalSince(lastRegionDetection) >= 30 {
            lastRegionDetection = Date()
            let detected = await Task.detached(priority: .utility) { LeagueRegionDetector.detect() }.value
            if let detected { detectedRegion = detected; return detected }
        }
        return players.lazy.compactMap { OPGGRegion.inferred(fromRiotID: $0.riotID) }.first
    }

    private func fetchProfiles(signature: String, region: OPGGRegion) async {
        let pending = rows.filter { $0.profile == nil }.map(\.riotID)
        var completed = rows.count - pending.count
        for start in stride(from: 0, to: pending.count, by: 2) {
            guard !Task.isCancelled, matchSignature == signature else { return }
            let batch = Array(pending[start..<min(start + 2, pending.count)])
            await withTaskGroup(of: (String, Result<SummonerProfile, Error>).self) { group in
                for riotID in batch {
                    group.addTask { [client] in
                        do { return (riotID, .success(try await client.fetch(riotID: riotID, region: region))) }
                        catch { return (riotID, .failure(error)) }
                    }
                }
                for await (riotID, result) in group {
                    guard !Task.isCancelled, matchSignature == signature,
                          let index = rows.firstIndex(where: { $0.riotID == riotID }) else { continue }
                    switch result {
                    case .success(let profile):
                        rows[index].profile = profile
                        cache[region.rawValue + ":" + riotID] = (Date(), profile)
                    case .failure(let error):
                        rows[index].failed = true
                        Logger(subsystem: "dev.local.wexilol", category: "OPGGProfile")
                            .error("Profile request failed: domain=\((error as NSError).domain, privacy: .public) code=\((error as NSError).code)")
                    }
                    completed += 1
                    setStatus("正在读取玩家资料 %d/%d…", completed, rows.count)
                }
            }
            if start + batch.count < pending.count {
                do { try await Task.sleep(nanoseconds: 250_000_000) } catch { return }
            }
        }
        if !Task.isCancelled, matchSignature == signature {
            let failed = failedProfileCount
            if failed == 0 {
                setStatus(gameTime > 1 ? "玩家资料已读取 · 按 Tab 显示" : "玩家资料已读取 · 进入游戏后按 Tab 显示")
            } else {
                statusKey = "scout-complete-with-failures"
                statusValues = []
            }
        }
    }

    private func setStatus(_ key: String, _ values: Int...) {
        statusKey = key
        statusValues = values
    }
}
