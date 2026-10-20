import Foundation
import RiftCore

struct PostGameRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let date: Date
    let champion: String
    let duration: Double
    let kills: Int
    let deaths: Int
    let assists: Int
    let creepScore: Int
    let wardScore: Double
    var csPerMinute: Double { duration >= 60 ? Double(creepScore) / (duration / 60) : 0 }
    var visionPerMinute: Double { duration >= 60 ? wardScore / (duration / 60) : 0 }
    var kda: Double { Double(kills + assists) / Double(max(1, deaths)) }
}

@MainActor final class PostGameStore: ObservableObject {
    @Published private(set) var records: [PostGameRecord] = []
    @Published private(set) var status = "等待完成一局对局…"
    private let live = LiveClient()
    private var task: Task<Void, Never>?
    private var lastSnapshot: Snapshot?
    private var lastChampion = ""
    private var lastSeen = Date.distantPast
    private var savedCurrentGame = false
    private static let defaultsKey = "postGameRecords.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode([PostGameRecord].self, from: data) { records = decoded }
    }

    func start() {
        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch { return }
            }
        }
    }
    func stop() { task?.cancel(); task = nil }

    var recentAverage: String {
        let values = Array(records.prefix(10)); guard !values.isEmpty else { return "—" }
        let cs = values.reduce(0) { $0 + $1.csPerMinute } / Double(values.count)
        let kda = values.reduce(0) { $0 + $1.kda } / Double(values.count)
        return String(format: "%.1f CS/min · %.2f KDA", cs, kda)
    }

    func advice(for record: PostGameRecord) -> String {
        if record.deaths >= 8 { return L10n.text("死亡次数偏高；优先复盘视野外阵亡和无目标团战。") }
        if record.csPerMinute < 5.5 { return L10n.text("补刀节奏偏低；检查前十分钟漏刀和转线后的兵线处理。") }
        if record.visionPerMinute < 0.6 { return L10n.text("视野贡献偏低；回城补真眼，并在资源刷新前提前布置视野。") }
        return L10n.text("基础数据稳定；下一步可重点复盘关键团战的站位和技能使用。")
    }

    private func poll() async {
        do {
            async let snapshot = live.snapshot()
            async let champion = live.champion()
            let (current, identity) = try await (snapshot, champion)
            if lastSnapshot == nil || current.game.gameTime + 30 < (lastSnapshot?.game.gameTime ?? 0) { savedCurrentGame = false }
            lastSnapshot = current; lastChampion = identity.key; lastSeen = Date(); savedCurrentGame = false
            status = L10n.text("正在记录当前对局…")
        } catch {
            guard !savedCurrentGame, let snapshot = lastSnapshot,
                  snapshot.game.gameTime >= 300, Date().timeIntervalSince(lastSeen) > 6 else { return }
            let record = PostGameRecord(id: UUID(), date: Date(), champion: lastChampion,
                                        duration: snapshot.game.gameTime, kills: snapshot.scores.kills,
                                        deaths: snapshot.scores.deaths, assists: snapshot.scores.assists,
                                        creepScore: snapshot.scores.creepScore, wardScore: snapshot.scores.wardScore)
            records.insert(record, at: 0); records = Array(records.prefix(30)); savedCurrentGame = true
            UserDefaults.standard.set(try? JSONEncoder().encode(records), forKey: Self.defaultsKey)
            status = L10n.text("最近一局已保存到本机")
        }
    }
}
