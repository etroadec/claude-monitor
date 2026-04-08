import Foundation
import os

private let logger = Logger(subsystem: "com.edgard.claude-monitor", category: "app")

func debugLog(_ msg: String) {
    #if DEBUG
    logger.debug("\(msg, privacy: .public)")
    #endif
    // No file logging — tokens must never be written to disk
}
