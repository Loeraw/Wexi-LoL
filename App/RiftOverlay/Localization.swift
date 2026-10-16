import Foundation
import Combine

enum AppLanguage: String, CaseIterable, Identifiable {
    case chinese = "zh-Hans"
    case english = "en"

    var id: String { rawValue }
    var title: String { self == .chinese ? "简体中文" : "English" }
    var locale: Locale { Locale(identifier: rawValue) }
}

@MainActor final class LanguageSettings: ObservableObject {
    static let shared = LanguageSettings()
    static let preferenceKey = "interfaceLanguage"
    static let didChange = Notification.Name("WexiLoL.languageDidChange")

    @Published var selection: AppLanguage {
        didSet {
            guard selection != oldValue else { return }
            UserDefaults.standard.set(selection.rawValue, forKey: Self.preferenceKey)
            NotificationCenter.default.post(name: Self.didChange, object: self)
        }
    }

    private init() {
        if UserDefaults.standard.object(forKey: Self.preferenceKey) == nil,
           let previous = UserDefaults(suiteName: "dev.local.riftoverlay")?.string(forKey: Self.preferenceKey) {
            UserDefaults.standard.set(previous, forKey: Self.preferenceKey)
        }
        // Preserve the original Chinese interface until the user chooses otherwise.
        selection = AppLanguage(rawValue: UserDefaults.standard.string(forKey: Self.preferenceKey) ?? "") ?? .chinese
    }
}

