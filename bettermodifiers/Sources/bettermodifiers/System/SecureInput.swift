import AppKit
import IOKit

/// Who is holding macOS secure event input. While any app holds it, the
/// event tap stops seeing keystrokes, so every remapper goes quiet.
struct SecureInputHolder: Equatable {
    let pid: pid_t
    let appName: String?

    /// Reads the console session from the IO registry, the same data
    /// `ioreg -l -w 0 | grep SecureInput` prints. There is no public API for it.
    static func current() -> SecureInputHolder? {
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        defer { IOObjectRelease(root) }
        guard let property = IORegistryEntryCreateCFProperty(
            root, "IOConsoleUsers" as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue(),
            let users = property as? [[String: Any]] else { return nil }

        let uid = getuid()
        let sessions = users.filter { ($0["kCGSSessionUserIDKey"] as? NSNumber)?.uint32Value == uid }
        for session in sessions.isEmpty ? users : sessions {
            guard let pid = (session["kCGSSessionSecureInputPID"] as? NSNumber)?.int32Value, pid > 0 else {
                continue
            }
            let name = NSRunningApplication(processIdentifier: pid)?.localizedName
            return SecureInputHolder(pid: pid, appName: name)
        }
        return nil
    }

    func activate() {
        NSRunningApplication(processIdentifier: pid)?.activate()
    }
}
