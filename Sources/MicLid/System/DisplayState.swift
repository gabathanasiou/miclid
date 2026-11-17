import AppKit
import CoreGraphics

enum DisplayState {
    static func externalDisplays() -> [String] {
        switch ProcessInfo.processInfo.environment["MICLID_FAKE_DISPLAY"] {
        case "none": return []
        case "external": return ["External Display"]
        default: break
        }

        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }

        var identifiers = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &identifiers, &count) == .success else { return [] }

        return identifiers
            .filter { CGDisplayIsBuiltin($0) == 0 }
            .map(name(for:))
    }

    private static func name(for identifier: CGDirectDisplayID) -> String {
        for screen in NSScreen.screens {
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            if number?.uint32Value == identifier {
                return screen.localizedName
            }
        }
        return "External Display"
    }
}
