#if os(macOS)
import AppKit
import CuktechCore
import CuktechBle

/// 菜单栏那一格 + 右键菜单 + 面板的接线员。
/// 与 M0 的 AppDelegate 同一风格：不标 @MainActor，靠所有入口都在主线程
/// （AppKit 回调、菜单动作、MainActor 上的 ticker）。
final class TrayController: NSObject {
    private var settings: AppSettings   // 菜单里的「菜单栏显示功率数字」会就地改它
    private let log: LogFile
    private let statusItem: NSStatusItem
    let panel = PanelController()

    private var session: DeviceSession?
    private var snapshot = DeviceSnapshot()
    private var ticker: Task<Void, Never>?
    private var statusLineItem: NSMenuItem!
    private var wattsItem: NSMenuItem!
    /// 右键菜单。左键不弹它——左键直接开面板（README 一直是这么写的，
    /// 之前把 menu 挂死在 statusItem 上，结果左键点出来的是菜单，面板反而要再点一次）。
    private let statusMenu = NSMenu()

    init(settings: AppSettings) {
        self.settings = settings
        self.log = LogFile()
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        buildMenu()
        wireStatusItemButton()
        wirePanel()
        updateTitle()
    }

    // MARK: - 生命周期

    func start() {
        log.write("[tray] 启动 version=\(BuildInfo.version) config=\(AppSettings.fileURL.path)")
        bootSession()

        ticker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if let s = self.session {
                    let snap = await s.snapshot
                    self.apply(snap)
                }
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
        }
    }

    func shutdown() {
        ticker?.cancel()
        ticker = nil
        if let s = session {
            Task { await s.stop() }
        }
        log.write("[tray] 退出")
    }

    // MARK: - 会话

    private func bootSession() {
        guard let mac = settings.macBytes, let token = settings.tokenBytes else {
            log.write("[tray] 还没配对：\(AppSettings.fileURL.path) 里缺 mac 或 token")
            statusLineItem.title = "还没配对，右键「重新配对…」走一遍向导"
            return
        }
        let s = DeviceSession(mac: mac, token: token)
        session = s
        let poll = settings.pollInterval
        let logger = log
        Task {
            await s.setPollInterval(poll)
            await s.setLogHandler { line in logger.write(line) }
            await s.start()
        }
    }

    private func apply(_ snap: DeviceSnapshot) {
        let sig = "\(snap.connected)|\(snap.totalText)|\(snap.headline)|\(snap.sceneMode)"
        let old = "\(snapshot.connected)|\(snapshot.totalText)|\(snapshot.headline)|\(snapshot.sceneMode)"
        snapshot = snap
        if sig != old {
            updateTitle()
            refreshMenuStatus()
        }
        panel.model.snapshot = snap
    }

    // MARK: - 菜单栏标题

    /// 关掉「菜单栏显示功率数字」时显示的那个图标。
    /// 以前这里塞的是「瓦」这个字，挤在菜单栏里像坏掉的标签；换成闪电模板图，
    /// 跟 App 图标上的闪电对应，深浅色菜单栏都会自动反色（isTemplate）。
    private static let boltIcon: NSImage? = {
        let cfg = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        guard let img = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "酷态科功率表")?
            .withSymbolConfiguration(cfg) else { return nil }
        img.isTemplate = true
        return img
    }()

    private func updateTitle() {
        guard let button = statusItem.button else { return }
        let text: String
        var color = NSColor.secondaryLabelColor

        if !settings.showWattsInMenuBar {
            button.image = Self.boltIcon
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
            button.attributedTitle = NSAttributedString(string: "")
            button.toolTip = snapshot.connected ? snapshot.headline : "酷态科 10 号 Ultra · \(snapshot.status)"
            return
        }

        button.image = nil
        button.imagePosition = .noImage

        if snapshot.connected {
            text = snapshot.totalText
            let c = snapshot.totalColor
            color = NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1)
        } else if session != nil {
            text = "—"
        } else {
            text = "未配对"
        }

        button.attributedTitle = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: color,
            ])
        button.toolTip = snapshot.connected ? snapshot.headline : "酷态科 10 号 Ultra · \(snapshot.status)"
    }

    private func refreshMenuStatus() {
        statusLineItem.title = snapshot.connected
            ? snapshot.headline
            : (snapshot.error.map { "没连上：" + $0 } ?? snapshot.status)
    }

    // MARK: - 菜单

    private func buildMenu() {
        let menu = statusMenu
        menu.autoenablesItems = false

        statusLineItem = NSMenuItem(title: "正在启动…", action: nil, keyEquivalent: "")
        statusLineItem.isEnabled = false
        menu.addItem(statusLineItem)
        menu.addItem(.separator())

        menu.addItem(item("显示功率面板", #selector(showPanel)))
        menu.addItem(item("重新连接", #selector(reconnect)))
        menu.addItem(item("重新配对…", #selector(runWizard)))
        menu.addItem(.separator())

        wattsItem = item("菜单栏显示功率数字", #selector(toggleWatts))
        wattsItem.state = settings.showWattsInMenuBar ? .on : .off
        menu.addItem(wattsItem)

        menu.addItem(.separator())
        menu.addItem(item("打开日志", #selector(openLog)))
        menu.addItem(item("显示配置文件", #selector(showConfig)))
        menu.addItem(.separator())
        menu.addItem(item("关于酷态科功率表…", #selector(showAbout)))
        menu.addItem(.separator())
        menu.addItem(item("退出", #selector(quit)))

    }

    /// 左键开面板、右键弹菜单。不设 `statusItem.menu`，否则左键永远只有菜单。
    private func wireStatusItemButton() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        let isSecondary = event?.type == .rightMouseUp
            || (event?.modifierFlags.contains(.control) ?? false)
        if isSecondary {
            // 临时挂上菜单再点一次，让 AppKit 把它弹在正确位置；弹完立刻摘掉
            statusItem.menu = statusMenu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            panel.toggle(relativeTo: statusItem.button)
        }
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: "")
        mi.target = self
        return mi
    }

    @objc private func showPanel() {
        panel.toggle(relativeTo: statusItem.button)
    }

    @objc private func reconnect() {
        guard let s = session else { return }
        Task { await s.reconnectNow() }
    }

    @objc private func toggleWatts() {
        settings.showWattsInMenuBar.toggle()
        wattsItem.state = settings.showWattsInMenuBar ? .on : .off
        try? settings.save()
        updateTitle()
    }

    @objc private func runWizard() {
        showWizard()
    }

    /// 首次运行（配置不全）时由 AppDelegate 调；菜单里点「重新配对…」也走这里。
    func showWizardIfNeeded() {
        guard !settings.isComplete else { return }
        log.write("[tray] 配置不全，先弹向导：\(AppSettings.fileURL.path)")
        showWizard()
    }

    private func showWizard() {
        WizardController.show(settings: settings) { [weak self] newSettings in
            guard let self else { return }
            self.log.write("[tray] 向导写完配置，重建会话")
            if let old = self.session {
                Task { await old.stop() }
            }
            self.session = nil
            self.settings = newSettings
            self.bootSession()
            self.updateTitle()
        }
    }

    @objc private func openLog() {
        let url = AppSettings.logURL
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: Data())
        }
        NSWorkspace.shared.open(url)
    }

    @objc private func showConfig() {
        NSWorkspace.shared.activateFileViewerSelecting([AppSettings.fileURL])
    }

    @objc private func showAbout() {
        AboutController.shared.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - 面板动作

    private func wirePanel() {
        panel.model.onReconnect = { [weak self] in self?.reconnect() }
        panel.model.onQuit = { NSApp.terminate(nil) }
        panel.model.onSetPort = { [weak self] index, on in self?.setPort(index, on) }
        panel.model.onSetScene = { [weak self] mode in self?.setScene(mode) }
    }

    private func setPort(_ index: Int, _ on: Bool) {
        guard let s = session else { return }
        Task { @MainActor in
            do {
                try await s.setPortEnabled(index, on)
            } catch {
                self.log.write("[panel] 设置端口 \(index) 失败：\(error)")
            }
            self.panel.model.busy = false
        }
    }

    private func setScene(_ mode: Int) {
        guard let s = session else { return }
        Task { @MainActor in
            do {
                try await s.setSceneMode(mode)
            } catch {
                self.log.write("[panel] 切换模式 \(mode) 失败：\(error)")
            }
            self.panel.model.busy = false
        }
    }
}
#endif