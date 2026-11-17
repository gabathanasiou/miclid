import Foundation
import IOKit
import IOKit.pwr_mgt

final class LidState {
    private var service: io_service_t = 0

    deinit {
        if service != 0 {
            IOObjectRelease(service)
        }
    }

    var isClosed: Bool {
        switch ProcessInfo.processInfo.environment["MICLID_FAKE_LID"] {
        case "closed": return true
        case "open": return false
        default: break
        }

        if service == 0 {
            service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        }
        guard service != 0 else { return false }
        guard let property = IORegistryEntryCreateCFProperty(
            service,
            "AppleClamshellState" as CFString,
            kCFAllocatorDefault,
            0
        ) else {
            return false
        }
        let value = property.takeRetainedValue()
        return (value as? NSNumber)?.boolValue ?? false
    }
}
