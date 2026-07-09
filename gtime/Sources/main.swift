import AppKit
import CoreLocation

let bundleID = "com.sijie.gtime"

// Single-instance guard: if another live copy is already running, quit quietly.
let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
    .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && !$0.isTerminated }
if !others.isEmpty {
    exit(0)
}

// MARK: - Search window

final class SearchWindowController: NSWindowController, NSSearchFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private enum Row {
        case city(City)
        case searchOnline(String)
        case status(String)
    }

    private let searchField = NSSearchField()
    private let tableView = NSTableView()
    private var rows: [Row] = []
    private let geocoder = CLGeocoder()
    /// Returns true if the city was added, false if it was a duplicate (already present).
    var onAdd: ((City) -> Bool)?

    convenience init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 380),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false)
        panel.title = "添加城市"
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.hidesOnDeactivate = false          // keep the in-progress search alive when switching apps
        panel.contentMinSize = NSSize(width: 360, height: 220)
        self.init(window: panel)

        let content = NSView()
        panel.contentView = content

        searchField.placeholderString = "输入城市名(中文 / 英文 / 拼音),如:北京、Tokyo、xianggang"
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(searchField)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("city"))
        column.title = "城市"
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 26
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(addSelected)

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(scroll)

        let hint = NSTextField(labelWithString: "回车或双击添加 · Esc 关闭")
        hint.textColor = .secondaryLabelColor
        hint.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        hint.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(hint)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            searchField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            scroll.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            scroll.bottomAnchor.constraint(equalTo: hint.topAnchor, constant: -8),
            hint.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            hint.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -8),
        ])
    }

    func show() {
        // Already open (e.g. user re-picked the menu item): just refocus, keep the query.
        if window?.isVisible == true {
            NSApp.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil)
            window?.makeFirstResponder(searchField)
            return
        }
        rows = []
        searchField.stringValue = ""
        tableView.reloadData()
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(searchField)
    }

    /// Close the panel and hand activation back to the previously frontmost app
    /// (an accessory app with no other windows would otherwise strand keyboard focus).
    private func closePanel() {
        window?.close()
        NSApp.hide(nil)
    }

    private func offsetLabel(_ tzID: String) -> String {
        guard let tz = TimeZone(identifier: tzID) else { return "" }
        let secs = tz.secondsFromGMT()
        let sign = secs < 0 ? "-" : "+"
        let h = abs(secs) / 3600
        let m = (abs(secs) % 3600) / 60
        return m == 0 ? "UTC\(sign)\(h)" : "UTC\(sign)\(h):" + String(format: "%02d", m)
    }

    private func display(_ c: City) -> String {
        let name = c.zh == c.en ? c.en : "\(c.zh) \(c.en)"
        return "\(c.flag) \(name) · \(c.tzID) (\(offsetLabel(c.tzID)))"
    }

    // NSTextFieldDelegate
    func controlTextDidChange(_ obj: Notification) {
        geocoder.cancelGeocode()
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        rows = searchCities(query).map { Row.city($0) }
        if !query.isEmpty {
            rows.append(.searchOnline(query))
        }
        tableView.reloadData()
        if !rows.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
    }

    private func startOnlineSearch(_ query: String) {
        geocoder.cancelGeocode()
        rows = rows.filter { if case .city = $0 { return true } else { return false } }
        rows.append(.status("正在在线搜索 \u{201C}\(query)\u{201D}…"))
        tableView.reloadData()
        geocoder.geocodeAddressString(query, in: nil, preferredLocale: Locale(identifier: "zh_CN")) { [weak self] placemarks, error in
            guard let self = self else { return }
            // Stale response: the query has changed since this request started.
            let current = self.searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard current == query else { return }

            self.rows = self.rows.filter { if case .city = $0 { return true } else { return false } }
            var found: [City] = []
            for p in placemarks ?? [] {
                guard let tz = p.timeZone else { continue }
                let name = p.name ?? p.locality ?? query
                let dup = found.contains { $0.en == name && $0.tzID == tz.identifier }
                if dup { continue }
                found.append(City(en: name, zh: name,
                                  countryEn: p.country ?? "", countryZh: p.country ?? "",
                                  flag: flagEmoji(countryCode: p.isoCountryCode),
                                  tzID: tz.identifier))
            }
            if found.isEmpty {
                let reason = error == nil ? "未找到 \u{201C}\(query)\u{201D}" : "在线搜索失败,请检查网络后重试"
                self.rows.append(.status(reason))
            } else {
                let firstOnline = self.rows.count
                self.rows.append(contentsOf: found.map { Row.city($0) })
                self.tableView.reloadData()
                self.tableView.selectRowIndexes(IndexSet(integer: firstOnline), byExtendingSelection: false)
                self.tableView.scrollRowToVisible(firstOnline)
                return
            }
            self.tableView.reloadData()
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            addSelected()
            return true
        case #selector(NSResponder.moveDown(_:)):
            moveSelection(by: 1)
            return true
        case #selector(NSResponder.moveUp(_:)):
            moveSelection(by: -1)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            closePanel()
            return true
        default:
            return false
        }
    }

    private func isSelectable(_ row: Row) -> Bool {
        if case .status = row { return false }
        return true
    }

    private func moveSelection(by delta: Int) {
        guard !rows.isEmpty else { return }
        var next = (tableView.selectedRow < 0 ? 0 : tableView.selectedRow) + delta
        while next >= 0, next < rows.count, !isSelectable(rows[next]) {
            next += delta > 0 ? 1 : -1
        }
        guard next >= 0, next < rows.count else { return }
        tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
    }

    @objc private func addSelected() {
        let index = tableView.selectedRow >= 0 ? tableView.selectedRow : 0
        guard index < rows.count else { return }
        switch rows[index] {
        case .city(let city):
            if onAdd?(city) == false {
                NSSound.beep()
                rows = [.status("已添加过该时区,不重复添加")]
                tableView.reloadData()
            } else {
                closePanel()
            }
        case .searchOnline(let query):
            startOnlineSearch(query)
        case .status:
            NSSound.beep()
        }
    }

    // NSTableViewDataSource / Delegate
    func numberOfRows(in tableView: NSTableView) -> Int {
        return rows.count
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        return row < rows.count && isSelectable(rows[row])
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("cell")
        let field: NSTextField
        if let reused = tableView.makeView(withIdentifier: id, owner: nil) as? NSTextField {
            field = reused
        } else {
            field = NSTextField(labelWithString: "")
            field.identifier = id
            field.lineBreakMode = .byTruncatingTail
        }
        switch rows[row] {
        case .city(let c):
            field.stringValue = display(c)
            field.textColor = .labelColor
        case .searchOnline(let q):
            field.stringValue = "🔍 在线搜索 \u{201C}\(q)\u{201D}(小城市、任意地名)"
            field.textColor = .labelColor
        case .status(let text):
            field.stringValue = text
            field.textColor = .secondaryLabelColor
        }
        return field
    }
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var entries: [TimeEntry] = []
    private var use24h = false
    private let searchController = SearchWindowController()
    private let defaults = UserDefaults.standard
    private lazy var scrollController = ScrollFlipController(
        settings: decodeScrollSettings(defaults.data(forKey: "scrollSettings") ?? Data()))
    private lazy var dockController = DockPinController(targetName: defaults.string(forKey: "dockPinTarget"))

    private var launchAgentURL: URL {
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(bundleID).plist")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        entries = decodeEntries(defaults.data(forKey: "entries") ?? Data())
        use24h = defaults.bool(forKey: "use24h")

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        searchController.onAdd = { [weak self] city in
            guard let self = self else { return false }
            if isDuplicateEntry(tzID: city.tzID, in: self.entries) { return false }
            self.entries.append(TimeEntry(en: city.en, zh: city.zh, flag: city.flag, tzID: city.tzID))
            self.saveEntries()
            self.refreshTitle()
            return true
        }

        refreshTitle()
        scheduleMinuteTimer()

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(systemChanged), name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(systemChanged), name: NSNotification.Name.NSSystemClockDidChange, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(systemChanged), name: NSNotification.Name.NSSystemTimeZoneDidChange, object: nil)

        // First run: enable launch-at-login by default.
        if defaults.object(forKey: "didSetupLaunchAtLogin") == nil {
            setLaunchAtLogin(true)
            defaults.set(true, forKey: "didSetupLaunchAtLogin")
        } else if launchAtLoginEnabled() {
            // Self-heal: if the app was moved, refresh the frozen path in the plist.
            setLaunchAtLogin(true)
        }

        // Scroll settings: remember the user's choice across launches. On the very
        // first run, persist the default (mouse reverse / trackpad natural) and prompt
        // once for Accessibility so the default actually takes effect.
        if defaults.data(forKey: "scrollSettings") == nil {
            defaults.set(encodeScrollSettings(scrollController.settings), forKey: "scrollSettings")
            scrollController.apply(promptForPermission: true)
        } else {
            scrollController.apply()
        }
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(scrollBaselineChanged),
            name: NSNotification.Name("SwipeScrollDirectionDidChangeNotification"), object: nil)

        // Re-apply persisted Dock pin (starts the tap if trusted and a display is pinned).
        dockController.reapply()
    }

    @objc private func scrollBaselineChanged() {
        DispatchQueue.main.async { [weak self] in self?.scrollController.apply() }
    }

    // MARK: State

    private func saveEntries() {
        defaults.set(encodeEntries(entries), forKey: "entries")
    }

    private func refreshTitle() {
        let text = statusText(entries: entries, now: Date(), local: TimeZone.current, use24h: use24h)
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        statusItem.button?.attributedTitle = NSAttributedString(string: text, attributes: [.font: font])
    }

    // MARK: Timer & system events

    // One-shot timer re-armed from the wall clock each fire, so it can't drift out of
    // alignment across NTP slews or sleep. Must run on the main thread.
    private func scheduleMinuteTimer() {
        timer?.invalidate()
        let nextMinute = (Date().timeIntervalSinceReferenceDate / 60.0).rounded(.up) * 60.0 + 0.1
        let t = Timer(fireAt: Date(timeIntervalSinceReferenceDate: nextMinute), interval: 0,
                      target: self, selector: #selector(tick), userInfo: nil, repeats: false)
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    @objc private func tick() {
        refreshTitle()
        scheduleMinuteTimer()
    }

    // System clock/time-zone notifications are delivered on Foundation's thread, not main;
    // hop to main before touching AppKit or the run-loop timer.
    @objc private func systemChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.refreshTitle()
            self?.scheduleMinuteTimer()
        }
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let now = Date()

        if entries.isEmpty {
            let empty = NSMenuItem(title: "还没有添加城市", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }

        let dateFmt = DateFormatter()
        dateFmt.locale = Locale(identifier: "zh_CN")
        dateFmt.dateFormat = "M月d日 EEE"

        for (i, e) in entries.enumerated() {
            guard let tz = TimeZone(identifier: e.tzID) else { continue }
            dateFmt.timeZone = tz
            let name = e.zh == e.en ? e.en : "\(e.zh) \(e.en)"
            let title = "\(e.flag) \(name)   \(timeString(now: now, tz: tz, use24h: use24h)) · \(dateFmt.string(from: now))"
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")

            let sub = NSMenu()
            let remove = NSMenuItem(title: "移除", action: #selector(removeEntry(_:)), keyEquivalent: "")
            remove.target = self
            remove.tag = i
            sub.addItem(remove)
            if i > 0 {
                let up = NSMenuItem(title: "上移", action: #selector(moveEntryUp(_:)), keyEquivalent: "")
                up.target = self
                up.tag = i
                sub.addItem(up)
            }
            if i < entries.count - 1 {
                let down = NSMenuItem(title: "下移", action: #selector(moveEntryDown(_:)), keyEquivalent: "")
                down.target = self
                down.tag = i
                sub.addItem(down)
            }
            item.submenu = sub
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let add = NSMenuItem(title: "添加城市…", action: #selector(openSearch), keyEquivalent: "n")
        add.target = self
        menu.addItem(add)

        let fmt = NSMenuItem(title: "24 小时制", action: #selector(toggle24h), keyEquivalent: "")
        fmt.target = self
        fmt.state = use24h ? .on : .off
        menu.addItem(fmt)

        let login = NSMenuItem(title: "登录时自动启动", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = launchAtLoginEnabled() ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(buildScrollMenuItem())
        menu.addItem(buildDockMenuItem())

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "退出 GTime", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    @objc private func openSearch() {
        searchController.show()
    }

    @objc private func removeEntry(_ sender: NSMenuItem) {
        guard sender.tag < entries.count else { return }
        entries.remove(at: sender.tag)
        saveEntries()
        refreshTitle()
    }

    @objc private func moveEntryUp(_ sender: NSMenuItem) {
        let i = sender.tag
        guard i > 0, i < entries.count else { return }
        entries.swapAt(i, i - 1)
        saveEntries()
        refreshTitle()
    }

    @objc private func moveEntryDown(_ sender: NSMenuItem) {
        let i = sender.tag
        guard i >= 0, i < entries.count - 1 else { return }
        entries.swapAt(i, i + 1)
        saveEntries()
        refreshTitle()
    }

    @objc private func toggle24h() {
        use24h = !use24h
        defaults.set(use24h, forKey: "use24h")
        refreshTitle()
    }

    // MARK: Scroll direction

    private func buildScrollMenuItem() -> NSMenuItem {
        // Refresh flips from the live system baseline so the checkmarks and tap state are current.
        scrollController.apply()
        let s = scrollController.settings
        let baseline = systemNaturalScrolling()

        let root = NSMenuItem(title: "滚动方向", action: nil, keyEquivalent: "")
        let sub = NSMenu()

        func deviceItem(_ emoji: String, _ name: String, current: ScrollDir, selector: Selector) -> NSMenuItem {
            let item = NSMenuItem(title: "\(emoji) \(name):\(current == .natural ? "自然" : "反转")",
                                  action: nil, keyEquivalent: "")
            let m = NSMenu()
            let nat = NSMenuItem(title: "自然", action: selector, keyEquivalent: "")
            nat.target = self; nat.tag = 0; nat.state = current == .natural ? .on : .off
            let rev = NSMenuItem(title: "反转", action: selector, keyEquivalent: "")
            rev.target = self; rev.tag = 1; rev.state = current == .reverse ? .on : .off
            m.addItem(nat); m.addItem(rev)
            item.submenu = m
            return item
        }

        sub.addItem(deviceItem("🖱", "鼠标", current: s.mouse, selector: #selector(setMouseDir(_:))))
        sub.addItem(deviceItem("🖐", "触控板", current: s.trackpad, selector: #selector(setTrackpadDir(_:))))
        sub.addItem(.separator())

        let info = NSMenuItem(title: "系统自然滚动:\(baseline ? "开" : "关")", action: nil, keyEquivalent: "")
        info.isEnabled = false
        sub.addItem(info)

        let flips = computeFlips(settings: s, baselineNatural: baseline)
        if shouldRunTap(flips) && !hasAccessibilityPermission(prompt: false) {
            let perm = NSMenuItem(title: "⚠️ 授予辅助功能权限…", action: #selector(openAccessibilitySettings), keyEquivalent: "")
            perm.target = self
            sub.addItem(perm)
        }

        root.submenu = sub
        return root
    }

    private func applyScroll(_ s: ScrollSettings) {
        defaults.set(encodeScrollSettings(s), forKey: "scrollSettings")
        scrollController.apply(s, promptForPermission: true)
    }

    @objc private func setMouseDir(_ sender: NSMenuItem) {
        var s = scrollController.settings
        s.mouse = sender.tag == 1 ? .reverse : .natural
        applyScroll(s)
    }

    @objc private func setTrackpadDir(_ sender: NSMenuItem) {
        var s = scrollController.settings
        s.trackpad = sender.tag == 1 ? .reverse : .natural
        applyScroll(s)
    }

    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Dock pin

    private func buildDockMenuItem() -> NSMenuItem {
        dockController.reapply()   // re-resolve target + orientation from live state
        let displays = listDockDisplays()
        let current = dockController.targetName

        let root = NSMenuItem(title: "Dock 固定", action: nil, keyEquivalent: "")
        let sub = NSMenu()

        let off = NSMenuItem(title: "关闭(不固定)", action: #selector(setDockTarget(_:)), keyEquivalent: "")
        off.target = self
        off.state = current == nil ? .on : .off
        sub.addItem(off)

        for d in displays {
            let title = d.isMain ? "\(d.name)(主)" : d.name
            let item = NSMenuItem(title: title, action: #selector(setDockTarget(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = d.name
            item.state = (current == d.name) ? .on : .off
            sub.addItem(item)
        }

        sub.addItem(.separator())
        if let cur = currentDockDisplayID(), let info = displays.first(where: { $0.id == cur }) {
            let line = NSMenuItem(title: "Dock 当前在:\(info.name)", action: nil, keyEquivalent: "")
            line.isEnabled = false
            sub.addItem(line)
        }
        if current != nil && !hasAccessibilityPermission(prompt: false) {
            let perm = NSMenuItem(title: "⚠️ 授予辅助功能权限…", action: #selector(openAccessibilitySettings), keyEquivalent: "")
            perm.target = self
            sub.addItem(perm)
        }

        root.submenu = sub
        return root
    }

    @objc private func setDockTarget(_ sender: NSMenuItem) {
        let name = sender.representedObject as? String   // nil = 关闭(不固定)
        if let name = name {
            defaults.set(name, forKey: "dockPinTarget")
        } else {
            defaults.removeObject(forKey: "dockPinTarget")
        }
        dockController.setTarget(name, promptForPermission: true)
    }

    // MARK: Launch at login (LaunchAgent; SMAppService needs a newer SDK than this box has)

    private func launchAtLoginEnabled() -> Bool {
        return FileManager.default.fileExists(atPath: launchAgentURL.path)
    }

    private func setLaunchAtLogin(_ on: Bool) {
        let fm = FileManager.default
        if on {
            let exe = Bundle.main.executablePath ?? CommandLine.arguments[0]
            let plist: [String: Any] = [
                "Label": bundleID,
                "ProgramArguments": [exe],
                "RunAtLoad": true,
                "LimitLoadToSessionType": "Aqua",
            ]
            try? fm.createDirectory(at: launchAgentURL.deletingLastPathComponent(),
                                    withIntermediateDirectories: true)
            (plist as NSDictionary).write(to: launchAgentURL, atomically: true)
        } else {
            try? fm.removeItem(at: launchAgentURL)
        }
    }

    @objc private func toggleLaunchAtLogin() {
        setLaunchAtLogin(!launchAtLoginEnabled())
    }
}

// MARK: - Entry point

/// Minimal Edit menu so the standard clipboard shortcuts work inside the search field.
/// An accessory app has no menu bar, but Cmd-key equivalents still route through mainMenu.
func makeEditMenu() -> NSMenu {
    let mainMenu = NSMenu()
    let editItem = NSMenuItem()
    mainMenu.addItem(editItem)
    let editMenu = NSMenu(title: "Edit")
    editItem.submenu = editMenu
    editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
    let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
    redo.keyEquivalentModifierMask = [.command, .shift]
    editMenu.addItem(.separator())
    editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    return mainMenu
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.mainMenu = makeEditMenu()
app.run()
