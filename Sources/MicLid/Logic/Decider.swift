import CoreAudio

enum QuickToggleResult: Equatable {
    case switchTo(AudioDeviceID)
    case showMenu
}

enum Decider {
    static func environmentSatisfied(_ conditions: Conditions) -> Bool {
        conditions.hasExternalDisplay && conditions.lidClosed && conditions.headset == nil
    }

    static func shouldRecommend(_ conditions: Conditions) -> Bool {
        environmentSatisfied(conditions)
            && conditions.iPhone != nil
            && conditions.currentInput?.role == .builtIn
    }

    static func toggleDestination(current: AudioDeviceInfo?, devices: [AudioDeviceInfo]) -> QuickToggleResult {
        let inputs = devices.filter { $0.hasInput }
        let iPhone = inputs.first { $0.role == .iphone }
        let airPods = inputs.first { $0.role == .airpods }
        let builtIn = inputs.first { $0.role == .builtIn }

        let destination: AudioDeviceInfo?
        switch current?.role {
        case .iphone?:
            destination = airPods ?? builtIn
        case .airpods?:
            destination = iPhone ?? builtIn
        case .builtIn?:
            destination = iPhone
        case .headset?, .other?, .none:
            destination = iPhone ?? airPods ?? builtIn
        }

        guard let destination, destination.id != current?.id else { return .showMenu }
        return .switchTo(destination.id)
    }

    static func restoreDestination(
        current: AudioDeviceInfo?,
        devices: [AudioDeviceInfo],
        switchedToUID: String?,
        previousUID: String?
    ) -> AudioDeviceInfo? {
        guard let current else { return nil }

        if let switchedToUID, current.uid == switchedToUID {
            if let previousUID, let previous = devices.first(where: { $0.uid == previousUID }) {
                return previous
            }
            return devices.first { $0.role == .builtIn && $0.hasInput }
        }

        // The iPhone mic is a clamshell workaround, so leave it behind when the
        // setup ends even if it was selected by hand.
        if current.role == .iphone {
            return devices.first { $0.role == .builtIn && $0.hasInput }
        }

        return nil
    }
}
