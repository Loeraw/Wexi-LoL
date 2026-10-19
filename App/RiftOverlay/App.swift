import AppKit
import SwiftUI
import Carbon

final class ControlWindow: NSWindow {}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = OverlayModel()
    let guide = GuideStore()
    let recognition = AutoRecognition()
    let calibration = SkillCalibration()
    let objectiveTimers = ObjectiveTimerStore()
    let lobbyScout = LobbyScoutStore()
    private let hints = HintOverlayController()
    private let objectiveTimerOverlay = ObjectiveTimerOverlayController()
    private let itemBuildOverlay = ItemBuildOverlayController()
    private let lobbyScoutOverlay = LobbyScoutOverlayController()
    private var controls: NSWindow!
    private var statusItem: NSStatusItem!
    private var hotkeys: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private var layoutTimer: Timer?
    private var lastDiagnosticWrite = Date.distantPast
    private var displayedVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.5.6"
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        controls = ControlWindow(contentRect: NSRect(x: 0, y: 0, width: 786, height: 740),
                                 styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        controls.isReleasedWhenClosed = false
        controls.contentView = NSHostingView(rootView: GuideControlView(model: model, guide: guide, recognition: recognition,
            calibration: calibration, objectiveTimers: objectiveTimers, lobbyScout: lobbyScout,
            startCalibration: { [weak self] in self?.startCalibration() }))
        controls.center()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateLanguage()
        NotificationCenter.default.addObserver(self, selector: #selector(updateLanguage), name: LanguageSettings.didChange, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(updateHints), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(updateHints), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateHints), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        layoutTimer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateHints() }
        }
        if let layoutTimer { RunLoop.main.add(layoutTimer, forMode: .common) }
        registerHotkeys()
        guide.load(); recognition.start(guide: guide, objectiveTimers: objectiveTimers); objectiveTimers.start(); lobbyScout.start()
        updateHints()
        if !CGPreflightScreenCaptureAccess() {
            showControls()
            // Register this exact app bundle with macOS on first launch so the
            // Screen Recording list contains Wexi LoL rather than only the
            // historical RiftOverlay entry.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.recognition.requestPermission()
            }
        } else if GameWindow.frontmostPID == nil {
            showControls()
        }
    }
    @objc private func updateLanguage() {
        controls.title = "Wexi LoL · v\(displayedVersion)"
        statusItem.button?.image = NSImage(systemSymbolName: "waveform.path", accessibilityDescription: L10n.text("Wexi LoL 设置"))
        let menu = NSMenu()
        for (title, action) in [("打开设置", #selector(showControls)), ("收起设置到菜单栏", #selector(minimizeControls)),
                                ("屏幕录制权限", #selector(openScreenPermissionSettings)),
                                ("校准技能＋位置", #selector(startCalibration)),
                                ("保存技能位置（⌥⌘K）", #selector(finishCalibration)),
                                ("取消校准", #selector(cancelCalibration))] {
            let item = NSMenuItem(title: L10n.text(title), action: action, keyEquivalent: "")
            item.target = self; menu.addItem(item)
        }
        menu.addItem(.separator())
        let quit = NSMenuItem(title: L10n.text("退出 Wexi LoL"), action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self; menu.addItem(quit); statusItem.menu = menu
        updateHints()
    }
    @objc func showControls() {
        if controls.isMiniaturized { controls.deminiaturize(nil) }
        NSApp.activate(ignoringOtherApps: true)
        controls.makeKeyAndOrderFront(nil)
    }
    @objc func minimizeControls() { controls.performMiniaturize(nil) }
    @objc func openScreenPermissionSettings() {
        recognition.requestPermission()
        if !recognition.hasScreenPermission { recognition.openPermissionSettings() }
    }
    @objc func startCalibration() { calibration.start(); controls.orderOut(nil); updateHints() }
    @objc func finishCalibration() { calibration.finish(); updateHints() }
    @objc func cancelCalibration() { calibration.cancel(); updateHints() }
    @objc func toggleCalibration() { if calibration.active { finishCalibration() } else { startCalibration() } }
    @objc func quitApp() { NSApp.terminate(nil) }
    @objc func updateHints() {
        recognition.pauseForApplicationChange()
        hints.update(model: model, guide: guide, recognition: recognition, calibration: calibration)
        objectiveTimers.refreshDisplay()
        objectiveTimerOverlay.update(store: objectiveTimers, model: model,
                                     game: recognition.capturedGameSurface ?? GameSurface.current())
        itemBuildOverlay.update(model: model, guide: guide, recognition: recognition, calibration: calibration,
                                game: recognition.capturedGameSurface ?? GameSurface.current())
        lobbyScoutOverlay.update(model: model, store: lobbyScout, guide: guide, recognition: recognition,
                                 game: recognition.capturedGameSurface ?? GameSurface.current())
        // One small local status file, overwritten every two seconds. No screenshots,
        // OCR text, account names or player identifiers are recorded.
        if Date().timeIntervalSince(lastDiagnosticWrite) >= 2 {
            lastDiagnosticWrite = Date()
            let status: [String: Any] = [
                "updatedAt": Date().description,
                "gameForeground": GameWindow.frontmostPID != nil,
                "gameWindow": (recognition.capturedGameSurface ?? GameSurface.current()) != nil,
                "permission": recognition.hasScreenPermission,
                "enabled": true, "calibration": calibration.active,
                "champion": recognition.championStatus, "skills": recognition.skillStatus,
                "scan": recognition.scanSummary, "capture": recognition.cardStatus,
                "overlay": model.overlayStatus, "guide": L10n.text(guide.status, guide.statusCount),
                "timerMode": objectiveTimers.mode, "timerStatus": objectiveTimers.status,
                "timers": objectiveTimers.rows.map { ["kind": $0.kind.rawValue, "remaining": $0.remaining, "slot": $0.slot ?? 0] },
                "itemBuilds": guide.itemBuilds.count, "ownedItems": recognition.ownedItemIDs,
                "playerScout": lobbyScout.status, "scoutPlayers": lobbyScout.rows.count,
                "scoutLoaded": lobbyScout.loadedProfileCount, "scoutFailed": lobbyScout.failedProfileCount,
                "playerRegion": lobbyScout.activeRegion?.rawValue ?? "auto",
                "scoreboardVisible": recognition.isScoreboardVisible,
                "recommendation": recognition.recommendedSkill ?? "none",
                "anchors": recognition.skillAnchors.mapValues { ["x": $0.x, "y": $0.y] },
                "cards": recognition.cardHints.map(\.id)
            ]
            if let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("WexiLoL") {
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                if let data = try? JSONSerialization.data(withJSONObject: status, options: [.prettyPrinted, .sortedKeys]) {
                    try? data.write(to: directory.appendingPathComponent("status.json"), options: .atomic)
                }
            }
        }
    }
    private func registerHotkeys() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installResult = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard result == noErr else { return result }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async {
                if id.id == 2 { delegate.toggleCalibration() }
            }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard installResult == noErr else {
            model.hotkeyStatus = "快捷键不可用，请使用菜单栏控制。"; return
        }
        let bindings: [(UInt32, UInt32)] = [(2, UInt32(kVK_ANSI_K))]
        for (id, key) in bindings {
            var ref: EventHotKeyRef?
            let result = RegisterEventHotKey(key, UInt32(cmdKey | optionKey), EventHotKeyID(signature: 0x52494654, id: id), GetApplicationEventTarget(), 0, &ref)
            if result == noErr, let ref { hotkeys.append(ref) }
            else { model.hotkeyStatus = "部分快捷键注册失败或已被占用，请使用菜单栏控制。" }
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showControls(); return true
    }
    func applicationWillTerminate(_ notification: Notification) {
        recognition.stop(); objectiveTimers.stop(); lobbyScout.stop(); hints.hideAll(); objectiveTimerOverlay.hide(); itemBuildOverlay.hide(); lobbyScoutOverlay.hide()
        layoutTimer?.invalidate()
        hotkeys.forEach { UnregisterEventHotKey($0) }
        if let handler { RemoveEventHandler(handler) }
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }
}

@main struct WexiLoLMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
