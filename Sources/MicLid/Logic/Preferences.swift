import Foundation

enum TriggerMode: String, CaseIterable {
    case prompt
    case automatic
    case off

    var title: String {
        switch self {
        case .prompt: return "Ask to Switch"
        case .automatic: return "Switch Automatically"
        case .off: return "Do Nothing"
        }
    }
}

final class Preferences {
    private enum Key {
        static let mode = "triggerMode"
    }

    private let defaults = UserDefaults.standard

    var mode: TriggerMode {
        get {
            guard let raw = defaults.string(forKey: Key.mode), let mode = TriggerMode(rawValue: raw) else {
                return .prompt
            }
            return mode
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.mode)
        }
    }
}
