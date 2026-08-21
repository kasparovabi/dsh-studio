import CoreGraphics
import Foundation

// Pass the process id to capture. Matching on the app name alone finds whatever
// copy of DSH Studio is frontmost, which during verification is the window the
// user is actually working in.
let wanted = CommandLine.arguments.count > 1 ? Int(CommandLine.arguments[1]) : nil
let opts = CGWindowListOption([.optionOnScreenOnly, .excludeDesktopElements])
if let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] {
    for w in list {
        let owner = w[kCGWindowOwnerName as String] as? String ?? ""
        let pid = w[kCGWindowOwnerPID as String] as? Int ?? 0
        let bounds = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
        let width = bounds["Width"] as? Double ?? 0
        guard owner == "DSH Studio", width > 400 else { continue }
        if let wanted, pid != wanted { continue }
        print(w[kCGWindowNumber as String] as? Int ?? 0)
        break
    }
}
