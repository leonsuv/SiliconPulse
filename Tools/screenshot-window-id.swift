import CoreGraphics
import Foundation

guard CommandLine.arguments.count == 3, let ownerPID = Int32(CommandLine.arguments[2]) else { fatalError("Usage: screenshot-window-id.swift panel|overlay|settings pid") }
let target = CommandLine.arguments[1]
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
let own = windows.filter {
    ($0[kCGWindowOwnerName as String] as? String) == "SiliconPulse" &&
    ($0[kCGWindowOwnerPID as String] as? Int32) == ownerPID &&
    (($0[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 0) > 0
}
let selected: [String: Any]?
switch target {
case "settings": selected = own.first { ($0[kCGWindowName as String] as? String) == "SiliconPulse Settings" }
    ?? own.filter { width($0) >= 800 && width($0) < 900 && height($0) >= 680 }.max { area($0) < area($1) }
case "overlay": selected = own.filter { (($0[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0) >= 1000 }.max { area($0) < area($1) }
default: selected = own.filter {
    let layer = ($0[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
    return layer >= 3 && layer < 1000
}.max { area($0) < area($1) }
}
guard let selected, let number = selected[kCGWindowNumber as String] else { exit(2) }
print(number)

func area(_ window: [String: Any]) -> Double {
    guard let bounds = window[kCGWindowBounds as String] as? [String: CGFloat] else { return 0 }
    return Double((bounds["Width"] ?? 0) * (bounds["Height"] ?? 0))
}

func width(_ window: [String: Any]) -> CGFloat {
    guard let bounds = window[kCGWindowBounds as String] as? [String: CGFloat] else { return 0 }
    return bounds["Width"] ?? 0
}

func height(_ window: [String: Any]) -> CGFloat {
    guard let bounds = window[kCGWindowBounds as String] as? [String: CGFloat] else { return 0 }
    return bounds["Height"] ?? 0
}
