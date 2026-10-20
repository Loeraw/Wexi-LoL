import Foundation
import Combine

enum AppLanguage: String, CaseIterable, Identifiable {
    case chinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case english = "en"
    case korean = "ko"
    case japanese = "ja"
    case french = "fr"
    case german = "de"
    case spanish = "es"
    case portuguese = "pt-BR"
    case russian = "ru"
    case turkish = "tr"
    case polish = "pl"
    case italian = "it"
    case thai = "th"
    case vietnamese = "vi"

    var id: String { rawValue }
    static let interfaceCases: [AppLanguage] = [
        .chinese, .traditionalChinese, .english, .korean, .japanese, .french,
        .german, .spanish, .portuguese, .russian, .turkish, .vietnamese
    ]
    var title: String {
        switch self {
        case .chinese: return "简体中文"
        case .traditionalChinese: return "繁體中文"
        case .english: return "English"
        case .korean: return "한국어"
        case .japanese: return "日本語"
        case .french: return "Français"
        case .german: return "Deutsch"
        case .spanish: return "Español"
        case .portuguese: return "Português (Brasil)"
        case .russian: return "Русский"
        case .turkish: return "Türkçe"
        case .polish: return "Polski"
        case .italian: return "Italiano"
        case .thai: return "ไทย"
        case .vietnamese: return "Tiếng Việt"
        }
    }
    var locale: Locale { Locale(identifier: rawValue) }
    var opggPrefix: String {
        switch self {
        case .english: return ""
        case .chinese: return "/zh-cn"
        case .traditionalChinese: return "/zh-tw"
        case .portuguese: return "/pt"
        default: return "/\(rawValue.lowercased())"
        }
    }
    var acceptLanguage: String {
        switch self {
        case .chinese: return "zh-CN,zh;q=0.9"
        case .traditionalChinese: return "zh-TW,zh;q=0.9"
        case .english: return "en-US,en;q=0.9"
        case .korean: return "ko-KR,ko;q=0.9"
        case .japanese: return "ja-JP,ja;q=0.9"
        case .french: return "fr-FR,fr;q=0.9"
        case .german: return "de-DE,de;q=0.9"
        case .spanish: return "es-ES,es;q=0.9"
        case .portuguese: return "pt-BR,pt;q=0.9"
        case .russian: return "ru-RU,ru;q=0.9"
        case .turkish: return "tr-TR,tr;q=0.9"
        case .polish: return "pl-PL,pl;q=0.9"
        case .italian: return "it-IT,it;q=0.9"
        case .thai: return "th-TH,th;q=0.9"
        case .vietnamese: return "vi-VN,vi;q=0.9"
        }
    }
    var visionLanguages: [String] {
        let primary: String
        switch self {
        case .chinese: primary = "zh-Hans"
        case .traditionalChinese: primary = "zh-Hant"
        case .english: primary = "en-US"
        case .korean: primary = "ko-KR"
        case .japanese: primary = "ja-JP"
        case .french: primary = "fr-FR"
        case .german: primary = "de-DE"
        case .spanish: primary = "es-ES"
        case .portuguese: primary = "pt-BR"
        case .russian: primary = "ru-RU"
        case .turkish: primary = "tr-TR"
        case .polish: primary = "pl-PL"
        case .italian: primary = "it-IT"
        case .thai: primary = "th-TH"
        case .vietnamese: primary = "vi-VT"
        }
        return primary == "en-US" ? [primary] : [primary, "en-US"]
    }
}

@MainActor final class LanguageSettings: ObservableObject {
    static let shared = LanguageSettings()
    static let preferenceKey = "interfaceLanguage"
    static let gamePreferenceKey = "gameClientLanguage"
    static let didChange = Notification.Name("WexiLoL.languageDidChange")

    @Published var selection: AppLanguage {
        didSet {
            guard selection != oldValue else { return }
            UserDefaults.standard.set(selection.rawValue, forKey: Self.preferenceKey)
            NotificationCenter.default.post(name: Self.didChange, object: self)
        }
    }
    @Published var gameSelection: String {
        didSet {
            guard gameSelection != oldValue else { return }
            UserDefaults.standard.set(gameSelection, forKey: Self.gamePreferenceKey)
            NotificationCenter.default.post(name: Self.didChange, object: self)
        }
    }
    var gameLanguage: AppLanguage {
        gameSelection == "follow" ? selection : (AppLanguage(rawValue: gameSelection) ?? selection)
    }

