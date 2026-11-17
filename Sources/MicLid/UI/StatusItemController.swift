import AppKit
import CoreAudio

final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let controller: Controller
    private var iconCache: [String: NSImage] = [:]

    init(controller: Controller) {
        self.controller = controller
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp, .otherMouseUp])
            button.imagePosition = .imageLeading
        }

        menu.delegate = self
        menu.autoenablesItems = false

        controller.onChange = { [weak self] in
            self?.refresh()
        }
        refresh()
    }

    // MARK: - Status item

    private func refresh() {
        guard let button = statusItem.button else { return }

        let role = controller.conditions.currentInput?.role
        button.image = icon(for: Controller.symbol(for: role))

        if controller.mode != .off && controller.isRecommendationActive && !controller.isSuppressed {
            button.attributedTitle = NSAttributedString(
                string: " •",
                attributes: [
                    .foregroundColor: NSColor.systemOrange,
                    .font: NSFont.systemFont(ofSize: 9, weight: .bold)
                ]
            )
        } else {
            button.title = ""
        }

        let inputName = controller.conditions.currentInput?.name ?? "No input"
        button.toolTip = "Microphone: \(inputName)"
        button.setAccessibilityLabel("MicLid")
        button.setAccessibilityHelp("Microphone input: \(inputName). Click to switch, right-click for options.")
    }

    private func icon(for symbol: String) -> NSImage? {
        if let cached = iconCache[symbol] { return cached }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Microphone")
        image?.isTemplate = true
        if let image { iconCache[symbol] = image }
        return image
    }

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent else {
            showMenu()
            return
        }

        if event.type == .rightMouseUp
            || event.type == .otherMouseUp
            || event.type == .keyDown
            || event.modifierFlags.contains(.control) {
            showMenu()
        } else {
            quickToggle()
        }
    }

    private func quickToggle() {
        let result = Decider.toggleDestination(
            current: controller.conditions.currentInput,
            devices: controller.inputDevices
        )

        switch result {
        case .switchTo(let identifier):
            guard let device = controller.inputDevices.first(where: { $0.id == identifier }) else {
                showMenu()
                return
            }
            controller.switchInput(to: device)
        case .showMenu:
            showMenu()
        }
    }

    private func showMenu() {
        rebuildMenu()
        guard let button = statusItem.button else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 5), in: button)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
    }

    // MARK: - Menu

    private func rebuildMenu() {
        menu.removeAllItems()
        let conditions = controller.conditions

        let switchItem = NSMenuItem(
            title: "Switch to iPhone Microphone",
            action: #selector(switchToiPhone),
            keyEquivalent: ""
        )
        switchItem.target = self
        switchItem.image = NSImage(systemSymbolName: "iphone", accessibilityDescription: nil)
        switchItem.isEnabled = conditions.iPhone != nil && conditions.currentInput?.role != .iphone
        menu.addItem(switchItem)

        menu.addItem(makeInputSubmenu(current: conditions.currentInput))
        menu.addItem(.separator())

        menu.addItem(makeModeSubmenu())
        menu.addItem(makeLaunchAtLoginItem())
        menu.addItem(.separator())

        let promptItem = NSMenuItem(title: "Show Prompt", action: #selector(showPrompt), keyEquivalent: "")
        promptItem.target = self
        promptItem.isEnabled = conditions.iPhone != nil
        menu.addItem(promptItem)

        let soundItem = NSMenuItem(title: "Open Sound Settings…", action: #selector(openSoundSettings), keyEquivalent: "")
        soundItem.target = self
        menu.addItem(soundItem)

        menu.addItem(.separator())

        let aboutItem = NSMenuItem(title: "About MicLid", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(title: "Quit MicLid", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func makeInputSubmenu(current: AudioDeviceInfo?) -> NSMenuItem {
        let item = NSMenuItem(title: "Switch Input", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        for device in controller.inputDevices {
            let entry = NSMenuItem(title: device.name, action: #selector(selectInput(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = NSNumber(value: device.id)
            entry.state = device.id == current?.id ? .on : .off
            submenu.addItem(entry)
        }

        if submenu.items.isEmpty {
            let empty = NSMenuItem(title: "No Inputs", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
        }

        item.submenu = submenu
        return item
    }

    private func makeModeSubmenu() -> NSMenuItem {
        let item = NSMenuItem(title: "When Connected", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        for mode in TriggerMode.allCases {
            let entry = NSMenuItem(title: mode.title, action: #selector(selectMode(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = mode.rawValue
            entry.state = controller.mode == mode ? .on : .off
            submenu.addItem(entry)
        }

        item.submenu = submenu
        return item
    }

    private func makeLaunchAtLoginItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        item.target = self
        item.state = LaunchAtLogin.isEnabled ? .on : .off
        item.isEnabled = LaunchAtLogin.isSupported
        return item
    }

    // MARK: - Actions

    @objc private func switchToiPhone() {
        controller.switchToiPhone(reason: .manual)
    }

    @objc private func selectInput(_ sender: NSMenuItem) {
        guard let number = sender.representedObject as? NSNumber else { return }
        let identifier = AudioDeviceID(truncating: number)
        guard let device = controller.inputDevices.first(where: { $0.id == identifier }) else { return }
        controller.switchInput(to: device)
    }

    @objc private func selectMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = TriggerMode(rawValue: raw) else { return }
        controller.setMode(mode)
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            try LaunchAtLogin.set(!LaunchAtLogin.isEnabled)
        } catch {
            showLaunchAtLoginError(error)
        }

        if LaunchAtLogin.requiresApproval {
            showLaunchAtLoginApproval()
        }
    }

    @objc private func showPrompt() {
        controller.showPrompt()
    }

    @objc private func openSoundSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func showAbout() {
        let credits = NSMutableAttributedString(
            string: "Switches your audio input to the iPhone Continuity microphone\nwhen the lid is closed and an external display is connected.",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
        credits.addAttribute(
            .font,
            value: NSFont.systemFont(ofSize: 11),
            range: NSRange(location: 0, length: credits.length)
        )

        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "MicLid",
            .applicationVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
            .version: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "",
            .credits: credits
        ])
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func showLaunchAtLoginError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Launch at Login"
        alert.informativeText = "Move MicLid to your Applications folder, then try again.\n\n\(error.localizedDescription)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func showLaunchAtLoginApproval() {
        let alert = NSAlert()
        alert.messageText = "Approve MicLid in Login Items"
        alert.informativeText = "macOS needs your approval before MicLid can open at login."
        alert.addButton(withTitle: "Open Login Items")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            LaunchAtLogin.openLoginItemsSettings()
        }
    }
}
