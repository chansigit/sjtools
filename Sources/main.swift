import AppKit

let bundleID = "com.sijie.gtime"

// Single-instance guard: if another copy is already running, quit quietly.
let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
    .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
if !others.isEmpty {
    exit(0)
}

// MARK: - Search window

final class SearchWindowController: NSWindowController, NSSearchFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private let searchField = NSSearchField()
    private let tableView = NSTableView()
    private var results: [City] = []
    var onAdd: ((City) -> Void)?

    convenience init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 380),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false)
        panel.title = "添加城市"
        panel.isReleasedWhenClosed = false
        panel.level = .floating
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
        results = []
        searchField.stringValue = ""
        tableView.reloadData()
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(searchField)
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
        results = searchCities(searchField.stringValue)
        tableView.reloadData()
        if !results.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
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
            window?.close()
            return true
        default:
            return false
        }
    }

    private func moveSelection(by delta: Int) {
        guard !results.isEmpty else { return }
        let current = tableView.selectedRow
        let next = min(max(current + delta, 0), results.count - 1)
        tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
    }

    @objc private func addSelected() {
        let row = tableView.selectedRow >= 0 ? tableView.selectedRow : 0
        guard row < results.count else { return }
        onAdd?(results[row])
        window?.close()
    }

    // NSTableViewDataSource / Delegate
    func numberOfRows(in tableView: NSTableView) -> Int {
        return results.count
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
        field.stringValue = display(results[row])
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
            guard let self = self else { return }
            self.entries.append(TimeEntry(en: city.en, zh: city.zh, flag: city.flag, tzID: city.tzID))
            self.saveEntries()
            self.refreshTitle()
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
        }
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

    private func scheduleMinuteTimer() {
        timer?.invalidate()
        let nextMinute = (Date().timeIntervalSinceReferenceDate / 60.0).rounded(.up) * 60.0 + 0.1
        let t = Timer(fireAt: Date(timeIntervalSinceReferenceDate: nextMinute), interval: 60,
                      target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    @objc private func tick() {
        refreshTitle()
    }

    @objc private func systemChanged() {
        refreshTitle()
        scheduleMinuteTimer()
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

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
