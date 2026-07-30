import CoreGraphics
import Foundation

// REQ-104: locates the on-screen window(s) owned by a process whose name contains the given
// argument, printing each CGWindowID on its own line. Used by smoke-screenshot.sh so it can
// capture only that window (screencapture -l<id>), never the full screen — a full-screen
// capture would leak whatever else happens to be on screen, unrelated to this verification.
//
// Needs no Accessibility permission: CGWindowListCopyWindowInfo is a lower-level API than
// AppleScript/System Events UI scripting. It does need the calling process to have Screen
// Recording permission to see window names, but window IDs and owner names are what this tool
// actually reads.
guard CommandLine.arguments.count > 1 else {
    FileHandle.standardError.write("usage: find-window-id <owner-name-substring>\n".data(using: .utf8)!)
    exit(1)
}
let needle = CommandLine.arguments[1]

guard let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: AnyObject]] else {
    exit(1)
}

for entry in list {
    guard let ownerName = entry[kCGWindowOwnerName as String] as? String,
          ownerName.contains(needle),
          let windowID = entry[kCGWindowNumber as String] as? Int,
          let layer = entry[kCGWindowLayer as String] as? Int,
          layer == 0 else { continue }
    print(windowID)
}