    private init() {
        if UserDefaults.standard.object(forKey: Self.preferenceKey) == nil,
           let previous = UserDefaults(suiteName: "dev.local.riftoverlay")?.string(forKey: Self.preferenceKey) {
            UserDefaults.standard.set(previous, forKey: Self.preferenceKey)
        }
        // Preserve the original Chinese interface until the user chooses otherwise.
        selection = AppLanguage(rawValue: UserDefaults.standard.string(forKey: Self.preferenceKey) ?? "") ?? .chinese
        let savedGame = UserDefaults.standard.string(forKey: Self.gamePreferenceKey) ?? "follow"
        gameSelection = savedGame == "follow" || AppLanguage(rawValue: savedGame) != nil ? savedGame : "follow"
    }
}

@MainActor enum L10n {
    static func text(_ key: String, _ arguments: CVarArg...) -> String {
        let language = LanguageSettings.shared.selection
        let format = language == .chinese ? key : (localized[language]?[key] ?? L10nSupplemental.text(key, language: language) ?? english[key] ?? key)
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: language.locale, arguments: arguments)
    }

    // Frequently used labels live here; the complete interface catalog is in
    // LocalizationSupplemental.swift.
    private static let localized: [AppLanguage: [String: String]] = [
        .traditionalChinese: [
            "语言": "語言", "游戏客户端语言": "遊戲客戶端語言", "跟随 Wexi 语言": "跟隨 Wexi 語言",
            "选择与英雄联盟客户端相同的语言，用于读取海克斯名称。": "請選擇與英雄聯盟客戶端相同的語言，用於讀取增幅裝置名稱。",
            "设置": "設定", "返回攻略": "返回攻略", "英雄": "英雄", "界面": "介面", "提示透明度": "提示透明度",
            "屏幕录制": "螢幕錄製", "目标计时": "目標計時", "出装推荐": "出裝推薦", "对局玩家": "對局玩家",
            "玩家区服": "玩家伺服器", "自动检测": "自動偵測", "技能提示": "技能提示", "状态与快捷键": "狀態與快捷鍵",
            "推荐出装": "推薦出裝", "按场次排序": "依場次排序", "大乱斗混乱": "隨機單中：混亂",
            "极地大乱斗": "隨機單中", "斗魂竞技场": "競技場", "排位模式": "積分模式", "下一件": "下一件",
            "刷新": "重新整理", "海克斯评级": "增幅裝置評級", "参考列表": "參考列表", "搜索英雄：": "搜尋英雄：",
            "搜索海克斯：": "搜尋增幅裝置：", "已授权": "已授權", "未授权": "未授權", "开启录屏权限": "啟用螢幕錄製權限",
            "打开系统权限设置": "開啟系統權限設定", "校准技能＋位置": "校準技能＋位置", "保存技能位置": "儲存技能位置",
            "取消校准": "取消校準", "胜率 %.1f%%": "勝率 %.1f%%", "选用率 %.1f%%": "選用率 %.1f%%", "选用率 %.1f%% · %d 场": "選用率 %.1f%% · %d 場"
        ],
        .korean: [
            "语言": "언어", "游戏客户端语言": "게임 클라이언트 언어", "跟随 Wexi 语言": "Wexi 언어 따르기",
            "选择与英雄联盟客户端相同的语言，用于读取海克斯名称。": "증강체 이름을 읽으려면 League 클라이언트와 같은 언어를 선택하세요.",
            "设置": "설정", "返回攻略": "가이드로 돌아가기", "英雄": "챔피언", "界面": "인터페이스", "提示透明度": "오버레이 투명도",
            "屏幕录制": "화면 기록", "目标计时": "오브젝트 타이머", "出装推荐": "아이템 빌드", "对局玩家": "게임 플레이어",
            "玩家区服": "플레이어 서버", "自动检测": "자동 감지", "技能提示": "스킬 안내", "状态与快捷键": "상태 및 단축키",
            "推荐出装": "추천 빌드", "按场次排序": "게임 수순", "大乱斗混乱": "무작위 총력전: 아수라장",
            "极地大乱斗": "무작위 총력전", "斗魂竞技场": "아레나", "排位模式": "랭크", "下一件": "다음",
            "刷新": "새로고침", "海克斯评级": "증강체 등급", "参考列表": "참고 목록", "搜索英雄：": "챔피언 검색:",
            "搜索海克斯：": "증강체 검색:", "已授权": "허용됨", "未授权": "허용되지 않음", "开启录屏权限": "화면 기록 허용",
            "打开系统权限设置": "시스템 권한 설정 열기", "校准技能＋位置": "스킬 위치 보정", "保存技能位置": "스킬 위치 저장",
            "取消校准": "보정 취소", "胜率 %.1f%%": "승률 %.1f%%", "选用率 %.1f%% · %d 场": "픽률 %.1f%% · %d게임"
        ],
        .japanese: [
            "语言": "言語", "游戏客户端语言": "ゲームクライアントの言語", "跟随 Wexi 语言": "Wexiの言語に合わせる",
            "选择与英雄联盟客户端相同的语言，用于读取海克斯名称。": "オーグメント名を読み取るため、Leagueクライアントと同じ言語を選択してください。",
            "设置": "設定", "返回攻略": "ガイドに戻る", "英雄": "チャンピオン", "界面": "インターフェース", "提示透明度": "オーバーレイの透明度",
            "屏幕录制": "画面収録", "目标计时": "オブジェクトタイマー", "出装推荐": "ビルド提案", "对局玩家": "対戦プレイヤー",
            "玩家区服": "プレイヤー地域", "自动检测": "自動検出", "技能提示": "スキルガイド", "状态与快捷键": "状態とショートカット",
            "推荐出装": "おすすめビルド", "按场次排序": "試合数順", "大乱斗混乱": "ARAM：メイヘム",
            "极地大乱斗": "ARAM", "斗魂竞技场": "アリーナ", "排位模式": "ランク", "下一件": "次",
            "刷新": "更新", "海克斯评级": "オーグメント評価", "参考列表": "参考リスト", "搜索英雄：": "チャンピオンを検索:",
            "搜索海克斯：": "オーグメントを検索:", "已授权": "許可済み", "未授权": "未許可", "开启录屏权限": "画面収録を許可",
            "打开系统权限设置": "システム権限設定を開く", "校准技能＋位置": "スキル位置を調整", "保存技能位置": "スキル位置を保存",
            "取消校准": "調整をキャンセル", "胜率 %.1f%%": "勝率 %.1f%%", "选用率 %.1f%% · %d 场": "選択率 %.1f%% · %d試合"
        ],
        .french: [
            "语言": "Langue", "游戏客户端语言": "Langue du client de jeu", "跟随 Wexi 语言": "Suivre la langue de Wexi",
            "选择与英雄联盟客户端相同的语言，用于读取海克斯名称。": "Choisissez la langue du client League pour lire les noms des optimisations.",
            "设置": "Réglages", "返回攻略": "Retour au guide", "英雄": "Champions", "界面": "Interface", "提示透明度": "Opacité",
            "屏幕录制": "Enregistrement de l’écran", "目标计时": "Chronos des objectifs", "出装推荐": "Build recommandé", "对局玩家": "Joueurs",
            "玩家区服": "Région", "自动检测": "Détection auto", "技能提示": "Compétences", "状态与快捷键": "État et raccourcis",
            "推荐出装": "Build recommandé", "按场次排序": "Trié par parties", "大乱斗混乱": "ARAM : Chaos",
            "极地大乱斗": "ARAM", "斗魂竞技场": "Arène", "排位模式": "Classé", "下一件": "Suivant",
            "刷新": "Actualiser", "海克斯评级": "Niveaux d’optimisations", "参考列表": "Liste de référence", "搜索英雄：": "Rechercher un champion :",
            "搜索海克斯：": "Rechercher une optimisation :", "已授权": "Autorisé", "未授权": "Non autorisé", "开启录屏权限": "Autoriser l’enregistrement",
            "打开系统权限设置": "Ouvrir les autorisations système", "校准技能＋位置": "Calibrer les compétences", "保存技能位置": "Enregistrer les positions",
            "取消校准": "Annuler", "胜率 %.1f%%": "Taux de victoire %.1f%%", "选用率 %.1f%%": "Sélection %.1f%%", "选用率 %.1f%% · %d 场": "Sélection %.1f%% · %d parties",
            "提示大小": "Taille des indications", "更新": "Mises à jour", "当前版本 %@": "Version actuelle %@",
            "检查更新": "Rechercher des mises à jour", "正在检查更新…": "Recherche de mises à jour…", "已是最新版本": "Vous avez la dernière version",
            "发现新版本 v%@": "Nouvelle version v%@ disponible", "下载 v%@": "Télécharger v%@", "检查更新失败，请稍后重试。": "La recherche a échoué. Réessayez plus tard.",
            "复制诊断信息": "Copier les diagnostics", "诊断信息已复制；不包含截图或玩家名称。": "Diagnostics copiés ; aucune capture ni aucun nom de joueur.",
            "复制应用状态、权限、窗口尺寸和加载结果，便于排查问题；不包含截图、OCR 文字或玩家名称。": "Copie l’état de l’app, les autorisations, la taille de la fenêtre et les résultats de chargement pour le dépannage, sans capture, texte OCR ni nom de joueur.",
            "当前玩家区服": "Région actuelle", "等待检测": "En attente de détection",
            "无法自动识别区服，请在设置中选择玩家区服。": "Impossible de détecter la région. Choisissez-la dans les réglages.",
            "显示玩家段位与战绩": "Afficher les rangs et l’historique des joueurs",
            "Loading 阶段只读取一次玩家资料并保存在本局缓存；进入游戏后按住 Tab 只切换显示，不会重新请求 OP.GG。": "Les profils sont chargés une seule fois pendant l’écran de chargement et conservés pour la partie. En jeu, maintenir Tab affiche ou masque les profils sans interroger de nouveau OP.GG.",
            "等待加载界面的玩家名单…": "En attente des joueurs de l’écran de chargement…",
            "正在读取玩家资料 0/%d…": "Chargement des profils 0/%d…", "正在读取玩家资料 %d/%d…": "Chargement des profils %d/%d…",
            "玩家资料已读取 · 按 Tab 显示": "Profils chargés · Maintenez Tab pour les afficher",
            "玩家资料已读取 · 进入游戏后按 Tab 显示": "Profils chargés · Maintenez Tab après le début de la partie",
            "OP.GG 资料可能已过期": "Les données OP.GG sont peut-être obsolètes",
            "无公开数据": "Aucune donnée publique", "读取中…": "Chargement…", "未定级": "Non classé",
            "段位 · 赛季胜率 · 最近战绩": "Rang · Taux de victoire de la saison · Parties récentes",
            "当前对局玩家": "Joueurs de la partie", "蓝方": "Équipe bleue", "红方": "Équipe rouge",
            "显示玩家资料": "Afficher les joueurs", "隐藏玩家资料": "Masquer les joueurs", "Wexi LoL 当前对局玩家": "Joueurs de la partie · Wexi LoL",
            "IRON": "Fer", "BRONZE": "Bronze", "SILVER": "Argent", "GOLD": "Or", "PLATINUM": "Platine",
            "EMERALD": "Émeraude", "DIAMOND": "Diamant", "MASTER": "Maître", "GRANDMASTER": "Grand Maître", "CHALLENGER": "Challenger",
            "显示推荐出装与胜率": "Afficher le build recommandé et son taux de victoire",
            "显示推荐出装": "Afficher le build recommandé", "隐藏推荐出装": "Masquer le build recommandé",
            "根据当前已购买的核心装备匹配 OP.GG 主流三件套，并标出下一件；胜率是该完整路线的统计。": "Associe vos objets principaux à un build populaire de trois objets sur OP.GG et indique le prochain achat. Le taux de victoire correspond au build complet.",
            "已加载出装路线": "Builds chargés", "%d 套": "%d builds", "OP.GG 出装来源 ↗": "Source des builds OP.GG ↗",
            "斗魂评级根据同稀有度海克斯的 OP.GG 胜率与场次计算，并非 OP.GG 官方分级。": "Les niveaux d’Arène sont calculés avec le taux de victoire et le nombre de parties OP.GG pour une même rareté. Ce ne sont pas des niveaux officiels OP.GG.",
            "胜率 %.1f%% · 选用率 %.1f%% · %d 场": "Taux de victoire %.1f%% · Sélection %.1f%% · %d parties",
            "OP.GG · 选用率 %.1f%% · %d 场": "OP.GG · Sélection %.1f%% · %d parties", "Wexi LoL 推荐出装": "Build recommandé · Wexi LoL",
            "显示游戏内目标倒计时": "Afficher les chronos des objectifs en jeu", "当前模式": "Mode actuel",
            "大乱斗": "ARAM", "召唤师峡谷": "Faille de l’invocateur", "等待对局": "En attente d’une partie", "等待对局数据…": "En attente des données de la partie…",
            "史诗野怪使用 Riot 对局事件自动计时。": "Les monstres épiques sont chronométrés automatiquement à partir des événements locaux de Riot.",
            "按住 Tab 约 1 秒，同步计分板上的血包倒计时。": "Maintenez Tab environ une seconde pour synchroniser les chronos des reliques de soin du tableau des scores.",
            "正在读取 Tab 计分板…": "Lecture du tableau des scores…",
            "已从 Tab 计分板同步：当前没有血包倒计时。": "Tableau des scores synchronisé : aucune relique de soin n’est en cours de recharge.",
            "已从 Tab 计分板同步 %d 个血包倒计时。": "%d chronos de reliques de soin synchronisés depuis le tableau des scores.",
            "当前模式没有启用目标计时。": "Les chronos des objectifs ne sont pas disponibles dans ce mode.",
            "峡谷的小龙、远古巨龙和纳什男爵会读取 Riot 本地事件自动计时；巢虫与先锋显示首次刷新。": "Le dragon, le dragon ancestral et le baron sont chronométrés à partir des événements locaux de Riot. Les larves du Néant et le héraut affichent leur première apparition.",
            "大乱斗中按住 Tab 约 1 秒，应用会读取计分板自带的血包时间并自动校准；关闭计分板后继续倒数。": "En ARAM, maintenez Tab environ une seconde. L’app lit les chronos des reliques de soin du tableau des scores et poursuit le décompte après sa fermeture.",
            "小龙": "Dragon", "远古巨龙": "Dragon ancestral", "虚空巢虫": "Larves du Néant", "峡谷先锋": "Héraut de la Faille", "纳什男爵": "Baron Nashor",
            "血包 %d": "Relique %d", "血包首次刷新": "Première apparition des reliques", "血包 %d · %d:%02d": "Relique %d · %d:%02d", "Wexi LoL 目标计时": "Chronos des objectifs · Wexi LoL",
            "只读取英雄联盟游戏窗口，用于识别海克斯选择、技能加点和 Tab 计分板计时；不会保存或上传画面。": "Lit uniquement la fenêtre de League of Legends pour reconnaître les optimisations, les améliorations de compétences et les chronos du tableau des scores. Aucune image n’est enregistrée ni envoyée.",
            "技能加点": "Ordre des compétences", "来源提供 1–%d 级顺序 · 最常用方案 · %d 场样本": "Niveaux 1 à %d · Ordre le plus populaire · %d parties",
            "白银": "Argent", "黄金": "Or", "棱彩": "Prismatique", "未知稀有度": "Rareté inconnue", "%@，评级 %@": "%@, niveau %@",
            "全球区服 · 游戏原位提示设置": "Toutes les régions · Réglages des indications en jeu", "透明度": "Opacité",
            "⌥⌘K 开始/保存校准\nTab 显示玩家资料并同步大乱斗血包计时\n⌘M 收起设置到菜单栏": "⌥⌘K Démarrer / enregistrer le calibrage\nTab Afficher les profils et synchroniser les reliques ARAM\n⌘M Réduire les réglages dans la barre des menus",
            "自动识别英雄 · OP.GG 全球数据 · 版本 %@": "Détection automatique du champion · Données mondiales OP.GG · Patch %@",
            "获取时间 %@": "Mis à jour %@",
            "下方是当前英雄的静态评级。游戏内只标注识别到的三张卡片，不显示常驻列表。": "Voici les niveaux statiques de ce champion. En jeu, seules les trois cartes détectées sont annotées.",
            "OP.GG 加点来源 ↗": "Source des compétences OP.GG ↗", "OP.GG 海克斯来源 ↗": "Source des optimisations OP.GG ↗",
            "技能＋优先自动定位；识别不到时可拖动校准一次。": "Les boutons d’amélioration sont localisés automatiquement. Faites glisser les repères une fois si la détection échoue.",
            "已保存技能＋位置；更改游戏界面缩放后请重新校准。": "Positions enregistrées. Recalibrez après avoir modifié l’échelle de l’interface du jeu.",
            "切回游戏，将四个标记分别拖到 Q/W/E/R 的＋，然后按 ⌥⌘K 保存。": "Retournez au jeu, placez les quatre repères sur les boutons + de Q/W/E/R, puis appuyez sur ⌥⌘K pour enregistrer.",
            "请先在游戏内分别拖动四个标记，再保存位置。": "Placez d’abord les quatre repères dans le jeu avant d’enregistrer.",
            "校准已取消。": "Calibrage annulé.", "等待游戏前台 · 提示已隐藏": "En attente du jeu au premier plan · Indications masquées",
            " ＋ 拖动": " + Glisser", "推荐 %@ ↓": "Niveau %@ ↓", "正在游戏对应位置显示提示": "Indications affichées aux emplacements correspondants dans le jeu",
            "有技能点可用；等待定位＋，可用下方按钮校准位置。": "Un point de compétence est disponible. Recherche des boutons + ; utilisez le calibrage si nécessaire.",
            "等待升级或海克斯选择 · 平时不显示任何面板": "En attente d’un niveau ou d’un choix d’optimisation · Indications masquées le reste du temps",
            "校准技能＋": "Calibrer les compétences", "Wexi LoL 游戏提示": "Indications en jeu · Wexi LoL", "等待对局 · 平时不显示提示": "En attente d’une partie · Indications masquées",
            "选择英雄后加载攻略": "Sélectionnez un champion pour charger le guide", "正在读取 OP.GG 攻略…": "Chargement du guide OP.GG…",
            "已加载 %d 个海克斯评级 · OP.GG 全球数据": "%d niveaux d’optimisations chargés · Données mondiales OP.GG",
            "已加载 %d 套出装路线 · OP.GG 全球数据": "%d builds chargés · Données mondiales OP.GG",
            "攻略加载失败；网络或网页结构可能变化，请重试或查看原网页。": "Échec du chargement du guide. Vérifiez votre connexion, réessayez ou consultez la page source.",
            "Wexi LoL · 设置": "Wexi LoL · Réglages", "Wexi LoL 设置": "Réglages Wexi LoL", "打开设置": "Ouvrir les réglages",
            "收起设置到菜单栏": "Réduire les réglages dans la barre des menus", "屏幕录制权限": "Autorisation d’enregistrement de l’écran",
            "保存技能位置（⌥⌘K）": "Enregistrer les positions (⌥⌘K)", "退出 Wexi LoL": "Quitter Wexi LoL",
            "快捷键不可用，请使用菜单栏控制。": "Le raccourci clavier n’est pas disponible. Utilisez les commandes de la barre des menus.",
            "部分快捷键注册失败或已被占用，请使用菜单栏控制。": "Un raccourci n’a pas pu être enregistré ou est déjà utilisé. Utilisez les commandes de la barre des menus.",
            "Wexi LoL 与 Riot Games 无关联，也不代表 Riot Games 或其官方相关人员的观点。League of Legends、Riot Games 及相关资产是 Riot Games, Inc. 的商标或注册商标。": "Wexi LoL n’est ni approuvé ni affilié à Riot Games et ne reflète pas les opinions de Riot Games ou des personnes officiellement impliquées dans ses produits. League of Legends, Riot Games et les éléments associés sont des marques de Riot Games, Inc.",
            "OP.GG · 全球": "OP.GG · Monde"
        ],
        .german: [
            "语言": "Sprache", "游戏客户端语言": "Spielclient-Sprache", "跟随 Wexi 语言": "Wexi-Sprache verwenden",
            "选择与英雄联盟客户端相同的语言，用于读取海克斯名称。": "Wähle die Sprache des League-Clients, damit Augment-Namen erkannt werden.",
            "设置": "Einstellungen", "返回攻略": "Zurück zum Guide", "英雄": "Champions", "界面": "Oberfläche", "提示透明度": "Overlay-Deckkraft",
            "屏幕录制": "Bildschirmaufnahme", "目标计时": "Ziel-Timer", "出装推荐": "Build-Empfehlung", "对局玩家": "Mitspieler",
            "玩家区服": "Spielerregion", "自动检测": "Automatisch", "技能提示": "Fähigkeiten", "状态与快捷键": "Status und Kurzbefehle",
            "推荐出装": "Empfohlener Build", "按场次排序": "Nach Spielen", "大乱斗混乱": "ARAM: Mayhem",
            "极地大乱斗": "ARAM", "斗魂竞技场": "Arena", "排位模式": "Rangliste", "下一件": "Nächstes",
            "刷新": "Aktualisieren", "海克斯评级": "Augment-Stufen", "参考列表": "Referenzliste", "搜索英雄：": "Champions suchen:",
            "搜索海克斯：": "Augments suchen:", "已授权": "Erlaubt", "未授权": "Nicht erlaubt", "开启录屏权限": "Bildschirmaufnahme erlauben",
            "打开系统权限设置": "Systemberechtigungen öffnen", "校准技能＋位置": "Fähigkeiten kalibrieren", "保存技能位置": "Positionen speichern",
            "取消校准": "Abbrechen", "胜率 %.1f%%": "Siegesrate %.1f%%", "选用率 %.1f%% · %d 场": "Auswahlrate %.1f%% · %d Spiele"
        ],
        .spanish: [
            "语言": "Idioma", "游戏客户端语言": "Idioma del cliente del juego", "跟随 Wexi 语言": "Usar idioma de Wexi",
            "选择与英雄联盟客户端相同的语言，用于读取海克斯名称。": "Elige el idioma del cliente de League para leer los nombres de los aumentos.",
            "设置": "Ajustes", "返回攻略": "Volver a la guía", "英雄": "Campeones", "界面": "Interfaz", "提示透明度": "Opacidad",
            "屏幕录制": "Grabación de pantalla", "目标计时": "Temporizadores", "出装推荐": "Build recomendada", "对局玩家": "Jugadores",
            "玩家区服": "Región", "自动检测": "Detección automática", "技能提示": "Habilidades", "状态与快捷键": "Estado y atajos",
            "推荐出装": "Build recomendada", "按场次排序": "Ordenado por partidas", "大乱斗混乱": "ARAM: Caos",
            "极地大乱斗": "ARAM", "斗魂竞技场": "Arena", "排位模式": "Clasificatoria", "下一件": "Siguiente",
            "刷新": "Actualizar", "海克斯评级": "Niveles de aumentos", "参考列表": "Lista de referencia", "搜索英雄：": "Buscar campeones:",
            "搜索海克斯：": "Buscar aumentos:", "已授权": "Permitido", "未授权": "Sin permiso", "开启录屏权限": "Permitir grabación",
            "打开系统权限设置": "Abrir permisos del sistema", "校准技能＋位置": "Calibrar habilidades", "保存技能位置": "Guardar posiciones",
            "取消校准": "Cancelar", "胜率 %.1f%%": "Tasa de victoria %.1f%%", "选用率 %.1f%% · %d 场": "Selección %.1f%% · %d partidas"
        ],
        .portuguese: [
            "语言": "Idioma", "游戏客户端语言": "Idioma do cliente do jogo", "跟随 Wexi 语言": "Usar idioma do Wexi",
            "选择与英雄联盟客户端相同的语言，用于读取海克斯名称。": "Escolha o idioma do cliente do League para ler os nomes dos aprimoramentos.",
            "设置": "Configurações", "返回攻略": "Voltar ao guia", "英雄": "Campeões", "界面": "Interface", "提示透明度": "Opacidade",
            "屏幕录制": "Gravação da tela", "目标计时": "Temporizadores", "出装推荐": "Build recomendada", "对局玩家": "Jogadores",
            "玩家区服": "Região", "自动检测": "Detecção automática", "技能提示": "Habilidades", "状态与快捷键": "Status e atalhos",
            "推荐出装": "Build recomendada", "按场次排序": "Ordenado por partidas", "大乱斗混乱": "ARAM: Mayhem",
            "极地大乱斗": "ARAM", "斗魂竞技场": "Arena", "排位模式": "Ranqueada", "下一件": "Próximo",
            "刷新": "Atualizar", "海克斯评级": "Níveis de aprimoramentos", "参考列表": "Lista de referência", "搜索英雄：": "Buscar campeões:",
            "搜索海克斯：": "Buscar aprimoramentos:", "已授权": "Permitido", "未授权": "Não permitido", "开启录屏权限": "Permitir gravação",
            "打开系统权限设置": "Abrir permissões do sistema", "校准技能＋位置": "Calibrar habilidades", "保存技能位置": "Salvar posições",
            "取消校准": "Cancelar", "胜率 %.1f%%": "Taxa de vitória %.1f%%", "选用率 %.1f%% · %d 场": "Escolha %.1f%% · %d partidas"
        ],
        .russian: [
            "语言": "Язык", "游戏客户端语言": "Язык игрового клиента", "跟随 Wexi 语言": "Как в Wexi",
            "选择与英雄联盟客户端相同的语言，用于读取海克斯名称。": "Выберите язык клиента League для распознавания названий усилений.",
            "设置": "Настройки", "返回攻略": "Назад к гайду", "英雄": "Чемпионы", "界面": "Интерфейс", "提示透明度": "Прозрачность",
            "屏幕录制": "Запись экрана", "目标计时": "Таймеры целей", "出装推荐": "Рекомендуемая сборка", "对局玩家": "Игроки",
            "玩家区服": "Регион", "自动检测": "Автоопределение", "技能提示": "Умения", "状态与快捷键": "Статус и клавиши",
            "推荐出装": "Рекомендуемая сборка", "按场次排序": "По числу игр", "大乱斗混乱": "ARAM: Хаос",
            "极地大乱斗": "ARAM", "斗魂竞技场": "Арена", "排位模式": "Рейтинг", "下一件": "Далее",
            "刷新": "Обновить", "海克斯评级": "Рейтинг усилений", "参考列表": "Справочник", "搜索英雄：": "Поиск чемпиона:",
            "搜索海克斯：": "Поиск усиления:", "已授权": "Разрешено", "未授权": "Не разрешено", "开启录屏权限": "Разрешить запись",
            "打开系统权限设置": "Открыть системные разрешения", "校准技能＋位置": "Калибровать умения", "保存技能位置": "Сохранить позиции",
            "取消校准": "Отмена", "胜率 %.1f%%": "Победы %.1f%%", "选用率 %.1f%% · %d 场": "Выбор %.1f%% · %d игр"
        ],
        .turkish: [
            "语言": "Dil", "游戏客户端语言": "Oyun istemcisi dili", "跟随 Wexi 语言": "Wexi dilini kullan",
            "选择与英雄联盟客户端相同的语言，用于读取海克斯名称。": "Güçlendirme adlarını okumak için League istemcisiyle aynı dili seçin.",
            "设置": "Ayarlar", "返回攻略": "Rehbere dön", "英雄": "Şampiyonlar", "界面": "Arayüz", "提示透明度": "Saydamlık",
            "屏幕录制": "Ekran kaydı", "目标计时": "Hedef sayaçları", "出装推荐": "Dizilim önerisi", "对局玩家": "Oyuncular",
            "玩家区服": "Oyuncu bölgesi", "自动检测": "Otomatik algıla", "技能提示": "Yetenekler", "状态与快捷键": "Durum ve kısayollar",
            "推荐出装": "Önerilen dizilim", "按场次排序": "Oyun sayısına göre", "大乱斗混乱": "ARAM: Kargaşa",
            "极地大乱斗": "ARAM", "斗魂竞技场": "Arena", "排位模式": "Dereceli", "下一件": "Sonraki",
            "刷新": "Yenile", "海克斯评级": "Güçlendirme seviyeleri", "参考列表": "Referans listesi", "搜索英雄：": "Şampiyon ara:",
            "搜索海克斯：": "Güçlendirme ara:", "已授权": "İzin verildi", "未授权": "İzin yok", "开启录屏权限": "Ekran kaydına izin ver",
            "打开系统权限设置": "Sistem izinlerini aç", "校准技能＋位置": "Yetenekleri kalibre et", "保存技能位置": "Konumları kaydet",
            "取消校准": "İptal", "胜率 %.1f%%": "Kazanma oranı %.1f%%", "选用率 %.1f%% · %d 场": "Seçilme %.1f%% · %d oyun"
        ],
        .vietnamese: [
            "语言": "Ngôn ngữ", "游戏客户端语言": "Ngôn ngữ client trò chơi", "跟随 Wexi 语言": "Theo ngôn ngữ Wexi",
            "选择与英雄联盟客户端相同的语言，用于读取海克斯名称。": "Chọn cùng ngôn ngữ với client League để đọc tên Nâng Cấp.",
            "设置": "Cài đặt", "返回攻略": "Quay lại hướng dẫn", "英雄": "Tướng", "界面": "Giao diện", "提示透明度": "Độ trong suốt",
            "屏幕录制": "Ghi màn hình", "目标计时": "Hẹn giờ mục tiêu", "出装推荐": "Gợi ý trang bị", "对局玩家": "Người chơi",
            "玩家区服": "Khu vực", "自动检测": "Tự động phát hiện", "技能提示": "Kỹ năng", "状态与快捷键": "Trạng thái và phím tắt",
            "推荐出装": "Trang bị đề xuất", "按场次排序": "Xếp theo số trận", "大乱斗混乱": "ARAM: Hỗn Loạn",
            "极地大乱斗": "ARAM", "斗魂竞技场": "Võ Đài", "排位模式": "Xếp hạng", "下一件": "Tiếp theo",
            "刷新": "Làm mới", "海克斯评级": "Xếp hạng Nâng Cấp", "参考列表": "Danh sách tham khảo", "搜索英雄：": "Tìm tướng:",
            "搜索海克斯：": "Tìm Nâng Cấp:", "已授权": "Đã cho phép", "未授权": "Chưa cho phép", "开启录屏权限": "Cho phép ghi màn hình",
            "打开系统权限设置": "Mở quyền hệ thống", "校准技能＋位置": "Căn chỉnh kỹ năng", "保存技能位置": "Lưu vị trí",
            "取消校准": "Hủy", "胜率 %.1f%%": "Tỉ lệ thắng %.1f%%", "选用率 %.1f%% · %d 场": "Tỉ lệ chọn %.1f%% · %d trận"
        ]
    ]

    private static let english: [String: String] = [
        "游戏客户端语言": "Game client language",
        "跟随 Wexi 语言": "Follow Wexi language",
        "选择与英雄联盟客户端相同的语言，用于读取海克斯名称。": "Choose the same language as the League client so augment names can be recognized.",
        "语言": "Language",
        "设置": "Settings",
        "返回攻略": "Back to guide",
        "英雄": "Champions",
        "界面": "Interface",
        "提示透明度": "Hint opacity",
        "提示大小": "Hint size",
        "更新": "Updates",
        "当前版本 %@": "Current version %@",
        "检查更新": "Check for updates",
        "正在检查更新…": "Checking for updates…",
        "已是最新版本": "You have the latest version",
        "发现新版本 v%@": "Version v%@ is available",
        "下载 v%@": "Download v%@",
        "检查更新失败，请稍后重试。": "Could not check for updates. Try again later.",
        "复制诊断信息": "Copy diagnostics",
        "诊断信息已复制；不包含截图或玩家名称。": "Diagnostics copied; no screenshots or player names are included.",
        "复制应用状态、权限、窗口尺寸和加载结果，便于排查问题；不包含截图、OCR 文字或玩家名称。": "Copies app status, permissions, window size, and loading results for troubleshooting. It excludes screenshots, OCR text, and player names.",
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
        "OP.GG 资料可能已过期": "OP.GG data may be out of date",
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
        "显示推荐出装": "Show recommended build",
        "隐藏推荐出装": "Hide recommended build",
        "按场次排序": "Sorted by games",
        "选用率 %.1f%%": "Pick rate %.1f%%",
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
        "Wexi LoL 与 Riot Games 无关联，也不代表 Riot Games 或其官方相关人员的观点。League of Legends、Riot Games 及相关资产是 Riot Games, Inc. 的商标或注册商标。": "Wexi LoL is not endorsed by or affiliated with Riot Games and does not reflect the views of Riot Games or anyone officially involved with its products. League of Legends, Riot Games, and associated properties are trademarks of Riot Games, Inc.",
        "OP.GG · 全球": "OP.GG · Global",
    ]
}
