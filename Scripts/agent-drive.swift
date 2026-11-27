// Drives the real app through a scenario, the way a person uses it on a Mac, and records what it
// looks like after each step, so an agent that cannot see the Mac (a cloud session) can operate it
// and inspect the result: window and screen captures, accessibility trees, element values, files
// on disk, and the app's own diagnostic log, all left in one folder.
// `.github/workflows/agent-drive.yml` runs it on a GitHub Mac runner, whose runner process is
// trusted for Accessibility (AXIsProcessTrusted is true there: UI probe, PR #97, run 45942394078).
//
// It is an instrument for an agent's eyes and hands, never a test and never a gate (CLAUDE.md §4).
// `expect` steps exist so a scenario can say what it was looking for; they make the run's verdict
// readable, and nothing requires that verdict.
//
//   agent-drive <app> <work-dir> <out-dir> <diagnostics-dir> < scenario
//
// The driver launches and quits the app itself, through Launch Services as Finder and the Dock do.
// A scenario is one step per line; `#` starts a comment, and an argument with spaces is quoted.
// `$WORK` in a step is the work directory (fixtures are copied there). LABEL is an element's
// accessibility title, description or identifier, as `tree` prints them (title="Bold",
// desc="Markdown WYSIWYG"); the frontmost window is searched first, then the rest of the app.
//
// The app
//   launch [FILE]              open the app, onto FILE if given, and wait for it to be running
//   quit                       cmd-Q, and wait for the app to end (it may stop at a dialog)
//   kill                       end the app without asking it
//   expect-running / expect-not-running
//   expect-windows N           how many windows the app has
//   expect-window TEXT         a window whose title contains TEXT
//   expect-no-window TEXT      no window whose title contains TEXT
//   raise TEXT                 bring the window whose title contains TEXT to the front
//   resize W H                 set the front window's size, in points
// Looking
//   shot NAME                  capture of the front window only
//   shot-screen NAME           capture of the whole screen: for sheets, panels and menus
//   tree NAME                  the accessibility tree, to NAME.txt
//   windows                    every window of the app: title, frame, size
//   focused                    which element has keyboard focus
//   value LABEL                the element's value, whole, to the transcript and a file
//   selection LABEL            the element's selected range
//   menu-items TOP             list a menu's items: enabled or not, and their shortcuts
//   faults                     the app's fault, error and warn records since the last `faults`
// Doing
//   press LABEL                accessibility press: buttons, segments, checkboxes, menu buttons
//   menu TOP ITEM [SUBITEM…]   open a menu and choose an item, e.g. menu View "Source Mode"
//   click LABEL                a real mouse click on the middle of the element's visible part
//   clickat X Y                a real mouse click at a point of the front window, in points
//   scroll LABEL LINES         real scroll-wheel events over the element (negative scrolls up)
//   focus LABEL                give the element keyboard focus
//   caret LABEL LOC [LEN]      set a text element's selection (UTF-16 offsets into its value)
//   select LABEL TEXT          select the first TEXT in the element's value
//   caret-after LABEL TEXT     put the caret just after the first TEXT in the element's value
//   type TEXT                  real key events carrying TEXT
//   type-field TEXT            wait for a text field (a dialog's, a sheet's) to have keyboard
//                              focus, type TEXT into it as `type` does, and wait to see it there
//   key COMBO                  one real key press: cmd+s, return, shift+left, cmd+b, escape…
//   clipboard-text TEXT / clipboard-image PATH
//   shell COMMAND…             run a shell command, as another app or the user in Terminal would
//   appearance dark|light      switch the system appearance
//   wait SECONDS
// Checking
//   expect-value LABEL TEXT    the element's value contains TEXT
//   expect-no-value LABEL TEXT the element's value does not contain TEXT
//   expect-element LABEL / expect-no-element LABEL
//   no-dialogs                 the front window is a document with no sheet; any dialog still
//                              open is a failure, and is closed with Escape so the next section
//                              starts from a document, as a person would close it
//   expect-enabled LABEL / expect-disabled LABEL
//   expect-file PATH TEXT      the file contains TEXT
//   expect-no-file PATH TEXT   the file does not contain TEXT
//   expect-exists PATH / expect-missing PATH
//   expect-no-faults           no fault or error record since the last `faults` or `expect-no-faults`
//   file PATH NAME             a copy of the file, to NAME.md
//
// Everything is written to transcript.txt in the out-dir, one numbered, timed line per step, and
// each file it writes is named with that step's number. Exit status 1 if an expectation failed,
// 2 for a scenario it could not run.

