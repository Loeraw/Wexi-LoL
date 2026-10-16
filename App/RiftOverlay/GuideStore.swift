import Foundation
import RiftCore

enum GuideMode: String, CaseIterable, Identifiable, Sendable {
    case mayhem = "aram-mayhem"
    case aram
    case arena
    case ranked

    var id: String { rawValue }
    var titleKey: String {
        switch self {
        case .mayhem: return "大乱斗混乱"
        case .aram: return "极地大乱斗"
        case .arena: return "斗魂竞技场"
        case .ranked: return "排位模式"
        }
    }
    var supportsAugmentTiers: Bool { self == .mayhem || self == .arena }
    var hasDerivedAugmentTiers: Bool { self == .arena }

    static func from(liveMode: String) -> GuideMode? {
        switch liveMode.uppercased() {
        case "KIWI": return .mayhem
        case "ARAM": return .aram
        case "CHERRY": return .arena
        case "CLASSIC": return .ranked
        default: return nil
        }
    }
}

private struct GuideCacheEntry {
    let date: Date
    let primary: GuidePage
    let skills: GuidePage?
    let items: GuidePage?
    let augments: GuidePage?
}

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
    @Published var mode: GuideMode = .mayhem {
        didSet {
            guard mode != oldValue else { return }
            load()
        }
    }
    private var request: Task<Void, Never>?
    private var generation = UUID()
    private var cached: [String: GuideCacheEntry] = [:]

    func displayName(for champion: ChampionOption) -> String {
        champion.name
    }
    var championName: String { champions.first { $0.id == championKey }.map { displayName(for: $0) } ?? championKey }
    var matchingChampions: [ChampionOption] {
        champions.filter { championSearch.isEmpty || $0.name.localizedCaseInsensitiveContains(championSearch) || $0.id.localizedCaseInsensitiveContains(championSearch) }
    }
    var matchingAugments: [AugmentRating] { augments.filter { $0.matches(augmentSearch) } }
    var statusCount: Int { augments.isEmpty ? itemBuilds.count : augments.count }
    var overlayAugments: [AugmentRating] {
        if !recognized.isEmpty { return recognized.compactMap { id in augments.first { $0.id == id } } }
        if !pinned.isEmpty { return pinned.compactMap { id in augments.first { $0.id == id } } }
        return Array(matchingAugments.prefix(6))
    }
    func sourceURL(_ section: String) -> URL {
        Self.sourceURL(section, champion: championKey, mode: mode, language: LanguageSettings.shared.selection)
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
        let selectedMode = mode
        let language = LanguageSettings.shared.selection
        let gameLanguage = LanguageSettings.shared.gameLanguage
        let cacheKey = "\(language.rawValue):\(gameLanguage.rawValue):\(selectedMode.rawValue):\(key)"
        augments = []; skills = nil; itemBuilds = []; pinned = []; recognized = []; patch = "—"; fetchedAt = nil
        augmentSearch = ""
        loading = true; status = "正在读取 OP.GG 攻略…"
        let augmentURL = Self.sourceURL("augments", champion: key, mode: selectedMode, language: language)
        let skillURL = Self.sourceURL("skills", champion: key, mode: selectedMode, language: language)
        let itemURL = Self.sourceURL("items", champion: key, mode: selectedMode, language: language)
        request = Task {
            do {
                let primaryPage: GuidePage, augmentPage: GuidePage?, skillPage: GuidePage?, itemPage: GuidePage?
                let date: Date
                if !force, let cache = cached[cacheKey], Date().timeIntervalSince(cache.date) < 1800 {
                    date = cache.date; primaryPage = cache.primary
                    skillPage = cache.skills; itemPage = cache.items; augmentPage = cache.augments
                } else {
                    async let item = Self.fetch(itemURL, language: language)
                    async let skill = try? Self.fetch(skillURL, language: language)
                    async let augment = selectedMode.supportsAugmentTiers ? (try? Self.fetch(augmentURL, language: language)) : nil
                    let fetchedItems = try await item
                    itemPage = fetchedItems; skillPage = await skill; augmentPage = await augment
                    primaryPage = fetchedItems
                    date = Date()
                }
                guard !Task.isCancelled, generation == token else { return }
                let resolvedPatch = primaryPage.patch ?? itemPage?.patch ?? skillPage?.patch ?? augmentPage?.patch
                guard resolvedPatch != nil, !(itemPage?.itemBuilds ?? []).isEmpty else {
                    throw GuideParseError.pageStructureChanged
                }
                cached[cacheKey] = GuideCacheEntry(date: date, primary: primaryPage, skills: skillPage,
                                                   items: itemPage, augments: augmentPage)
                champions = [primaryPage, itemPage, skillPage, augmentPage]
                    .compactMap { $0 }.first { !$0.champions.isEmpty }?.champions ?? champions
                augments = (augmentPage?.augments ?? []).sorted {
                    if $0.tier != $1.tier { return $0.tier < $1.tier }
                    if let left = $0.winRate, let right = $1.winRate, left != right { return left > right }
                    return $0.id < $1.id
                }
                skills = skillPage?.skills
                itemBuilds = itemPage?.itemBuilds ?? []
                patch = resolvedPatch ?? "—"; fetchedAt = date
                status = augments.isEmpty
                    ? "已加载 %d 套出装路线 · OP.GG 全球数据"
                    : "已加载 %d 个海克斯评级 · OP.GG 全球数据"
                loading = false
                // Keep the visible guide in the Wexi interface language, while
                // adding the actual League client locale and English as OCR aliases.
                if selectedMode.supportsAugmentTiers, let augmentPage {
                    var aliasesByID: [Int: [String]] = [:]
                    var englishByID: [Int: String] = [:]
                    var aliasLanguages: [AppLanguage] = []
                    for candidate in [gameLanguage, .english] where candidate != language && !aliasLanguages.contains(candidate) {
                        aliasLanguages.append(candidate)
                    }
                    for aliasLanguage in aliasLanguages {
                        let aliasURL = Self.sourceURL("augments", champion: key, mode: selectedMode, language: aliasLanguage)
                        guard let aliasPage = try? await Self.fetch(aliasURL, language: aliasLanguage),
                              aliasPage.patch == augmentPage.patch else { continue }
                        for item in aliasPage.augments {
                            aliasesByID[item.id, default: []].append(item.name)
                            if aliasLanguage == .english { englishByID[item.id] = item.name }
                        }
                    }
                    guard !Task.isCancelled, generation == token else { return }
                    var enriched = augmentPage
                    enriched.augments = augmentPage.augments.map { item in
                        var copy = item
                        copy.englishName = englishByID[item.id] ?? item.englishName
                        copy.alternateNames = Array(Set(item.alternateNames + aliasesByID[item.id, default: []]))
                            .filter { $0 != item.name }
                        return copy
                    }
                    augments = enriched.augments.sorted {
                        if $0.tier != $1.tier { return $0.tier < $1.tier }
                        if let left = $0.winRate, let right = $1.winRate, left != right { return left > right }
                        return $0.id < $1.id
                    }
                    cached[cacheKey] = GuideCacheEntry(date: date, primary: primaryPage, skills: skillPage,
                                                       items: itemPage, augments: enriched)
                }
            } catch {
                guard !Task.isCancelled, generation == token else { return }
                status = "攻略加载失败；网络或网页结构可能变化，请重试或查看原网页。"
                loading = false
            }
        }
    }
    private nonisolated static func sourceURL(_ section: String, champion: String, mode: GuideMode,
                                              language: AppLanguage) -> URL {
        let locale = language.opggPrefix
        if mode == .ranked {
            return URL(string: "https://op.gg\(locale)/lol/champions/\(champion)/\(section)")!
        }
        return URL(string: "https://op.gg\(locale)/lol/modes/\(mode.rawValue)/\(champion)/\(section)")!
    }
    private nonisolated static func fetch(_ url: URL, language: AppLanguage) async throws -> GuidePage {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("WexiLoL/0.5.3", forHTTPHeaderField: "User-Agent")
        request.setValue(language.acceptLanguage, forHTTPHeaderField: "Accept-Language")
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
