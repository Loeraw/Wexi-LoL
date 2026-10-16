import SwiftUI
import RiftCore

private let guideMint = Color(red: 0.40, green: 0.91, blue: 0.77)
private let guideBackground = Color(red: 0.055, green: 0.075, blue: 0.095)

struct SkillOrderView: View {
    @ObservedObject private var language = LanguageSettings.shared
    let guide: SkillGuide
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.text("技能加点")).font(.headline)
                Spacer()
                Text(guide.priority.joined(separator: " › ")).font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(guideMint)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 9), spacing: 8) {
                ForEach(Array(guide.order.enumerated()), id: \.offset) { index, skill in
                    VStack(spacing: 3) {
                        Text("\(index + 1)").font(.system(size: 9)).foregroundStyle(.secondary)
                        Text(skill).font(.system(size: 14, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity).frame(height: 27)
                            .background(skill == "R" ? guideMint.opacity(0.24) : .white.opacity(0.07), in: RoundedRectangle(cornerRadius: 5))
                    }
                }
            }
            Text(L10n.text("来源提供 1–%d 级顺序 · 最常用方案 · %d 场样本", guide.order.count, guide.samples))
                .font(.system(size: 9)).foregroundStyle(.secondary)
        }
    }
}

struct AugmentRow: View {
    @ObservedObject private var language = LanguageSettings.shared
    let augment: AugmentRating
    var pinned = false
    private var rarityColors: [Color] {
        switch augment.rarity {
        case 1: return [Color(red: 0.88, green: 0.93, blue: 0.97), Color(red: 0.55, green: 0.63, blue: 0.72)]
        case 4: return [Color(red: 1, green: 0.89, blue: 0.49), Color(red: 0.79, green: 0.53, blue: 0.16)]
        case 8: return [Color(red: 0.49, green: 0.93, blue: 1), Color(red: 0.77, green: 0.62, blue: 1), Color(red: 1, green: 0.66, blue: 0.84)]
        default: return [.gray, .gray.opacity(0.7)]
        }
    }
    var body: some View {
        HStack(spacing: 12) {
            Text(augment.tierLabel).font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundStyle(Color(red: 0.06, green: 0.08, blue: 0.12))
                .frame(width: 40, height: 36)
                .background(LinearGradient(colors: rarityColors, startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 8))
                .help(L10n.text(augment.rarityLabel))
                .accessibilityLabel(L10n.text("%@，评级 %@", L10n.text(augment.rarityLabel), augment.tierLabel))
            Text(augment.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
            Spacer()
            if pinned { Image(systemName: "pin.fill").foregroundStyle(guideMint) }
        }
    }
}

struct GuideControlView: View {
    @ObservedObject private var language = LanguageSettings.shared
    @ObservedObject var model: OverlayModel
    @ObservedObject var guide: GuideStore
    @ObservedObject var recognition: AutoRecognition
    @ObservedObject var calibration: SkillCalibration
    @ObservedObject var objectiveTimers: ObjectiveTimerStore
    @ObservedObject var lobbyScout: LobbyScoutStore
    let startCalibration: () -> Void
    @State private var showingSettings = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if showingSettings {
                    Button {
                        showingSettings = false
                    } label: {
                        Label(L10n.text("返回攻略"), systemImage: "chevron.left")
                    }
                    .buttonStyle(.plain)
                } else {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Wexi LoL").font(.system(size: 24, weight: .bold))
                        Text(L10n.text("EUW · 游戏原位提示设置")).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if !showingSettings {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 34, height: 30)
                            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .help(L10n.text("设置"))
                    .accessibilityLabel(L10n.text("设置"))
                    .accessibilityIdentifier("settingsButton")
                }
            }
            .padding(.horizontal, 20)
            .frame(height: 64)
            Divider()
            if showingSettings { settingsPage } else { guidePage }
        }
        .frame(width: 786, height: 740)
        .background(guideBackground)
        .preferredColorScheme(.dark)
        .onChange(of: language.selection) { _ in guide.load() }
    }

    private var guidePage: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.text("英雄")).font(.headline)
                TextField(L10n.text("搜索英雄："), text: $guide.championSearch).textFieldStyle(.roundedBorder)
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(guide.matchingChampions) { champion in
                            Button {
                                guide.championKey = champion.id
                                guide.load()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(guide.displayName(for: champion)).font(.system(size: 12, weight: .medium))
                                        Text(champion.id).font(.system(size: 10)).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if guide.championKey == champion.id { Image(systemName: "checkmark").foregroundStyle(guideMint) }
                                }.padding(9).background(guide.championKey == champion.id ? .white.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 7))
                            }.buttonStyle(.plain).disabled(recognition.detectedChampion != nil)
                        }
                    }
                }
            }.padding(20).frame(width: 245)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(guide.championName).font(.system(size: 26, weight: .semibold))
                            Text(L10n.text("自动识别英雄 · OP.GG 全球数据 · 版本 %@", guide.patch))
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if guide.loading { ProgressView().controlSize(.small) }
                        Button(L10n.text("刷新")) { guide.load(force: true) }.disabled(guide.loading)
                    }
                    Text(L10n.text(guide.status, guide.augments.count)).font(.system(size: 11)).foregroundStyle(.secondary)
                    if let date = guide.fetchedAt {
                        Text(L10n.text("获取时间 %@", date.formatted(.dateTime.year().month(.abbreviated).day().hour().minute().locale(language.selection.locale))))
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    if let skills = guide.skills { SkillOrderView(guide: skills).padding(16).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12)) }
                    HStack {
                        Text(L10n.text("海克斯评级")).font(.title3.bold())
                        Spacer()
                        Text(L10n.text("参考列表")).font(.caption).foregroundStyle(.secondary)
                    }
                    TextField(L10n.text("搜索海克斯："), text: $guide.augmentSearch).textFieldStyle(.roundedBorder)
                    Text(L10n.text("下方是当前英雄的静态评级。游戏内只标注识别到的三张卡片，不显示常驻列表。"))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    LazyVStack(spacing: 5) {
                        ForEach(guide.matchingAugments) { augment in
                            AugmentRow(augment: augment)
                                .padding(8).background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 9))
                        }
                    }
                    Divider()
                    HStack {
                        Link(L10n.text("OP.GG 加点来源 ↗"), destination: guide.sourceURL("skills"))
                        Link(L10n.text("OP.GG 海克斯来源 ↗"), destination: guide.sourceURL("augments"))
                    }.font(.system(size: 11))
                    Text("Wexi LoL is not endorsed by Riot Games and does not reflect the views or opinions of Riot Games or anyone officially involved in producing or managing Riot Games properties. Riot Games and all associated properties are trademarks or registered trademarks of Riot Games, Inc.")
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                }.padding(24)
            }.frame(width: 540)
        }
    }

    private var settingsPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(L10n.text("设置")).font(.system(size: 28, weight: .bold))

                settingsSection(L10n.text("界面")) {
                    Picker(L10n.text("语言"), selection: $language.selection) {
                        ForEach(AppLanguage.allCases) { option in Text(option.title).tag(option) }
                    }
                    .accessibilityIdentifier("languagePicker")
                    HStack(spacing: 14) {
                        Text(L10n.text("提示透明度")).frame(width: 90, alignment: .leading)
                        Slider(value: $model.opacity, in: 0.35...1)
                        Text("\(Int(model.opacity * 100))%").monospacedDigit().foregroundStyle(.secondary).frame(width: 42)
                    }
                }

                settingsSection(L10n.text("屏幕录制")) {
                    HStack {
                        Image(systemName: recognition.hasScreenPermission ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(recognition.hasScreenPermission ? guideMint : .orange)
                        Text(L10n.text(recognition.hasScreenPermission ? "已授权" : "未授权"))
                        Spacer()
                        Button(L10n.text(recognition.hasScreenPermission ? "打开系统权限设置" : "开启录屏权限")) {
                            if recognition.hasScreenPermission { recognition.openPermissionSettings() }
                            else {
                                recognition.requestPermission()
                                if !recognition.hasScreenPermission { recognition.openPermissionSettings() }
                            }
                        }
                    }
                    Text(L10n.text("只读取英雄联盟游戏窗口，用于识别海克斯选择、技能加点和 Tab 计分板计时；不会保存或上传画面。"))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }

                settingsSection(L10n.text("目标计时")) {
                    Toggle(L10n.text("显示游戏内目标倒计时"), isOn: $objectiveTimers.enabled)
                    HStack {
                        Text(L10n.text("当前模式"))
                        Spacer()
                        Text(objectiveTimers.modeLabel).foregroundStyle(.secondary)
                    }
                    Text(objectiveTimers.status).font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(L10n.text("峡谷的小龙、远古巨龙和纳什男爵会读取 Riot 本地事件自动计时；巢虫与先锋显示首次刷新。"))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(L10n.text("大乱斗中按住 Tab 约 1 秒，应用会读取计分板自带的血包时间并自动校准；关闭计分板后继续倒数。"))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }

                settingsSection(L10n.text("出装推荐")) {
                    Toggle(L10n.text("显示推荐出装与胜率"), isOn: $model.itemBuildEnabled)
                    Text(L10n.text("根据当前已购买的核心装备匹配 OP.GG 主流三件套，并标出下一件；胜率是该完整路线的统计。"))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    HStack {
                        Text(L10n.text("已加载出装路线"))
                        Spacer()
                        Text(L10n.text("%d 套", guide.itemBuilds.count)).foregroundStyle(.secondary)
                    }
                }

                settingsSection(L10n.text("对局玩家")) {
                    Toggle(L10n.text("显示玩家段位与战绩"), isOn: $model.playerScoutEnabled)
                    Text(L10n.text("Loading 阶段只读取一次玩家资料并保存在本局缓存；进入游戏后按住 Tab 只切换显示，不会重新请求 OP.GG。"))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(lobbyScout.status).font(.system(size: 11)).foregroundStyle(.secondary)
                }

                settingsSection(L10n.text("技能提示")) {
                    Text(L10n.text(calibration.message)).font(.system(size: 12)).foregroundStyle(.secondary)
                    HStack {
                        Button(L10n.text("校准技能＋位置"), action: startCalibration)
                        if calibration.active {
                            Button(L10n.text("保存技能位置")) { calibration.finish() }
                            Button(L10n.text("取消校准")) { calibration.cancel() }
                        }
                    }
                }

                settingsSection(L10n.text("状态与快捷键")) {
                    Text(L10n.text(model.overlayStatus)).font(.system(size: 12)).foregroundStyle(.secondary)
                    Text(L10n.text("⌥⌘K 开始/保存校准\nTab 显示玩家资料并同步大乱斗血包计时\n⌘M 收起设置到菜单栏"))
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
                    if !model.hotkeyStatus.isEmpty { Text(L10n.text(model.hotkeyStatus)).font(.caption).foregroundStyle(.orange) }
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
    }

}