import AppKit
import ApplicationServices

let arguments = CommandLine.arguments
guard arguments.count == 5 else {
    FileHandle.standardError.write("usage: agent-drive <app> <work-dir> <out-dir> <diagnostics-dir> < scenario\n".data(using: .utf8)!)
    exit(2)
}
let appURL = URL(fileURLWithPath: arguments[1])
let workDirectory = URL(fileURLWithPath: arguments[2], isDirectory: true)
let outDirectory = URL(fileURLWithPath: arguments[3], isDirectory: true)
let diagnosticsDirectory = URL(fileURLWithPath: arguments[4], isDirectory: true)
try? FileManager.default.createDirectory(at: outDirectory, withIntermediateDirectories: true)
try? FileManager.default.createDirectory(at: diagnosticsDirectory, withIntermediateDirectories: true)
let bundleIdentifier = Bundle(url: appURL)?.bundleIdentifier ?? "net.melisma.Markdown-Editor"

var pid: pid_t?
var transcript = ""
var step = 0
var failures = 0
var faultLinesSeen: [String: Int] = [:]

let clock: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withTime, .withColonSeparatorInTime, .withFractionalSeconds]
    return formatter
}()

/// Each line carries the UTC time, in the app's diagnostic log's format, so a step can be matched
/// to what the app recorded while it ran.
func log(_ line: String) {
    let numbered = String(format: "%02d ", step) + clock.string(from: Date()) + " " + line
    print(numbered)
    transcript += numbered + "\n"
}

func fail(_ line: String) {
    failures += 1
    log("  FAIL: " + line)
}

func pass(_ line: String) {
    log("  PASS: " + line)
}

func outFile(_ name: String, _ ext: String) -> URL {
    let safe = name.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "-" }
    return outDirectory.appendingPathComponent(String(format: "%03d-", step) + String(safe) + "." + ext)
}

func resolvePath(_ path: String) -> URL {
    path.hasPrefix("/") ? URL(fileURLWithPath: path) : workDirectory.appendingPathComponent(path)
}

// MARK: The app's process

func runningApp() -> NSRunningApplication? {
    guard let pid else { return nil }
    let app = NSRunningApplication(processIdentifier: pid)
    return (app?.isTerminated ?? true) ? nil : app
}

var app: AXUIElement? { runningApp().map { AXUIElementCreateApplication($0.processIdentifier) } }

func run(_ executable: String, _ args: [String]) -> (status: Int32, output: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = args
    var environment = ProcessInfo.processInfo.environment
    environment["WORK"] = workDirectory.path
    process.environment = environment
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    do {
        try process.run()
    } catch {
        return (127, "\(error)")
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, String(decoding: data, as: UTF8.self))
}

func waitUntil(_ seconds: Double, _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if condition() { return true }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    return condition()
}

// MARK: Accessibility

func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
    var value: AnyObject?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}

func text(_ element: AXUIElement, _ name: String) -> String {
    guard let value = attribute(element, name) else { return "" }
    if let string = value as? String { return string }
    if let number = value as? NSNumber { return number.stringValue }
    return ""
}

