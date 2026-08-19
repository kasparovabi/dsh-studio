import CoreGraphics
import Foundation

let opts = CGWindowListOption([.optionOnScreenOnly, .excludeDesktopElements])
if let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] {
    for w in list {
        let owner = w[kCGWindowOwnerName as String] as? String ?? ""
        let bounds = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
        let width = bounds["Width"] as? Double ?? 0
        if owner == "DSH Studio", width > 400 {
            print(w[kCGWindowNumber as String] as? Int ?? 0)
            break
        }
    }
}
