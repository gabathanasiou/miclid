import AppKit
import CoreAudio
import Foundation

final class Controller {
    enum SwitchReason {
        case prompt
        case automatic
        case manual
    }

    private struct RestoreTarget {
        let previousUID: String?
        let switchedToUID: String
    }

    private let audio = AudioSystem()
    private let lid = LidState()
    private let preferences = Preferences()
    private let prompt = SwitchPrompt()

    private var pollTimer: Timer?
    private var evaluationWork: DispatchWorkItem?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var defaultObservers: [NSObjectProtocol] = []

    private var cachedDevices: [AudioDeviceInfo] = []
    private var audioListDirty = true

    private var environmentActive = false
    private var recommendationActive = false
    private var suppressed = false
    private var handledThisEpisode = false
    private var restoreTarget: RestoreTarget?

    private(set) var conditions = Conditions()
    var onChange: (() -> Void)?

    var mode: TriggerMode { preferences.mode }
    var isSuppressed: Bool { suppressed }
    var isRecommendationActive: Bool { recommendationActive }

    var inputDevices: [AudioDeviceInfo] {
        audio.devices().filter { $0.hasInput }
    }

    // MARK: - Lifecycle

    func start() {
        guard pollTimer == nil else { return }

        prompt.onSwitch = { [weak self] in
            self?.switchToiPhone(reason: .prompt)
        }
        prompt.onDismiss = { [weak self] in
            self?.suppressed = true
            self?.onChange?()
        }

        audio.onDevicesChanged = { [weak self] in
            self?.audioListDirty = true
            self?.scheduleEvaluation()
        }
        audio.onDefaultInputChanged = { [weak self] in self?.scheduleEvaluation() }
        audio.startMonitoring()

        workspaceObservers.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.audioListDirty = true
                self?.scheduleEvaluation(after: 2.0)
            }
        )

        defaultObservers.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.scheduleEvaluation()
            }
        )

        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.evaluate()
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer

        evaluate()
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        evaluationWork?.cancel()
        prompt.dismiss()
        audio.stopMonitoring()
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceObservers.removeAll()
        defaultObservers.forEach { NotificationCenter.default.removeObserver($0) }
        defaultObservers.removeAll()
    }

    // MARK: - Actions

    func switchToiPhone(reason: SwitchReason = .manual) {
        guard let iPhone = conditions.iPhone ?? inputDevices.first(where: { $0.role == .iphone }) else { return }
        setInput(iPhone, recordRestore: reason != .manual)
    }

    func switchInput(to device: AudioDeviceInfo) {
        setInput(device, recordRestore: false)
    }

    func showPrompt() {
        suppressed = false
        handledThisEpisode = false
        guard let iPhone = iPhoneDevice else { return }
        handledThisEpisode = true
        prompt.present(deviceName: iPhone.name, countdown: nil)
        onChange?()
    }

    func setMode(_ mode: TriggerMode) {
        preferences.mode = mode
        if mode == .off {
            prompt.dismiss()
        }
        if mode == .automatic, recommendationActive {
            switchToiPhone(reason: .automatic)
        }
        onChange?()
    }

    // MARK: - Evaluation

    private var iPhoneDevice: AudioDeviceInfo? {
        conditions.iPhone ?? inputDevices.first { $0.role == .iphone }
    }

    private func scheduleEvaluation(after delay: TimeInterval = 0.8) {
        evaluationWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.evaluate() }
        evaluationWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func evaluate() {
        let currentID = audio.defaultInputID()
        var devices = currentDevices()

        var current = devices.first { $0.id == currentID }
        if current == nil, currentID != nil {
            audioListDirty = true
            devices = currentDevices()
            current = devices.first { $0.id == currentID }
        }

        var updated = Conditions()
        updated.externalDisplays = DisplayState.externalDisplays()
        updated.lidClosed = lid.isClosed
        updated.headset = devices.first { $0.role == .airpods || $0.role == .headset }
        updated.iPhone = devices.first { $0.role == .iphone }
        updated.currentInput = current

        let changed = updated != conditions
        conditions = updated

        let environment = Decider.environmentSatisfied(updated)
        let recommendation = Decider.shouldRecommend(updated)

        if environment, !environmentActive {
            beginEpisode()
        } else if !environment, environmentActive {
            endEpisode()
        }

        if recommendation, !recommendationActive {
            handleRecommendationBegan()
        }

        if recommendation != recommendationActive {
            Log.info("Recommendation active: \(recommendation) (input: \(updated.currentInput?.name ?? "none"))")
        }

        environmentActive = environment
        recommendationActive = recommendation

        if changed {
            onChange?()
        }
    }

    private func currentDevices() -> [AudioDeviceInfo] {
        if audioListDirty || cachedDevices.isEmpty {
            cachedDevices = audio.devices()
            audioListDirty = false
        }
        return cachedDevices
    }

    private func beginEpisode() {
        suppressed = false
        handledThisEpisode = false
        Log.info("Clamshell environment detected")
    }

    private func endEpisode() {
        suppressed = false
        handledThisEpisode = false
        prompt.dismiss()
        restoreInputIfNeeded()
        Log.info("Clamshell environment ended")
    }

    private func handleRecommendationBegan() {
        switch preferences.mode {
        case .off:
            break
        case .automatic:
            guard !handledThisEpisode else { return }
            handledThisEpisode = true
            switchToiPhone(reason: .automatic)
        case .prompt:
            guard !suppressed, !handledThisEpisode, let iPhone = iPhoneDevice else { return }
            handledThisEpisode = true
            Log.info("Presenting switch prompt for \(iPhone.name)")
            prompt.present(deviceName: iPhone.name, countdown: 8)
        }
    }

    private func setInput(_ device: AudioDeviceInfo, recordRestore: Bool) {
        prompt.dismiss()
        let previous = conditions.currentInput ?? audio.currentInput()
        if recordRestore, previous?.uid != device.uid {
            restoreTarget = RestoreTarget(previousUID: previous?.uid, switchedToUID: device.uid)
        } else if !recordRestore {
            restoreTarget = nil
        }

        guard audio.setDefaultInput(device.id) else { return }
        conditions.currentInput = device
        Hud.shared.show(symbol: Self.symbol(for: device.role), text: device.name)
        onChange?()
    }

    private func restoreInputIfNeeded() {
        let devices = audio.devices()
        guard let currentID = audio.defaultInputID(),
              let current = devices.first(where: { $0.id == currentID }) else {
            restoreTarget = nil
            return
        }

        let destination = Decider.restoreDestination(
            current: current,
            devices: devices,
            switchedToUID: restoreTarget?.switchedToUID,
            previousUID: restoreTarget?.previousUID
        )
        restoreTarget = nil

        guard let destination, destination.id != current.id else { return }
        guard audio.setDefaultInput(destination.id) else { return }
        conditions.currentInput = destination
        Hud.shared.show(symbol: Self.symbol(for: destination.role), text: destination.name)
    }

    static func symbol(for role: DeviceRole?) -> String {
        switch role {
        case .iphone?: return "iphone"
        case .airpods?: return "airpods"
        case .headset?: return "headphones"
        default: return "mic.fill"
        }
    }
}