func children(_ element: AXUIElement) -> [AXUIElement] {
    (attribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
}

func frame(_ element: AXUIElement) -> CGRect {
    var origin = CGPoint.zero, size = CGSize.zero
    if let value = attribute(element, kAXPositionAttribute) { AXValueGetValue(value as! AXValue, .cgPoint, &origin) }
    if let value = attribute(element, kAXSizeAttribute) { AXValueGetValue(value as! AXValue, .cgSize, &size) }
    return CGRect(origin: origin, size: size)
}

func describe(_ element: AXUIElement) -> String {
    var line = text(element, kAXRoleAttribute)
    for (name, label) in [(kAXTitleAttribute, "title"), (kAXDescriptionAttribute, "desc"),
                          (kAXIdentifierAttribute, "id"), (kAXHelpAttribute, "help")] {
        let value = text(element, name)
        if !value.isEmpty { line += " \(label)=\"\(value.prefix(60))\"" }
    }
    let value = text(element, kAXValueAttribute)
    if !value.isEmpty { line += " value=\"\(value.prefix(160).replacingOccurrences(of: "\n", with: "⏎"))\"" }
    if (attribute(element, kAXEnabledAttribute) as? Bool) == false { line += " disabled" }
    if (attribute(element, kAXFocusedAttribute) as? Bool) == true { line += " focused" }
    let rect = frame(element)
    return line + " [\(Int(rect.minX)),\(Int(rect.minY)) \(Int(rect.width))x\(Int(rect.height))]"
}

func tree(_ element: AXUIElement, depth: Int, into output: inout String) {
    guard depth <= 16 else { return }
    output += String(repeating: "  ", count: depth) + describe(element) + "\n"
    // A closed menu's items have no geometry and repeat on every dump; `menu-items` lists them.
    if text(element, kAXRoleAttribute) == "AXMenuBarItem" { return }
    for child in children(element) { tree(child, depth: depth + 1, into: &output) }
}

func windows() -> [AXUIElement] {
    guard let app else { return [] }
    return (attribute(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []
}

func frontWindow() -> AXUIElement? {
    guard let app else { return nil }
    if let focused = attribute(app, kAXFocusedWindowAttribute) { return (focused as! AXUIElement) }
    if let main = attribute(app, kAXMainWindowAttribute) { return (main as! AXUIElement) }
    return windows().first
}

func search(_ element: AXUIElement, _ label: String, depth: Int = 0) -> AXUIElement? {
    guard depth <= 20 else { return nil }
    for name in [kAXTitleAttribute, kAXDescriptionAttribute, kAXIdentifierAttribute] where text(element, name) == label {
        return element
    }
    for child in children(element) {
        if let found = search(child, label, depth: depth + 1) { return found }
    }
    return nil
}

/// The front window first, so its toolbar's "Bold" wins over the Format menu's, then the others.
func find(_ label: String) -> AXUIElement? {
    if let front = frontWindow(), let found = search(front, label) { return found }
    for window in windows() { if let found = search(window, label) { return found } }
    return app.flatMap { search($0, label) }
}

func require(_ label: String) -> AXUIElement? {
    if let element = find(label) { return element }
    fail("no element labelled \"\(label)\"")
    return nil
}

// MARK: Real input events

func activate() {
    _ = runningApp()?.activate()
    usleep(150_000)
}

func click(_ point: CGPoint) {
    activate()
    let source = CGEventSource(stateID: .hidSystemState)
    CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?
        .post(tap: .cghidEventTap)
    usleep(80_000)
    for kind in [CGEventType.leftMouseDown, .leftMouseUp] {
        let event = CGEvent(mouseEventSource: source, mouseType: kind, mouseCursorPosition: point, mouseButton: .left)
        event?.setIntegerValueField(.mouseEventClickState, value: 1)
        event?.post(tap: .cghidEventTap)
        usleep(40_000)
    }
}

func scroll(at point: CGPoint, lines: Int32) {
    activate()
    let source = CGEventSource(stateID: .hidSystemState)
    CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?
        .post(tap: .cghidEventTap)
    usleep(80_000)
    let step: Int32 = lines < 0 ? 1 : -1
    for _ in 0..<abs(lines) {
        CGEvent(scrollWheelEvent2Source: source, units: .line, wheelCount: 1, wheel1: step, wheel2: 0, wheel3: 0)?
            .post(tap: .cghidEventTap)
        usleep(30_000)
    }
}

let keyCodes: [String: CGKeyCode] = [
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11,
    "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21,
    "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29, "]": 30, "o": 31,
    "u": 32, "[": 33, "i": 34, "p": 35, "return": 36, "l": 37, "j": 38, "'": 39, "k": 40,
    ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46, ".": 47, "tab": 48, "space": 49,
    "`": 50, "delete": 51, "escape": 53, "home": 115, "pageup": 116, "forwarddelete": 117,
    "end": 119, "pagedown": 121, "left": 123, "right": 124, "down": 125, "up": 126,
]

func key(_ combo: String) -> Bool {
    var flags: CGEventFlags = []
    var code: CGKeyCode?
    for part in combo.lowercased().split(separator: "+").map(String.init) {
        switch part {
        case "cmd", "command": flags.insert(.maskCommand)
        case "shift": flags.insert(.maskShift)
        case "opt", "option", "alt": flags.insert(.maskAlternate)
        case "ctrl", "control": flags.insert(.maskControl)
        default: code = keyCodes[part]
        }
    }
    guard let code else { return false }
    activate()
    let source = CGEventSource(stateID: .hidSystemState)
    for down in [true, false] {
        let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
        event?.flags = flags
        event?.post(tap: .cghidEventTap)
        usleep(30_000)
    }
    return true
}

func typeText(_ string: String) {
    activate()
    let source = CGEventSource(stateID: .hidSystemState)
    for unit in string.utf16 {
        var character = unit
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down)
            event?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &character)
            event?.post(tap: .cghidEventTap)
        }
        usleep(25_000)
    }
}

