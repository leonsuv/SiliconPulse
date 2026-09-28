import CoreGraphics
import Foundation

let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
guard let entries = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
    print("CGWINDOW_UNAVAILABLE")
    exit(0)
}
let windows = entries.filter { entry in
    guard let owner = entry[kCGWindowOwnerName as String] as? String,
          owner == "SiliconPulse",
          let bounds = entry[kCGWindowBounds as String] as? [String: CGFloat] else { return false }
    return (bounds["Width"] ?? 0) >= 280 && (bounds["Height"] ?? 0) >= 240
}
print(windows.isEmpty ? "CGWINDOW_PANEL_NOT_FOUND" : "CGWINDOW_PANEL_ON_SCREEN")
