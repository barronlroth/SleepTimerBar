import AppKit
import SleepTimerCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private lazy var timerController = SleepTimerController(settings: settings)
    private var statusItem: NSStatusItem?

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
        }
        timerController.onError = { [weak self] message in
            self?.showError(message)
        }

        refreshStatusItem()
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
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func buildOptionsMenu() -> NSMenu {
        let menu = NSMenu()

        let status = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        switch timerController.state {
        case .idle:
            menu.addItem(menuItem(
                title: "Start \(settings.defaultDuration.title)",
                action: #selector(startDuration(_:)),
                representedObject: settings.defaultDuration.minutes
            ))
        case .running:
            menu.addItem(menuItem(title: "Cancel Timer", action: #selector(cancelTimer(_:))))
        }

        menu.addItem(durationMenu())
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

        let image = NSImage(systemSymbolName: active ? "moon.zzz.fill" : "moon.zzz", accessibilityDescription: "Sleep Timer")
        image?.isTemplate = true

        button.image = image
        button.contentTintColor = active ? .white : .tertiaryLabelColor
        button.toolTip = statusTitle
    }

    private var statusTitle: String {
        switch timerController.state {
        case .idle:
            return "Sleep Timer Idle"
        case .running(let snapshot):
            let minutes = Int(ceil(snapshot.remainingSeconds() / 60))
            return "Sleep in \(minutes) min"
        }
    }

    private func percentTitle(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Sleep Timer"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