// MARK: Looking

/// The window server's number for the app's front window: the on-screen window of the app's
/// process whose bounds match the accessibility front window, or else its largest one.
func frontWindowNumber() -> Int? {
    guard let pid, let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: AnyObject]] else {
        return nil
    }
    let owned = list.filter { ($0[kCGWindowOwnerPID as String] as? Int32) == pid && ($0[kCGWindowLayer as String] as? Int) == 0 }
    func bounds(_ info: [String: AnyObject]) -> CGRect {
        guard let dictionary = info[kCGWindowBounds as String] as? NSDictionary,
              let rect = CGRect(dictionaryRepresentation: dictionary) else { return .zero }
        return rect
    }
    if let front = frontWindow() {
        let target = frame(front)
        if let match = owned.first(where: { abs(bounds($0).minX - target.minX) < 2 && abs(bounds($0).minY - target.minY) < 2 }) {
            return match[kCGWindowNumber as String] as? Int
        }
    }
    return owned.max { bounds($0).width * bounds($0).height < bounds($1).width * bounds($1).height }?[kCGWindowNumber as String] as? Int
}

func capture(_ name: String, screen: Bool) {
    let url = outFile(name, "png")
    var args = ["-x", url.path]
    if !screen {
        guard let number = frontWindowNumber() else {
            fail("no window of the app is on screen to capture")
            return
        }
        args = ["-x", "-o", "-l\(number)", url.path]
    }
    let result = run("/usr/sbin/screencapture", args)
    let size = frontWindow().map(frame) ?? .zero
    log("  \(url.lastPathComponent)\(result.status == 0 ? "" : " (screencapture: \(result.output))") — front window \(Int(size.width))x\(Int(size.height)) at \(Int(size.minX)),\(Int(size.minY))")
}

func fileText(_ url: URL) -> String? {
    try? String(contentsOf: url, encoding: .utf8)
}

/// The app's fault, error and warn records written since the last call, from every run's log.
func newFaultRecords() -> [String] {
    let files = (try? FileManager.default.contentsOfDirectory(at: diagnosticsDirectory, includingPropertiesForKeys: nil)) ?? []
    var found: [String] = []
    for file in files where file.pathExtension == "jsonl" {
        let lines = (fileText(file) ?? "").split(separator: "\n", omittingEmptySubsequences: true)
        let seen = faultLinesSeen[file.lastPathComponent] ?? 0
        for line in lines.dropFirst(seen) where line.contains("\"lvl\":\"fault\"") || line.contains("\"lvl\":\"error\"") || line.contains("\"lvl\":\"warn\"") {
            found.append(String(line.prefix(400)))
        }
        faultLinesSeen[file.lastPathComponent] = lines.count
    }
    return found
}

func tokens(_ line: String) -> [String] {
    var result: [String] = [], current = "", quoted = false, started = false
    for character in line {
        if character == "\"" { quoted.toggle(); started = true; continue }
        if character == " " && !quoted {
            if started || !current.isEmpty { result.append(current) }
            current = ""; started = false
            continue
        }
        current.append(character)
    }
    if started || !current.isEmpty { result.append(current) }
    return result
}

func finish() -> Never {
    if let running = runningApp() {
        running.forceTerminate()
        _ = waitUntil(5) { runningApp() == nil }
    }
    try? transcript.write(to: outDirectory.appendingPathComponent("transcript.txt"), atomically: true, encoding: .utf8)
    exit(failures == 0 ? 0 : 1)
}

// MARK: The scenario

