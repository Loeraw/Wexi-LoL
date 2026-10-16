import Foundation
import RiftCore

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
        guard let url = SummonerProfileURL.make(riotID: riotID, region: region) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue("WexiLoL/0.4", forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let html = String(data: data, encoding: .utf8) else { throw URLError(.badServerResponse) }
        return try SummonerProfileParser.parse(html)
    }
}

@MainActor final class LobbyScoutStore: ObservableObject {
    @Published private(set) var rows: [LobbyPlayerRow] = []
    @Published private(set) var status = "等待加载界面的玩家名单…"
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

    init() {
        let saved = UserDefaults.standard.string(forKey: "playerScoutRegion.v1") ?? "auto"
        regionPreference = saved == "auto" || OPGGRegion(rawValue: saved) != nil ? saved : "auto"
    }

    var isLoadingScreen: Bool { !rows.isEmpty && gameTime.isFinite && gameTime <= 1 }
    var isInGame: Bool { !rows.isEmpty && gameTime.isFinite && gameTime > 1 }

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
                status = L10n.text("无法自动识别区服，请在设置中选择玩家区服。")
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
                status = L10n.text("正在读取玩家资料 0/%d…", rows.count)
                fetchTask = Task { [weak self] in await self?.fetchProfiles(signature: signature, region: region) }
            }
        } catch {
            guard !Task.isCancelled else { return }
            if !gameTime.isFinite { status = L10n.text("等待加载界面的玩家名单…") }
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
        for start in stride(from: 0, to: pending.count, by: 3) {
            guard !Task.isCancelled, matchSignature == signature else { return }
            let batch = Array(pending[start..<min(start + 3, pending.count)])
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
                    case .failure:
                        rows[index].failed = true
                    }
                    completed += 1
                    status = L10n.text("正在读取玩家资料 %d/%d…", completed, rows.count)
                }
            }
        }
        if !Task.isCancelled, matchSignature == signature {
            status = L10n.text(gameTime > 1 ? "玩家资料已读取 · 按 Tab 显示" : "玩家资料已读取 · 进入游戏后按 Tab 显示")
        }
    }
}
