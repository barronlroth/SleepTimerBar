import AppKit
import SleepTimerCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private lazy var timerController = SleepTimerController(settings: settings)
    private var statusItem: NSStatusItem?
    private var statusTimer: Timer?
    private weak var openMenu: NSMenu?

    private enum MenuTag {
        static let status = 1
        static let deadline = 2
        static let primaryAction = 3
        static let durations = 4
        static let brightnessIssue = 5
        static let volumeIssue = 6
        static let sleepIssue = 7
    }

    private let floorChoices: [Double] = [0, 0.05, 0.1, 0.2, 0.3, 0.5]

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item

        if let button = item.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "Sleep Timer"
        }

        timerController.onStateChanged = { [weak self] _ in
            self?.refreshStatusItem()
            self?.scheduleStatusUpdates()
        }
        timerController.onStatusChanged = { [weak self] in self?.refreshStatusText() }
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(systemWillSleep(_:)),
            name: NSWorkspace.willSleepNotification, object: nil
        )

        refreshStatusItem()
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        statusTimer?.invalidate()
        timerController.cancel()
    }

    @objc private func systemWillSleep(_ notification: Notification) {
        timerController.systemWillSleep()
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showOptionsMenu()
        } else {
            timerController.toggleDefaultTimer()
        }
    }

    @objc private func startDuration(_ sender: NSMenuItem) {
        guard
            let minutes = sender.representedObject as? Int,
            let duration = TimerDuration(minutes: minutes)
        else {
            return
        }

        timerController.start(duration: duration)
    }

    @objc private func cancelTimer(_ sender: NSMenuItem) {
        timerController.cancel()
    }

    @objc private func setDefaultDuration(_ sender: NSMenuItem) {
        guard
            let minutes = sender.representedObject as? Int,
            let duration = TimerDuration(minutes: minutes)
        else {
            return
        }

        settings.defaultDuration = duration
    }

    @objc private func setBrightnessFloor(_ sender: NSMenuItem) {
        guard let floor = sender.representedObject as? Double else { return }
        settings.brightnessFloor = floor
    }

    @objc private func setVolumeFloor(_ sender: NSMenuItem) {
        guard let floor = sender.representedObject as? Double else { return }
        settings.volumeFloor = floor
    }

    @objc private func quit(_ sender: NSMenuItem) {
        NSApp.terminate(nil)
    }

    private func showOptionsMenu() {
        guard let statusItem else { return }

        let menu = buildOptionsMenu()
        openMenu = menu
        refreshStatusText()
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
        openMenu = nil
    }

    private func buildOptionsMenu() -> NSMenu {
        let menu = NSMenu()

        let status = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        status.tag = MenuTag.status
        menu.addItem(status)
        let deadline = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        deadline.tag = MenuTag.deadline
        menu.addItem(deadline)
        for tag in [MenuTag.brightnessIssue, MenuTag.volumeIssue, MenuTag.sleepIssue] {
            let issue = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            issue.tag = tag
            issue.isHidden = true
            menu.addItem(issue)
        }
        menu.addItem(.separator())
        let primaryAction = menuItem(title: "", action: #selector(startDuration(_:)))
        primaryAction.tag = MenuTag.primaryAction
        menu.addItem(primaryAction)
        let durations = durationMenu()
        durations.tag = MenuTag.durations
        menu.addItem(durations)
        menu.addItem(.separator())
        menu.addItem(defaultDurationMenu())
        menu.addItem(floorMenu(title: "Brightness Floor", currentValue: settings.brightnessFloor, action: #selector(setBrightnessFloor(_:))))
        menu.addItem(floorMenu(title: "Volume Floor", currentValue: settings.volumeFloor, action: #selector(setVolumeFloor(_:))))
        menu.addItem(.separator())
        menu.addItem(menuItem(title: "Quit", action: #selector(quit(_:)), keyEquivalent: "q"))

        return menu
    }

    private func durationMenu() -> NSMenuItem {
        let item = NSMenuItem(title: "Start Duration", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        for duration in TimerDuration.allCases {
            let title: String
            switch timerController.state {
            case .idle:
                title = duration.title
            case .running:
                title = "Restart \(duration.title)"
            }

            submenu.addItem(menuItem(
                title: title,
                action: #selector(startDuration(_:)),
                representedObject: duration.minutes
            ))
        }

        item.submenu = submenu
        return item
    }

    private func defaultDurationMenu() -> NSMenuItem {
        let item = NSMenuItem(title: "Default Duration", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        for duration in TimerDuration.allCases {
            let durationItem = menuItem(
                title: duration.title,
                action: #selector(setDefaultDuration(_:)),
                representedObject: duration.minutes
            )
            durationItem.state = duration == settings.defaultDuration ? .on : .off
            submenu.addItem(durationItem)
        }

        item.submenu = submenu
        return item
    }

    private func floorMenu(title: String, currentValue: Double, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        for floor in floorChoices {
            let floorItem = menuItem(
                title: percentTitle(floor),
                action: action,
                representedObject: floor
            )
            floorItem.state = abs(floor - currentValue) < 0.001 ? .on : .off
            submenu.addItem(floorItem)
        }

        item.submenu = submenu
        return item
    }

    private func menuItem(
        title: String,
        action: Selector,
        keyEquivalent: String = "",
        representedObject: Any? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        item.representedObject = representedObject
        return item
    }

    private func refreshStatusItem() {
        guard let button = statusItem?.button else { return }

        let active: Bool
        switch timerController.state {
        case .idle:
            active = false
        case .running:
            active = true
        }

        button.image = whiteStatusImage(systemName: active ? "moon.zzz.fill" : "moon.zzz")
        button.contentTintColor = .white
        refreshStatusText()
    }

    private func whiteStatusImage(systemName: String) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(paletteColors: [.white])
        guard
            let baseSymbol = NSImage(systemSymbolName: systemName, accessibilityDescription: "Sleep Timer"),
            let symbol = baseSymbol.withSymbolConfiguration(configuration)
        else {
            return nil
        }

        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.lockFocus()
        NSColor.white.set()

        let rect = NSRect(x: 0, y: 0, width: 18, height: 18)
        symbol.draw(
            in: rect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: nil
        )
        image.unlockFocus()
        image.isTemplate = false

        return image
    }

    private var statusTitle: String {
        switch timerController.state {
        case .idle:
            return "Sleep Timer Idle"
        case .running:
            let minutes = Int(ceil(timerController.remainingSeconds / 60))
            return "Sleep in \(minutes) min"
        }
    }

    private func percentTitle(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func scheduleStatusUpdates() {
        statusTimer?.invalidate()
        statusTimer = nil
        guard case .running = timerController.state else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshStatusText() }
        }
        statusTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func refreshStatusText() {
        statusItem?.button?.toolTip = statusTitle
        guard let menu = openMenu else { return }
        menu.item(withTag: MenuTag.status)?.title = statusTitle
        let deadline = menu.item(withTag: MenuTag.deadline)
        deadline?.isHidden = timerController.estimatedSleepDate == nil
        if let date = timerController.estimatedSleepDate {
            deadline?.title = "Sleep at \(date.formatted(date: .omitted, time: .shortened))"
        }
        let running: Bool
        let primaryAction = menu.item(withTag: MenuTag.primaryAction)
        switch timerController.state {
        case .idle:
            running = false
            primaryAction?.title = "Start \(settings.defaultDuration.title)"
            primaryAction?.action = #selector(startDuration(_:))
            primaryAction?.representedObject = settings.defaultDuration.minutes
        case .running:
            running = true
            primaryAction?.title = "Cancel Timer"
            primaryAction?.action = #selector(cancelTimer(_:))
            primaryAction?.representedObject = nil
        }
        if let durations = menu.item(withTag: MenuTag.durations)?.submenu {
            for item in durations.items {
                guard let minutes = item.representedObject as? Int else { continue }
                item.title = running ? "Restart \(minutes) min" : "\(minutes) min"
            }
        }
        let sources: [(SleepTimerIssue.Source, Int)] = [
            (.brightness, MenuTag.brightnessIssue), (.volume, MenuTag.volumeIssue), (.sleep, MenuTag.sleepIssue)
        ]
        for (source, tag) in sources {
            let item = menu.item(withTag: tag)
            let issue = timerController.issues.first { $0.source == source }
            item?.isHidden = issue == nil
            item?.toolTip = issue?.message
            if issue != nil {
                if source == .sleep {
                    item?.title = "Could not put the Mac to sleep"
                } else {
                    item?.title = "\(source.rawValue) unavailable" + (running ? "; timer still active" : "")
                }
            }
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
