import Foundation
import RiftCore

@MainActor final class GuideStore: ObservableObject {
    @Published var championKey = "kayle"
    @Published var champions: [ChampionOption] = []
    @Published var championSearch = ""
    @Published var augmentSearch = ""
    @Published var augments: [AugmentRating] = []
    @Published var skills: SkillGuide?
    @Published var itemBuilds: [ItemBuild] = []
    @Published var patch = "—"
    @Published var status = "选择英雄后加载攻略"
    @Published var loading = false
    @Published var pinned: [Int] = []
    @Published var recognized: [Int] = []
    @Published var fetchedAt: Date?
    private var request: Task<Void, Never>?
    private var generation = UUID()
    private var cached: [String: (Date, GuidePage, GuidePage?, GuidePage?)] = [:]

    func displayName(for champion: ChampionOption) -> String {
        champion.name
    }
    var championName: String { champions.first { $0.id == championKey }.map { displayName(for: $0) } ?? championKey }
    var matchingChampions: [ChampionOption] {
        champions.filter { championSearch.isEmpty || $0.name.localizedCaseInsensitiveContains(championSearch) || $0.id.localizedCaseInsensitiveContains(championSearch) }
    }
    var matchingAugments: [AugmentRating] { augments.filter { $0.matches(augmentSearch) } }
    var overlayAugments: [AugmentRating] {
        if !recognized.isEmpty { return recognized.compactMap { id in augments.first { $0.id == id } } }
        if !pinned.isEmpty { return pinned.compactMap { id in augments.first { $0.id == id } } }
        return Array(matchingAugments.prefix(6))
    }
    func sourceURL(_ section: String) -> URL {
        Self.sourceURL(section, champion: championKey, language: LanguageSettings.shared.selection)
    }
    func pin(_ augment: AugmentRating) {
        if pinned.contains(augment.id) { pinned.removeAll { $0 == augment.id } }
        else if pinned.count < 3 { pinned.append(augment.id) }
    }
    func load(force: Bool = false) {
        guard championKey.range(of: #"^[a-z0-9]+$"#, options: .regularExpression) != nil else { return }
        request?.cancel()
        let token = UUID(); generation = token
        let key = championKey
        let language = LanguageSettings.shared.selection
        let cacheKey = "\(language.rawValue):\(key)"
        augments = []; skills = nil; itemBuilds = []; pinned = []; recognized = []; patch = "—"; fetchedAt = nil
        augmentSearch = ""
        loading = true; status = "正在读取 OP.GG 攻略…"
        let augmentURL = Self.sourceURL("augments", champion: key, language: language)
        let skillURL = Self.sourceURL("skills", champion: key, language: language)
        let itemURL = Self.sourceURL("items", champion: key, language: language)
        request = Task {
            do {
                let augmentPage: GuidePage, skillPage: GuidePage?, itemPage: GuidePage?
                let date: Date
                if !force, let cache = cached[cacheKey], Date().timeIntervalSince(cache.0) < 1800 {
                    date = cache.0; augmentPage = cache.1; skillPage = cache.2; itemPage = cache.3
                } else {
                    async let first = Self.fetch(augmentURL)
                    async let second = try? Self.fetch(skillURL)
                    async let third = try? Self.fetch(itemURL)
                    augmentPage = try await first; skillPage = await second; itemPage = await third
                    date = Date()
                }
                guard !Task.isCancelled, generation == token else { return }
                guard !augmentPage.augments.isEmpty, augmentPage.patch != nil else {
                    throw GuideParseError.pageStructureChanged
                }
                cached[cacheKey] = (date, augmentPage, skillPage, itemPage)
                champions = augmentPage.champions
                augments = augmentPage.augments.sorted { $0.tier < $1.tier || ($0.tier == $1.tier && $0.id < $1.id) }
                skills = skillPage?.patch == augmentPage.patch ? skillPage?.skills : nil
                itemBuilds = itemPage?.patch == augmentPage.patch ? (itemPage?.itemBuilds ?? []) : []
                patch = augmentPage.patch ?? "—"; fetchedAt = date
                status = "已加载 %d 个海克斯评级 · OP.GG 全球数据"
                loading = false
                // Fetch the other locale as an OCR alias after the selected locale
                // is ready. Visible names always come from the selected OP.GG site.
                let alternate: AppLanguage = language == .english ? .chinese : .english
                let alternateURL = Self.sourceURL("augments", champion: key, language: alternate)
                if let alternatePage = try? await Self.fetch(alternateURL),
                   !Task.isCancelled, generation == token, alternatePage.patch == augmentPage.patch {
                    let names = Dictionary(alternatePage.augments.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
                    var enriched = augmentPage
                    enriched.augments = augmentPage.augments.map { item in
                        var copy = item; copy.englishName = names[item.id]; return copy
                    }
                    augments = augments.map { item in
                        var copy = item; copy.englishName = names[item.id]; return copy
                    }
                    cached[cacheKey] = (date, enriched, skillPage, itemPage)
                }
            } catch {
                guard !Task.isCancelled, generation == token else { return }
                status = "攻略加载失败；网络或网页结构可能变化，请重试或查看原网页。"
                loading = false
            }
        }
    }
    private nonisolated static func sourceURL(_ section: String, champion: String, language: AppLanguage) -> URL {
        let locale = language == .chinese ? "/zh-cn" : ""
        return URL(string: "https://op.gg\(locale)/lol/modes/aram-mayhem/\(champion)/\(section)")!
    }
    private nonisolated static func fetch(_ url: URL) async throws -> GuidePage {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("WexiLoL/0.3 (local personal prototype)", forHTTPHeaderField: "User-Agent")
        let chinese = url.path.hasPrefix("/zh-cn/")
        request.setValue(chinese ? "zh-CN,zh;q=0.9" : "en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        // OP.GG stores its last locale in a cookie. A shared session can therefore
        // return Chinese content for the unprefixed English URL after visiting
        // /zh-cn. Keep guide requests stateless so the URL controls the language.
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
}
