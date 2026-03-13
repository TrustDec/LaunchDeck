import Foundation
import OSLog
import Darwin

enum LaunchDeckDiagnostics {
    private static let logger = Logger(subsystem: "LaunchDeck", category: "Startup")
    private static let processInfo = ProcessInfo.processInfo
    private static let launchUptime = processInfo.systemUptime

    static var disablePager: Bool {
        flag(named: "LAUNCHDECK_DISABLE_PAGER")
    }

    static var disableBackdrop: Bool {
        flag(named: "LAUNCHDECK_DISABLE_BACKDROP")
    }

    static var disableCatalog: Bool {
        flag(named: "LAUNCHDECK_DISABLE_CATALOG")
    }

    static var useAppKitPager: Bool {
        flag(named: "LAUNCHDECK_USE_APPKIT_PAGER")
    }

    static func log(_ message: String) {
        let elapsed = Int((processInfo.systemUptime - launchUptime) * 1000)
        let memory = memoryFootprintMB().map { "\($0)MB" } ?? "n/a"
        let decorated = "+\(elapsed)ms [mem \(memory)] \(message)"
        logger.info("\(decorated, privacy: .public)")
        print("[LaunchDeck] \(decorated)")
    }

    static func logIconLoad(path: String, duration: TimeInterval, cacheHit: Bool) {
        guard !cacheHit || duration >= 0.012 else {
            return
        }

        let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        let ms = Int(duration * 1000)
        log("icon resolved name=\(name) cacheHit=\(cacheHit) duration=\(ms)ms")
    }

    private static func flag(named name: String) -> Bool {
        guard let value = processInfo.environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return false
        }

        return value == "1" || value == "true" || value == "yes"
    }

    private static func memoryFootprintMB() -> Int? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result: kern_return_t = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), rebound, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return nil
        }

        return Int(info.resident_size) / 1_048_576
    }
}
