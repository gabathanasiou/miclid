import Foundation
import os

enum Log {
    private static let logger = Logger(subsystem: "com.gabrielathanasiou.miclid", category: "MicLid")
    private static let verbose = ProcessInfo.processInfo.environment["MICLID_DEBUG"] == "1"

    static func debug(_ message: String) {
        guard verbose else { return }
        logger.debug("\(message, privacy: .public)")
    }

    static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}
