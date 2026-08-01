import CoreGraphics
import Foundation

// REQ-104: locates the on-screen window(s) owned by a specific process ID, printing each
// CGWindowID on its own line. Used by smoke-screenshot.sh so it can capture only that window
// (screencapture -l<id>), never the full screen — a full-screen capture would leak whatever else
// happens to be on screen, unrelated to this verification.
//
// Matched by owner PID, not owner-name substring: if the user already has their own real
// Markdown Editor window open while this verification runs, a name-only match could select
// their document instead of the fixture this script just launched, capturing and reporting on
// unrelated (and potentially private) document content. Matching the exact PID this script
// launched is the only way to guarantee the right window.
//
// Needs no Accessibility permission: CGWindowListCopyWindowInfo is a lower-level API than
// AppleScript/System Events UI scripting. It does need the calling process to have Screen
// Recording permission to see window names/most metadata.
guard CommandLine.arguments.count > 1, let targetPID = Int32(CommandLine.arguments[1]) else {
    FileHandle.standardError.write("usage: find-window-id <pid>\n".data(using: .utf8)!)
    exit(1)
}

guard let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: AnyObject]] else {
    FileHandle.standardError.write("find-window-id: window list unavailable\n".data(using: .utf8)!)
    exit(2)
}

// Distinguish "no Screen Recording permission" from "the window is not up yet". Without the
// permission the list still returns entries, but window *names* are withheld — so a list with
// several windows and zero names means permission, and a list with names means the caller has
// it and any failure below is a different problem. Reported on stderr so the caller can say
// which of the two it is instead of guessing, and exit 3 is reserved for the permission case.
let namedWindows = list.filter { $0[kCGWindowName as String] as? String != nil }.count
if list.count > 3 && namedWindows == 0 {
    FileHandle.standardError.write(
        "find-window-id: \(list.count) windows visible, none named — Screen Recording permission is missing\n"
            .data(using: .utf8)!
    )
    exit(3)
}

for entry in list {
    guard let ownerPID = entry[kCGWindowOwnerPID as String] as? Int32,
          ownerPID == targetPID,
          let windowID = entry[kCGWindowNumber as String] as? Int,
          let layer = entry[kCGWindowLayer as String] as? Int,
          layer == 0 else { continue }
    print(windowID)
}
