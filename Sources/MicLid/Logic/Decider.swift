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
}