@MainActor enum L10n {
    static func text(_ key: String, _ arguments: CVarArg...) -> String {
        let language = LanguageSettings.shared.selection
        let format = language == .english ? (english[key] ?? key) : key
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: language.locale, arguments: arguments)
    }

    private static let english: [String: String] = [
        "语言": "Language",
        "设置": "Settings",
        "返回攻略": "Back to guide",
        "英雄": "Champions",
        "界面": "Interface",
        "提示透明度": "Hint opacity",
        "屏幕录制": "Screen recording",
        "目标计时": "Objective timers",
        "出装推荐": "Build recommendation",
        "对局玩家": "Match players",
        "玩家区服": "Player region",
        "自动检测": "Auto-detect",
        "当前玩家区服": "Current player region",
        "等待检测": "Waiting to detect",
        "无法自动识别区服，请在设置中选择玩家区服。": "Could not auto-detect the region. Choose a player region in Settings.",
        "显示玩家段位与战绩": "Show player ranks and match history",
        "Loading 阶段只读取一次玩家资料并保存在本局缓存；进入游戏后按住 Tab 只切换显示，不会重新请求 OP.GG。": "Player profiles are fetched once during loading and cached for the match. Holding Tab in game only toggles their display and does not request OP.GG again.",
        "等待加载界面的玩家名单…": "Waiting for the loading-screen player list…",
        "正在读取玩家资料 0/%d…": "Loading player profiles 0/%d…",
        "正在读取玩家资料 %d/%d…": "Loading player profiles %d/%d…",
        "玩家资料已读取 · 按 Tab 显示": "Player profiles ready · Hold Tab to show",
        "玩家资料已读取 · 进入游戏后按 Tab 显示": "Player profiles ready · Hold Tab after the game starts",
        "无公开数据": "No public data",
        "读取中…": "Loading…",
        "未定级": "Unranked",
        "段位 · 赛季胜率 · 最近战绩": "Rank · Season win rate · Recent",
        "当前对局玩家": "Current match players",
        "蓝方": "Blue team",
        "红方": "Red team",
        "显示玩家资料": "Show players",
        "隐藏玩家资料": "Hide players",
        "Wexi LoL 当前对局玩家": "Wexi LoL match players",
        "IRON": "Iron",
        "BRONZE": "Bronze",
        "SILVER": "Silver",
        "GOLD": "Gold",
        "PLATINUM": "Platinum",
        "EMERALD": "Emerald",
        "DIAMOND": "Diamond",
        "MASTER": "Master",
        "GRANDMASTER": "Grandmaster",
        "CHALLENGER": "Challenger",
        "显示推荐出装与胜率": "Show recommended build and win rate",
        "根据当前已购买的核心装备匹配 OP.GG 主流三件套，并标出下一件；胜率是该完整路线的统计。": "Matches a popular OP.GG three-item route to your completed core items and marks the next item. The win rate is for the complete route.",
        "已加载出装路线": "Loaded build routes",
        "%d 套": "%d routes",
        "推荐出装": "Recommended build",
        "按场次排序": "Sorted by games",
        "选用率 %.1f%% · %d 场": "Pick rate %.1f%% · %d games",
        "OP.GG 出装来源 ↗": "OP.GG build source ↗",
        "大乱斗混乱": "ARAM: Mayhem",
        "极地大乱斗": "ARAM",
        "斗魂竞技场": "Arena",
        "排位模式": "Ranked",
        "斗魂评级根据同稀有度海克斯的 OP.GG 胜率与场次计算，并非 OP.GG 官方分级。": "Arena tiers are calculated from OP.GG win rate and sample size within each rarity; they are not official OP.GG tiers.",
        "下一件": "Next",
        "胜率 %.1f%%": "Win rate %.1f%%",
        "胜率 %.1f%% · 选用率 %.1f%% · %d 场": "Win rate %.1f%% · Pick rate %.1f%% · %d games",
        "OP.GG · 选用率 %.1f%% · %d 场": "OP.GG · Pick rate %.1f%% · %d games",
        "Wexi LoL 推荐出装": "Wexi LoL recommended build",
        "显示游戏内目标倒计时": "Show in-game objective countdowns",
        "当前模式": "Current mode",
        "大乱斗": "ARAM",
        "召唤师峡谷": "Summoner's Rift",
        "等待对局": "Waiting for a game",
        "等待对局数据…": "Waiting for game data…",
        "史诗野怪使用 Riot 对局事件自动计时。": "Epic monsters are timed automatically from Riot game events.",
        "按住 Tab 约 1 秒，同步计分板上的血包倒计时。": "Hold Tab for about one second to sync the health relic countdowns shown on the scoreboard.",
        "正在读取 Tab 计分板…": "Reading the Tab scoreboard…",
        "已从 Tab 计分板同步：当前没有血包倒计时。": "Synced from the Tab scoreboard: no health relics are currently counting down.",
        "已从 Tab 计分板同步 %d 个血包倒计时。": "Synced %d health relic countdowns from the Tab scoreboard.",
        "当前模式没有启用目标计时。": "Objective timers are not enabled for this mode.",
        "峡谷的小龙、远古巨龙和纳什男爵会读取 Riot 本地事件自动计时；巢虫与先锋显示首次刷新。": "Dragon, Elder Dragon, and Baron use Riot's local events automatically; Void Grubs and Rift Herald show their first spawn.",
        "大乱斗中按住 Tab 约 1 秒，应用会读取计分板自带的血包时间并自动校准；关闭计分板后继续倒数。": "In ARAM, hold Tab for about one second. The app reads the built-in relic timers and keeps counting down after the scoreboard closes.",
        "小龙": "Dragon",
        "远古巨龙": "Elder Dragon",
        "虚空巢虫": "Void Grubs",
        "峡谷先锋": "Rift Herald",
        "纳什男爵": "Baron Nashor",
        "血包 %d": "Relic %d",
        "血包首次刷新": "First relic spawn",
        "血包 %d · %d:%02d": "Relic %d · %d:%02d",
        "Wexi LoL 目标计时": "Wexi LoL objective timers",
        "已授权": "Allowed",
        "未授权": "Not allowed",
        "打开系统权限设置": "Open system permission settings",
        "只读取英雄联盟游戏窗口，用于识别海克斯选择、技能加点和 Tab 计分板计时；不会保存或上传画面。": "Reads only the League of Legends game window to detect augment choices, skill upgrades, and Tab scoreboard timers. Frames are never saved or uploaded.",
        "技能提示": "Skill hints",
        "状态与快捷键": "Status and shortcuts",
        "技能加点": "Skill order",
        "来源提供 1–%d 级顺序 · 最常用方案 · %d 场样本": "Levels 1–%d · Most popular build · %d games",
        "白银": "Silver",
        "黄金": "Gold",
        "棱彩": "Prismatic",
        "未知稀有度": "Unknown rarity",
        "%@，评级 %@": "%@, tier %@",
        "全球区服 · 游戏原位提示设置": "Global regions · In-game hint settings",
        "搜索英雄：": "Search champions:",
        "透明度": "Opacity",
        "校准技能＋位置": "Calibrate skill positions",
        "开启录屏权限": "Enable screen recording",
        "保存技能位置": "Save skill positions",
        "取消校准": "Cancel calibration",
        "⌥⌘K 开始/保存校准\nTab 显示玩家资料并同步大乱斗血包计时\n⌘M 收起设置到菜单栏": "⌥⌘K Start / save calibration\nTab Show player profiles and sync ARAM relic timers\n⌘M Hide settings to menu bar",
        "自动识别英雄 · OP.GG 全球数据 · 版本 %@": "Auto-detect champion · OP.GG global data · Patch %@",
        "刷新": "Refresh",
        "获取时间 %@": "Updated %@",
        "海克斯评级": "Augment tiers",
        "参考列表": "Reference list",
        "搜索海克斯：": "Search augments:",
        "下方是当前英雄的静态评级。游戏内只标注识别到的三张卡片，不显示常驻列表。": "These are static tiers for this champion. In-game hints label detected augment cards only.",
        "OP.GG 加点来源 ↗": "OP.GG skill source ↗",
        "OP.GG 海克斯来源 ↗": "OP.GG augment source ↗",
        "技能＋优先自动定位；识别不到时可拖动校准一次。": "Skill positions are detected automatically. Drag the markers to calibrate if detection fails.",
        "已保存技能＋位置；更改游戏界面缩放后请重新校准。": "Skill positions saved. Recalibrate after changing the game HUD scale.",
        "切回游戏，将四个标记分别拖到 Q/W/E/R 的＋，然后按 ⌥⌘K 保存。": "Return to the game, drag all four markers onto the Q/W/E/R upgrade buttons, then press ⌥⌘K to save.",
        "请先在游戏内分别拖动四个标记，再保存位置。": "Drag all four markers in-game before saving their positions.",
        "校准已取消。": "Calibration cancelled.",
        "等待游戏前台 · 提示已隐藏": "Waiting for the game to be active · Hints hidden",
        " ＋ 拖动": " + Drag",
        "推荐 %@ ↓": "Level %@ ↓",
        "正在游戏对应位置显示提示": "Showing hints at the corresponding in-game positions",
        "有技能点可用；等待定位＋，可用下方按钮校准位置。": "Skill points available. Waiting to locate upgrade buttons; use calibration if needed.",
        "等待升级或海克斯选择 · 平时不显示任何面板": "Waiting for a level-up or augment choice · Hints otherwise hidden",
        "校准技能＋": "Calibrate skill positions",
        "Wexi LoL 游戏提示": "Wexi LoL in-game hints",
        "等待对局 · 平时不显示提示": "Waiting for a game · Hints hidden",
        "选择英雄后加载攻略": "Select a champion to load a guide",
        "正在读取 OP.GG 攻略…": "Loading OP.GG guide…",
        "已加载 %d 个海克斯评级 · OP.GG 全球数据": "Loaded %d augment tiers · OP.GG global data",
        "已加载 %d 套出装路线 · OP.GG 全球数据": "Loaded %d build routes · OP.GG global data",
        "攻略加载失败；网络或网页结构可能变化，请重试或查看原网页。": "Guide loading failed. Check your connection, retry, or visit the source page.",
        "Wexi LoL · 设置": "Wexi LoL · Settings",
        "Wexi LoL 设置": "Wexi LoL settings",
        "打开设置": "Open settings",
        "收起设置到菜单栏": "Hide settings to menu bar",
        "屏幕录制权限": "Screen recording permission",
        "保存技能位置（⌥⌘K）": "Save skill positions (⌥⌘K)",
        "退出 Wexi LoL": "Quit Wexi LoL",
        "快捷键不可用，请使用菜单栏控制。": "Keyboard shortcut unavailable. Use the menu bar controls.",
        "部分快捷键注册失败或已被占用，请使用菜单栏控制。": "A keyboard shortcut could not be registered or is already in use. Use the menu bar controls.",
    ]
}
