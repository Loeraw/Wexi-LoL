import Foundation
import Security
import RiftCore
import OSLog

// Only Riot's certificate anchor is trusted, and only for the fixed loopback service.
final class RiotLocalTrust: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let space = challenge.protectionSpace
        guard space.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              space.host == "127.0.0.1", space.port == 2999,
              let trust = space.serverTrust,
              let file = Bundle.module.url(forResource: "riotgames", withExtension: "pem"),
              let pem = try? String(contentsOf: file, encoding: .utf8),
              let bytes = Data(base64Encoded: pem
                .replacingOccurrences(of: "-----BEGIN CERTIFICATE-----", with: "")
                .replacingOccurrences(of: "-----END CERTIFICATE-----", with: ""), options: .ignoreUnknownCharacters),
              let certificate = SecCertificateCreateWithData(nil, bytes as CFData)
        else { completionHandler(.cancelAuthenticationChallenge, nil); return }
        if LocalGameCertificateTrust.evaluate(trust, anchor: certificate) {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            Logger(subsystem: "dev.local.wexilol", category: "LiveClient").error("Local certificate failed pinned CA, validity, IP, or server-auth verification")
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

final class LiveClient {
    private let trust = RiotLocalTrust()
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 2
        config.timeoutIntervalForResource = 4
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.connectionProxyDictionary = [:]
        return URLSession(configuration: config, delegate: trust, delegateQueue: nil)
    }()
    deinit { session.invalidateAndCancel() }

    private func get<T: Decodable>(_ url: URL) async throws -> T {
        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(from: url) }
        catch {
            let code = (error as NSError).code, domain = (error as NSError).domain
            Logger(subsystem: "dev.local.wexilol", category: "LiveClient").error("Local request failed: domain=\(domain, privacy: .public) code=\(code)")
            throw error
        }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch {
            let model = String(describing: T.self)
            Logger(subsystem: "dev.local.wexilol", category: "LiveClient").error("Local response decoding failed for \(model, privacy: .public)")
            throw error
        }
    }
    func snapshot() async throws -> Snapshot {
        let player: ActivePlayer = try await get(URL(string: "https://127.0.0.1:2999/liveclientdata/activeplayer")!)
        guard let scoresURL = LiveEndpoint.scoresURL(for: player) else { throw URLError(.cannotParseResponse) }
        async let scores: Scores = get(scoresURL)
        async let game: GameStats = get(URL(string: "https://127.0.0.1:2999/liveclientdata/gamestats")!)
        return try await Snapshot(player: player, scores: scores, game: game)
    }
    func champion() async throws -> (key: String, mode: String, level: Int, ranks: [String: Int], itemIDs: [Int]) {
        let active: ActivePlayer = try await get(URL(string: "https://127.0.0.1:2999/liveclientdata/activeplayer")!)
        async let roster: [LiveRosterPlayer] = get(URL(string: "https://127.0.0.1:2999/liveclientdata/playerlist")!)
        async let game: GameStats = get(URL(string: "https://127.0.0.1:2999/liveclientdata/gamestats")!)
        let (players, stats) = try await (roster, game)
        guard let key = ChampionRecognition.key(active: active, roster: players) else { throw URLError(.cannotParseResponse) }
        return (key, stats.gameMode, active.level, active.skillRanks,
                ChampionRecognition.ownedItemIDs(active: active, roster: players))
    }
    func objectiveState() async throws -> (game: GameStats, events: [LiveGameEvent], playerTeams: [String: String]) {
        async let game: GameStats = get(URL(string: "https://127.0.0.1:2999/liveclientdata/gamestats")!)
        async let eventData: LiveEventData = get(URL(string: "https://127.0.0.1:2999/liveclientdata/eventdata")!)
        async let roster: [LiveRosterPlayer] = get(URL(string: "https://127.0.0.1:2999/liveclientdata/playerlist")!)
        let (stats, data, players) = try await (game, eventData, roster)
        var teams: [String: String] = [:]
        for player in players {
            guard let team = player.team else { continue }
            for name in [player.riotId, player.summonerName].compactMap({ $0 }) where !name.isEmpty {
                teams[ObjectiveTimerEngine.normalize(name)] = team
            }
        }
        return (stats, data.events, teams)
    }
    func lobbyState() async throws -> (game: GameStats, players: [LiveRosterPlayer]) {
        async let game: GameStats = get(URL(string: "https://127.0.0.1:2999/liveclientdata/gamestats")!)
        async let roster: [LiveRosterPlayer] = get(URL(string: "https://127.0.0.1:2999/liveclientdata/playerlist")!)
        return try await (game, roster)
    }
}

@MainActor final class OverlayModel: ObservableObject {
    @Published var opacity: Double {
        didSet { UserDefaults.standard.set(opacity, forKey: "overlayOpacity.v1") }
    }
    @Published var overlayScale: Double {
        didSet { UserDefaults.standard.set(overlayScale, forKey: "overlayScale.v1") }
    }
    @Published var itemBuildEnabled: Bool {
        didSet { UserDefaults.standard.set(itemBuildEnabled, forKey: "itemBuildOverlayEnabled.v1") }
    }
    @Published var playerScoutEnabled: Bool {
        didSet { UserDefaults.standard.set(playerScoutEnabled, forKey: "playerScoutEnabled.v1") }
    }
    @Published var hotkeyStatus = ""
    @Published var overlayStatus = "等待对局 · 平时不显示提示"
    @Published var diagnosticStatus = ""

    init() {
        let storedOpacity = UserDefaults.standard.object(forKey: "overlayOpacity.v1") as? Double ?? 0.94
        opacity = min(1, max(0.35, storedOpacity))
        let storedScale = UserDefaults.standard.object(forKey: "overlayScale.v1") as? Double ?? 1
        overlayScale = min(1.35, max(0.75, storedScale))
        itemBuildEnabled = UserDefaults.standard.object(forKey: "itemBuildOverlayEnabled.v1") == nil
            ? true : UserDefaults.standard.bool(forKey: "itemBuildOverlayEnabled.v1")
        playerScoutEnabled = UserDefaults.standard.object(forKey: "playerScoutEnabled.v1") == nil
            ? true : UserDefaults.standard.bool(forKey: "playerScoutEnabled.v1")
    }
}
