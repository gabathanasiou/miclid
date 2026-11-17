import AppKit

final class SwitchPrompt {
    var onSwitch: (() -> Void)?
    var onDismiss: (() -> Void)?

    private var panel: SwitchPromptPanel?

    func present(deviceName: String, countdown: TimeInterval?) {
        panel?.closeWithoutCallback()
        panel = nil

        let panel = SwitchPromptPanel(deviceName: deviceName, countdown: countdown)
        panel.onSwitch = { [weak self] in
            self?.onSwitch?()
        }
        panel.onDismiss = { [weak self] in
            self?.onDismiss?()
        }
        self.panel = panel
        panel.present()
    }

    func dismiss() {
        panel?.closeWithoutCallback()
        panel = nil
    }
}

final class SwitchPromptPanel: NSPanel {
    enum Outcome {
        case switchNow
        case dismissed
    }

    var onSwitch: (() -> Void)?
    var onDismiss: (() -> Void)?

    private let effect = NSVisualEffectView()
    private let countdownBar = CountdownBar()
    private let countdownLabel = NSTextField(labelWithString: "")

    private var timer: Timer?
    private var deadline: Date?
    private var total: TimeInterval?
    private var isFinishing = false

    private let width: CGFloat = 380

    init(deviceName: String, countdown: TimeInterval?) {
        total = countdown
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: width, height: countdown == nil ? 124 : 160),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 16
        effect.layer?.masksToBounds = true
        effect.layer?.borderWidth = 1
        effect.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor
        contentView = effect

        // NSVisualEffectView ignores the layer corner radius for its blur, so
        // mask the vibrancy itself to keep the corners truly transparent.
        effect.maskImage = NSImage(size: frame.size, flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 16, yRadius: 16).fill()
            return true
        }

        buildContent(deviceName: deviceName, hasCountdown: countdown != nil)

        if let countdown {
            deadline = Date().addingTimeInterval(countdown)
            startCountdown()
        }
    }

    override var canBecomeKey: Bool { true }

    // MARK: - Presentation

    func present() {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else {
            return
        }

        let visible = screen.visibleFrame
        let size = frame.size
        let target = NSPoint(
            x: visible.maxX - size.width - 16,
            y: visible.maxY - size.height - 16
        )

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        alphaValue = reduceMotion ? 1 : 0
        setFrameOrigin(reduceMotion ? target : NSPoint(x: target.x, y: target.y + 10))
        orderFrontRegardless()

        guard !reduceMotion else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
            animator().setFrameOrigin(target)
        }
    }

    func closeWithoutCallback() {
        timer?.invalidate()
        timer = nil
        isFinishing = true
        close(animated: true)
    }

    private func finish(_ outcome: Outcome) {
        guard !isFinishing else { return }
        isFinishing = true
        timer?.invalidate()
        timer = nil
        close(animated: true)

        switch outcome {
        case .switchNow: onSwitch?()
        case .dismissed: onDismiss?()
        }
    }

    private func close(animated: Bool) {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.16
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
        })
    }

    // MARK: - Content

    private func buildContent(deviceName: String, hasCountdown: Bool) {
        let iconView = NSImageView(image: NSApp.applicationIconImage)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: "Switch to iPhone Microphone?")
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let body = NSMutableAttributedString()
        body.append(NSAttributedString(
            string: "Lid closed and an external display is connected.\n",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11.5),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        ))
        body.append(NSAttributedString(
            string: deviceName,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11.5, weight: .medium),
                .foregroundColor: NSColor.labelColor
            ]
        ))
        let bodyLabel = NSTextField(labelWithAttributedString: body)
        bodyLabel.maximumNumberOfLines = 2
        bodyLabel.lineBreakMode = .byTruncatingTail
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false

        let switchButton = Button(title: "Switch Now", target: self, action: #selector(handleSwitch))
        switchButton.keyEquivalent = "\r"
        switchButton.bezelStyle = .rounded

        let dismissButton = Button(title: "Not Now", target: self, action: #selector(handleDismiss))
        dismissButton.keyEquivalent = "\u{1b}"
        dismissButton.bezelStyle = .rounded

        let buttons = NSStackView(views: [dismissButton, switchButton])
        buttons.orientation = .horizontal
        buttons.spacing = 10
        buttons.translatesAutoresizingMaskIntoConstraints = false

        countdownLabel.font = .systemFont(ofSize: 11)
        countdownLabel.textColor = .secondaryLabelColor
        countdownLabel.translatesAutoresizingMaskIntoConstraints = false

        countdownBar.translatesAutoresizingMaskIntoConstraints = false
        countdownBar.isHidden = !hasCountdown
        countdownLabel.isHidden = !hasCountdown

        effect.addSubview(iconView)
        effect.addSubview(titleLabel)
        effect.addSubview(bodyLabel)
        effect.addSubview(countdownLabel)
        effect.addSubview(countdownBar)
        effect.addSubview(buttons)

        var constraints: [NSLayoutConstraint] = [
            iconView.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 16),
            iconView.topAnchor.constraint(equalTo: effect.topAnchor, constant: 16),
            iconView.widthAnchor.constraint(equalToConstant: 40),
            iconView.heightAnchor.constraint(equalToConstant: 40),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -16),
            titleLabel.topAnchor.constraint(equalTo: effect.topAnchor, constant: 15),

            bodyLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            bodyLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            bodyLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),

            countdownLabel.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 16),
            countdownLabel.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -16),
            countdownLabel.topAnchor.constraint(equalTo: bodyLabel.bottomAnchor, constant: 14),

            countdownBar.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 16),
            countdownBar.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -16),
            countdownBar.topAnchor.constraint(equalTo: countdownLabel.bottomAnchor, constant: 6),
            countdownBar.heightAnchor.constraint(equalToConstant: 3),

            buttons.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -16)
        ]

        if hasCountdown {
            constraints.append(buttons.topAnchor.constraint(equalTo: countdownBar.bottomAnchor, constant: 14))
        } else {
            constraints.append(buttons.topAnchor.constraint(equalTo: bodyLabel.bottomAnchor, constant: 18))
        }

        NSLayoutConstraint.activate(constraints)
    }

    // MARK: - Countdown

    private func startCountdown() {
        countdownBar.progress = 1
        updateCountdownLabel(remaining: total ?? 0)

        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        guard let deadline, let total else { return }
        let remaining = deadline.timeIntervalSinceNow

        if remaining <= 0 {
            finish(.switchNow)
            return
        }

        countdownBar.progress = CGFloat(remaining / total)
        updateCountdownLabel(remaining: remaining)
    }

    private func updateCountdownLabel(remaining: TimeInterval) {
        let seconds = max(1, Int(ceil(remaining)))
        countdownLabel.stringValue = seconds == 1
            ? "Switching in 1 second"
            : "Switching in \(seconds) seconds"
    }

    // MARK: - Actions

    @objc private func handleSwitch() {
        finish(.switchNow)
    }

    @objc private func handleDismiss() {
        finish(.dismissed)
    }
}

private final class Button: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private final class CountdownBar: NSView {
    var progress: CGFloat = 1 {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let radius = bounds.height / 2
        NSColor.separatorColor.withAlphaComponent(0.35).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()

        let width = bounds.width * min(max(progress, 0), 1)
        guard width > 0 else { return }
        NSColor.controlAccentColor.setFill()
        NSBezierPath(
            roundedRect: NSRect(x: 0, y: 0, width: width, height: bounds.height),
            xRadius: radius,
            yRadius: radius
        ).fill()
    }
}