while let raw = readLine() {
    let line = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "$WORK", with: workDirectory.path)
    if line.isEmpty || line.hasPrefix("#") { continue }
    step += 1
    log(line)
    let words = tokens(line)
    let rest = Array(words.dropFirst())
    let needsApp: Set<String> = [
        "shot", "tree", "windows", "focused", "value", "selection", "menu-items", "press", "menu", "click",
        "clickat", "scroll", "focus", "caret", "select", "caret-after", "type", "type-field", "key", "raise", "resize", "expect-value",
        "expect-no-value", "expect-element", "expect-no-element", "expect-enabled", "expect-disabled",
        "expect-window", "expect-windows", "expect-no-window", "no-dialogs",
    ]
    if needsApp.contains(words[0]), runningApp() == nil {
        fail("the app is not running")
        continue
    }
    switch (words[0], rest.count) {
    case ("launch", 0), ("launch", 1):
        if runningApp() != nil { fail("the app is already running"); continue }
        let started = Date()
        var args = ["-n", "-a", appURL.path, "--env", "MARKDOWN_EDITOR_DIAGNOSTICS_DIR=\(diagnosticsDirectory.path)"]
        if rest.count == 1 { args.append(resolvePath(rest[0]).path) }
        let result = run("/usr/bin/open", args)
        if result.status != 0 { fail("open: \(result.output)"); continue }
        let launched = waitUntil(20) {
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
                .contains { ($0.launchDate ?? .distantPast) >= started.addingTimeInterval(-1) && !$0.isTerminated }
        }
        guard launched, let instance = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter({ !$0.isTerminated }).max(by: { ($0.launchDate ?? .distantPast) < ($1.launchDate ?? .distantPast) }) else {
            fail("the app did not start within 20 s")
            continue
        }
        pid = instance.processIdentifier
        let hasWindow = waitUntil(15) { !windows().isEmpty }
        log("  pid \(instance.processIdentifier), \(windows().count) window(s)\(hasWindow ? "" : " after 15 s"): \(windows().map { text($0, kAXTitleAttribute) })")
    case ("quit", 0):
        _ = key("cmd+q")
        if waitUntil(10, { runningApp() == nil }) {
            log("  the app ended")
            pid = nil
        } else {
            log("  still running after 10 s: \(windows().map { text($0, kAXTitleAttribute) })")
        }
    case ("kill", 0):
        runningApp()?.forceTerminate()
        _ = waitUntil(5) { runningApp() == nil }
        pid = nil
        log("  ended")
    case ("expect-running", 0):
        runningApp() != nil ? pass("the app is running") : fail("the app is not running")
    case ("expect-not-running", 0):
        runningApp() == nil ? pass("the app is not running") : fail("the app is still running")
    case ("expect-windows", 1):
        let count = windows().count
        count == Int(rest[0]) ? pass("\(count) window(s)") : fail("\(count) window(s), not \(rest[0]): \(windows().map { text($0, kAXTitleAttribute) })")
    case ("expect-window", 1):
        let titles = windows().map { text($0, kAXTitleAttribute) }
        titles.contains { $0.contains(rest[0]) } ? pass("a window titled like \"\(rest[0])\"") : fail("no window titled like \"\(rest[0])\": \(titles)")
    case ("expect-no-window", 1):
        let titles = windows().map { text($0, kAXTitleAttribute) }
        titles.contains { $0.contains(rest[0]) } ? fail("a window titled like \"\(rest[0])\": \(titles)") : pass("no window titled like \"\(rest[0])\"")
    case ("raise", 1):
        if let window = windows().first(where: { text($0, kAXTitleAttribute).contains(rest[0]) }) {
            activate()
            _ = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            _ = AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
            log("  raised \(describe(window))")
        } else {
            fail("no window titled like \"\(rest[0])\"")
        }
    case ("resize", 2):
        if let window = frontWindow(), let width = Double(rest[0]), let height = Double(rest[1]) {
            var size = CGSize(width: width, height: height)
            let value = AXValueCreate(.cgSize, &size)!
            let status = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
            usleep(300_000)
            log("  → \(status.rawValue); now \(describe(window))")
        } else {
            fail("resize needs a front window and two numbers")
        }
    case ("shot", 1):
        capture(rest[0], screen: false)
    case ("shot-screen", 1):
        capture(rest[0], screen: true)
    case ("tree", 1):
        var output = ""
        if let app { tree(app, depth: 0, into: &output) }
        try? output.write(to: outFile(rest[0], "txt"), atomically: true, encoding: .utf8)
        log("  \(output.split(separator: "\n").count) elements")
    case ("windows", 0):
        for window in windows() { log("  \(describe(window))") }
    case ("press", 1):
        if let element = require(rest[0]) {
            log("  \(describe(element)) → \(AXUIElementPerformAction(element, kAXPressAction as CFString).rawValue)")
        }
    case ("menu-items", 1):
        // Opens one menu bar menu, lists every item with its enabled state and shortcut, and
        // closes it again: what the menu offers right now, as AppKit has just validated it.
        activate()
        let bar: AXUIElement? = app.flatMap { attribute($0, kAXMenuBarAttribute) }.map { $0 as! AXUIElement }
        if let top = bar.map(children)?.first(where: { text($0, kAXTitleAttribute) == rest[0] }) {
            _ = AXUIElementPerformAction(top, kAXPressAction as CFString)
            usleep(400_000)
            for menu in children(top) {
                for item in children(menu) {
                    let title = text(item, kAXTitleAttribute)
                    guard !title.isEmpty else { continue }
                    let enabled = (attribute(item, kAXEnabledAttribute) as? Bool) ?? true
                    let shortcut = text(item, "AXMenuItemCmdChar")
                    let modifiers = (attribute(item, "AXMenuItemCmdModifiers") as? NSNumber)?.intValue
                    log("  \(enabled ? "enabled " : "DISABLED") \(title)\(shortcut.isEmpty ? "" : "  key=\(shortcut) mods=\(modifiers ?? -1)")")
                }
            }
            _ = key("escape")
        } else {
            fail("no menu titled \(rest[0])")
        }
    case ("menu", 2...):
        // Opened first, as a person opens it: AppKit validates a menu's items when it opens, so an
        // item read from a closed menu carries whatever enabled state the last validation left
        // (agent-drive run 45943545906 found "WYSIWYG Mode" disabled in Source mode that way).
        // Then closed again before the item is pressed: an item pressed inside a menu opened this
        // way did nothing, and the menu went on tracking the keyboard, so the next shortcut was
        // lost too (agent-drive run 45948482951). Its validated state outlives the closing.
        activate()
        let bar: AXUIElement? = app.flatMap { attribute($0, kAXMenuBarAttribute) }.map { $0 as! AXUIElement }
        if let top = bar.map(children)?.first(where: { text($0, kAXTitleAttribute) == rest[0] }) {
            _ = AXUIElementPerformAction(top, kAXPressAction as CFString)
            usleep(400_000)
            _ = key("escape")
            usleep(200_000)
        }
        var current: AXUIElement? = bar
        for title in rest {
            // A menu bar item and a menu item hold their menu as their only child.
            let candidates = current.map(children) ?? []
            let items = candidates.count == 1 && text(candidates[0], kAXRoleAttribute) == "AXMenu"
                ? children(candidates[0]) : candidates
            current = items.first { text($0, kAXTitleAttribute) == title }
        }
        if let item = current {
            log("  \(describe(item)) → \(AXUIElementPerformAction(item, kAXPressAction as CFString).rawValue)")
        } else {
            fail("no menu item at \(rest.joined(separator: " › "))")
            _ = key("escape")
        }
    case ("click", 1):
        if let element = require(rest[0]) {
            var target = frame(element)
            if let window = frontWindow() { target = target.intersection(frame(window)) }
            let point = CGPoint(x: target.midX, y: target.midY)
            click(point)
            log("  clicked \(Int(point.x)),\(Int(point.y)) on \(describe(element))")
        }
    case ("clickat", 2):
        if let x = Double(rest[0]), let y = Double(rest[1]), let window = frontWindow() {
            let origin = frame(window).origin
            click(CGPoint(x: origin.x + x, y: origin.y + y))
            log("  clicked window point \(x),\(y)")
        } else {
            fail("clickat needs a window and two numbers")
        }
    case ("scroll", 2):
        if let element = require(rest[0]), let lines = Int32(rest[1]) {
            var target = frame(element)
            if let window = frontWindow() { target = target.intersection(frame(window)) }
            scroll(at: CGPoint(x: target.midX, y: target.midY), lines: lines)
            log("  scrolled \(lines) lines")
        }
    case ("focus", 1):
        if let element = require(rest[0]) {
            activate()
            log("  → \(AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue).rawValue)")
        }
    case ("caret", 2), ("caret", 3):
        if let element = require(rest[0]), let location = Int(rest[1]) {
            var range = CFRange(location: location, length: rest.count == 3 ? Int(rest[2]) ?? 0 : 0)
            let value = AXValueCreate(.cfRange, &range)!
            log("  → \(AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value).rawValue)")
        }
    case ("select", 2), ("caret-after", 2):
        if let element = require(rest[0]) {
            let value = text(element, kAXValueAttribute) as NSString
            let found = value.range(of: rest[1])
            if found.location == NSNotFound {
                fail("\"\(rest[1])\" is not in \"\(rest[0])\"")
            } else {
                var range = words[0] == "select"
                    ? CFRange(location: found.location, length: found.length)
                    : CFRange(location: NSMaxRange(found), length: 0)
                let axRange = AXValueCreate(.cfRange, &range)!
                activate()
                log("  \(range.location)+\(range.length) → \(AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, axRange).rawValue)")
            }
        }
    case ("type", 1...):
        typeText(rest.joined(separator: " "))
    case ("type-field", 1...):
        // A person waits for the field to appear before typing into it; key events sent before a
        // sheet has focus land in whatever had it.
        let wanted = rest.joined(separator: " ")
        func focusedField() -> AXUIElement? {
            guard let app, let focused = attribute(app, kAXFocusedUIElementAttribute) else { return nil }
            let element = focused as! AXUIElement
            let role = text(element, kAXRoleAttribute)
            return ["AXTextField", "AXComboBox", "AXSearchField", "AXTextArea"].contains(role) ? element : nil
        }
        guard waitUntil(5, { focusedField() != nil }), let field = focusedField() else {
            fail("no text field has keyboard focus")
            continue
        }
        typeText(wanted)
        if waitUntil(3, { text(field, kAXValueAttribute).contains(wanted) }) {
            pass("\(describe(field)) holds the text")
        } else {
            fail("\(describe(field)) reads \"\(text(field, kAXValueAttribute).prefix(200))\"")
        }
    case ("key", 1):
        if !key(rest[0]) { fail("unknown key \(rest[0])") }
    case ("clipboard-text", 1...):
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(rest.joined(separator: " "), forType: .string)
        log("  clipboard holds text")
    case ("clipboard-image", 1):
        if let image = NSImage(contentsOf: resolvePath(rest[0])) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([image])
            log("  clipboard holds an image \(Int(image.size.width))x\(Int(image.size.height))")
        } else {
            fail("no image at \(rest[0])")
        }
    case ("shell", 1...):
        let result = run("/bin/bash", ["-c", rest.joined(separator: " ")])
        log("  exit \(result.status)\(result.output.isEmpty ? "" : ": " + result.output.prefix(400).replacingOccurrences(of: "\n", with: "⏎"))")
        if result.status != 0 { failures += 1 }
    case ("appearance", 1):
        let dark = rest[0] == "dark"
        let result = run("/usr/bin/osascript", ["-e", "tell application \"System Events\" to tell appearance preferences to set dark mode to \(dark)"])
        log("  \(rest[0])\(result.status == 0 ? "" : " (osascript: \(result.output))")")
    case ("wait", 1):
        RunLoop.current.run(until: Date().addingTimeInterval(Double(rest[0]) ?? 1))
    case ("focused", 0):
        if let app, let element = attribute(app, kAXFocusedUIElementAttribute) {
            log("  \(describe(element as! AXUIElement))")
        } else {
            log("  nothing has keyboard focus")
        }
    case ("value", 1):
        if let element = require(rest[0]) {
            let value = text(element, kAXValueAttribute)
            let url = outFile(rest[0], "txt")
            try? value.write(to: url, atomically: true, encoding: .utf8)
            log("  \(value.utf16.count) UTF-16 units → \(url.lastPathComponent): \(value.prefix(300).replacingOccurrences(of: "\n", with: "⏎"))")
        }
    case ("selection", 1):
        if let element = require(rest[0]), let value = attribute(element, kAXSelectedTextRangeAttribute) {
            var range = CFRange()
            AXValueGetValue(value as! AXValue, .cfRange, &range)
            log("  location \(range.location), length \(range.length)")
        }
    case ("faults", 0):
        let records = newFaultRecords()
        log("  \(records.count) fault, error or warn record(s)")
        for record in records { log("    " + record) }
    case ("expect-no-faults", 0):
        let records = newFaultRecords().filter { $0.contains("\"lvl\":\"fault\"") || $0.contains("\"lvl\":\"error\"") }
        if records.isEmpty {
            pass("no fault or error records")
        } else {
            fail("\(records.count) fault or error record(s)")
            for record in records { log("    " + record) }
        }
    case ("file", 2):
        let url = outFile(rest[1], "md")
        if let content = fileText(resolvePath(rest[0])) {
            try? content.write(to: url, atomically: true, encoding: .utf8)
            log("  → \(url.lastPathComponent) (\(content.utf16.count) UTF-16 units)")
        } else {
            fail("no readable file at \(rest[0])")
        }
    case ("expect-value", 2), ("expect-no-value", 2):
        if let element = require(rest[0]) {
            let wanted = words[0] == "expect-value"
            let found = text(element, kAXValueAttribute).contains(rest[1])
            found == wanted ? pass("value of \"\(rest[0])\" \(found ? "contains" : "lacks") \"\(rest[1])\"")
                : fail("value of \"\(rest[0])\" \(found ? "contains" : "lacks") \"\(rest[1])\"")
        }
    case ("no-dialogs", 0):
        func dialogOpen() -> Bool {
            guard let front = frontWindow() else { return false }
            if text(front, kAXSubroleAttribute) != "AXStandardWindow" { return true }
            return children(front).contains { text($0, kAXRoleAttribute) == "AXSheet" }
        }
        var closed: [String] = []
        for _ in 0..<4 where dialogOpen() {
            if let front = frontWindow() { closed.append(describe(front)) }
            _ = key("escape")
            RunLoop.current.run(until: Date().addingTimeInterval(0.7))
        }
        if closed.isEmpty {
            pass("no dialog is open")
        } else {
            fail("closed with Escape: \(closed.joined(separator: "; "))\(dialogOpen() ? ", and one is still open" : "")")
        }
    case ("expect-element", 1):
        find(rest[0]) != nil ? pass("\"\(rest[0])\" is there") : fail("no element labelled \"\(rest[0])\"")
    case ("expect-no-element", 1):
        find(rest[0]) == nil ? pass("no \"\(rest[0])\"") : fail("\"\(rest[0])\" is there")
    case ("expect-enabled", 1), ("expect-disabled", 1):
        if let element = require(rest[0]) {
            let enabled = (attribute(element, kAXEnabledAttribute) as? Bool) ?? true
            let wanted = words[0] == "expect-enabled"
            enabled == wanted ? pass("\"\(rest[0])\" is \(enabled ? "enabled" : "disabled")")
                : fail("\"\(rest[0])\" is \(enabled ? "enabled" : "disabled")")
        }
    case ("expect-file", 2), ("expect-no-file", 2):
        let wanted = words[0] == "expect-file"
        if let content = fileText(resolvePath(rest[0])) {
            let found = content.contains(rest[1])
            found == wanted ? pass("\(rest[0]) \(found ? "contains" : "lacks") \"\(rest[1])\"")
                : fail("\(rest[0]) \(found ? "contains" : "lacks") \"\(rest[1])\"")
        } else {
            fail("no readable file at \(rest[0])")
        }
    case ("expect-exists", 1), ("expect-missing", 1):
        let exists = FileManager.default.fileExists(atPath: resolvePath(rest[0]).path)
        let wanted = words[0] == "expect-exists"
        exists == wanted ? pass("\(rest[0]) \(exists ? "exists" : "is missing")") : fail("\(rest[0]) \(exists ? "exists" : "is missing")")
    default:
        log("  not a step this driver knows (see the top of Scripts/agent-drive.swift)")
        failures += 1
        try? transcript.write(to: outDirectory.appendingPathComponent("transcript.txt"), atomically: true, encoding: .utf8)
        if let running = runningApp() { running.forceTerminate() }
        exit(2)
    }
}
step += 1
log("done: \(failures == 0 ? "every expectation held" : "\(failures) failed")")
finish()
