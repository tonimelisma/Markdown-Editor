// Drives the running app through a scenario and records what it looks like after each step, so an
// agent that cannot see the Mac (a cloud session) can operate the real app and inspect the result:
// window screenshots, accessibility trees, element values, the saved file, and the app's own
// diagnostic log, all left in one folder. `.github/workflows/agent-drive.yml` runs it on a GitHub
// Mac runner, whose runner process is trusted for Accessibility (AXIsProcessTrusted is true there:
// UI probe, PR #97, run 45942394078).
//
// It is an instrument for an agent's eyes and hands, never a test and never a gate (CLAUDE.md §4).
// `expect` lines exist so a scenario can say what it was looking for; they make the run's verdict
// readable, and nothing requires that verdict.
//
//   agent-drive <pid> <window-id> <out-dir> <document> < scenario
//
// A scenario is one step per line; `#` starts a comment, and an argument with spaces is quoted.
// LABEL is an element's accessibility title, description or identifier, as `tree` prints them
// (title="Bold", desc="Markdown WYSIWYG"); the document window is searched before the menu bar.
//
//   shot NAME                  screenshot of the app's window only (never the screen)
//   tree NAME                  the accessibility tree, to NAME.txt
//   press LABEL                accessibility press: buttons, segments, checkboxes, menu buttons
//   menu TOP ITEM [SUBITEM…]   open a menu and choose an item, e.g. menu View "Source Mode"
//   menu-items TOP             list a menu's items: enabled or not, and their shortcuts
//   click LABEL                a real mouse click on the middle of the element's visible part
//   clickat X Y                a real mouse click at a point of the window, in screenshot points
//   focus LABEL                give the element keyboard focus
//   caret LABEL LOC [LEN]      set a text element's selection (UTF-16 offsets into its value)
//   type TEXT                  real key events carrying TEXT
//   key COMBO                  one real key press: cmd+s, return, shift+left, cmd+b, escape…
//   wait SECONDS
//   focused                    which element has keyboard focus
//   value LABEL                the element's value, whole, to the transcript and a file
//   selection LABEL            the element's selected range
//   file NAME                  a copy of the document as it is on disk
//   expect-value LABEL TEXT    the element's value contains TEXT
//   expect-file TEXT           the document on disk contains TEXT
//   expect-no-file TEXT        the document on disk does not contain TEXT
//
// Everything it does is written to transcript.txt in the out-dir, one numbered, timed line per step, and
// each file it writes is named with that step's number. Exit status 1 if an expectation failed,
// 2 for a scenario it could not run.

import AppKit
import ApplicationServices

let arguments = CommandLine.arguments
guard arguments.count == 5, let pid = pid_t(arguments[1]), let windowID = Int(arguments[2]) else {
    FileHandle.standardError.write("usage: agent-drive <pid> <window-id> <out-dir> <document> < scenario\n".data(using: .utf8)!)
    exit(2)
}
let outDirectory = URL(fileURLWithPath: arguments[3], isDirectory: true)
let documentURL = URL(fileURLWithPath: arguments[4])
try? FileManager.default.createDirectory(at: outDirectory, withIntermediateDirectories: true)
let app = AXUIElementCreateApplication(pid)
var transcript = ""
var step = 0
var failures = 0

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

func outFile(_ name: String, _ ext: String) -> URL {
    let safe = name.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "-" }
    return outDirectory.appendingPathComponent(String(format: "%02d-", step) + String(safe) + "." + ext)
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
    // A closed menu's items have no geometry and repeat on every dump; the menu bar's titles are
    // enough to find them with `menu`.
    if text(element, kAXRoleAttribute) == "AXMenuBarItem" { return }
    for child in children(element) { tree(child, depth: depth + 1, into: &output) }
}

func windows() -> [AXUIElement] { (attribute(app, kAXWindowsAttribute) as? [AXUIElement]) ?? [] }

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

/// The document window first, so a toolbar's "Bold" wins over the Format menu's.
func find(_ label: String) -> AXUIElement? {
    for window in windows() { if let found = search(window, label) { return found } }
    return search(app, label)
}

func require(_ label: String) -> AXUIElement? {
    if let element = find(label) { return element }
    log("  no element labelled \"\(label)\"")
    failures += 1
    return nil
}

// MARK: Real input events

func activate() {
    _ = NSRunningApplication(processIdentifier: pid)?.activate()
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

func screenshot(_ name: String) {
    let url = outFile(name, "png")
    let capture = Process()
    capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    capture.arguments = ["-x", "-o", "-l\(windowID)", url.path]
    do {
        try capture.run()
        capture.waitUntilExit()
    } catch {
        log("  screencapture did not start: \(error)")
    }
    let window = windows().first.map(frame) ?? .zero
    log("  \(url.lastPathComponent) (window at \(Int(window.minX)),\(Int(window.minY)) \(Int(window.width))x\(Int(window.height)))")
}

func documentText() -> String {
    (try? String(contentsOf: documentURL, encoding: .utf8)) ?? "<unreadable>"
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

// MARK: The scenario

activate()
while let raw = readLine() {
    let line = raw.trimmingCharacters(in: .whitespaces)
    if line.isEmpty || line.hasPrefix("#") { continue }
    step += 1
    log(line)
    let words = tokens(line)
    let rest = Array(words.dropFirst())
    switch (words[0], rest.count) {
    case ("shot", 1):
        screenshot(rest[0])
    case ("tree", 1):
        var output = ""
        tree(app, depth: 0, into: &output)
        try? output.write(to: outFile(rest[0], "txt"), atomically: true, encoding: .utf8)
        log("  \(output.split(separator: "\n").count) elements")
    case ("press", 1):
        if let element = require(rest[0]) {
            log("  \(describe(element)) → \(AXUIElementPerformAction(element, kAXPressAction as CFString).rawValue)")
        }
    case ("menu-items", 1):
        // Opens one menu bar menu, lists every item with its enabled state and shortcut, and
        // closes it again: what the menu offers right now, as AppKit has just validated it.
        activate()
        let bar: AXUIElement? = attribute(app, kAXMenuBarAttribute).map { $0 as! AXUIElement }
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
            log("  no menu titled \(rest[0])"); failures += 1
        }
    case ("menu", 2...):
        // Opened first, as a person opens it: AppKit validates a menu's items when it opens, so an
        // item read from a closed menu carries whatever enabled state the last validation left
        // (agent-drive run 45943545906 found "WYSIWYG Mode" disabled in Source mode that way).
        activate()
        let bar: AXUIElement? = attribute(app, kAXMenuBarAttribute).map { $0 as! AXUIElement }
        // Then closed again before the item is pressed: an item pressed inside a menu opened this
        // way did nothing, and the menu went on tracking the keyboard, so the next shortcut was
        // lost too (agent-drive run 45948482951). Its validated state outlives the closing.
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
            log("  no menu item at \(rest.joined(separator: " › "))")
            failures += 1
            _ = key("escape")
        }
    case ("click", 1):
        if let element = require(rest[0]) {
            var target = frame(element)
            if let window = windows().first { target = target.intersection(frame(window)) }
            let point = CGPoint(x: target.midX, y: target.midY)
            click(point)
            log("  clicked \(Int(point.x)),\(Int(point.y)) on \(describe(element))")
        }
    case ("clickat", 2):
        if let x = Double(rest[0]), let y = Double(rest[1]), let window = windows().first {
            let origin = frame(window).origin
            click(CGPoint(x: origin.x + x, y: origin.y + y))
            log("  clicked window point \(x),\(y)")
        } else {
            log("  clickat needs a window and two numbers"); failures += 1
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
    case ("type", 1...):
        typeText(rest.joined(separator: " "))
    case ("key", 1):
        if !key(rest[0]) { log("  unknown key \(rest[0])"); failures += 1 }
    case ("wait", 1):
        usleep(useconds_t((Double(rest[0]) ?? 1) * 1_000_000))
    case ("focused", 0):
        if let element = attribute(app, kAXFocusedUIElementAttribute) {
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
    case ("file", 1):
        let url = outFile(rest[0], "md")
        try? documentText().write(to: url, atomically: true, encoding: .utf8)
        log("  → \(url.lastPathComponent)")
    case ("expect-value", 2):
        if let element = require(rest[0]) {
            let found = text(element, kAXValueAttribute).contains(rest[1])
            if !found { failures += 1 }
            log("  \(found ? "PASS" : "FAIL"): value of \"\(rest[0])\" \(found ? "contains" : "lacks") \"\(rest[1])\"")
        }
    case ("expect-file", 1), ("expect-no-file", 1):
        let wanted = words[0] == "expect-file"
        let found = documentText().contains(rest[0])
        if found != wanted { failures += 1 }
        log("  \(found == wanted ? "PASS" : "FAIL"): the document \(found ? "contains" : "lacks") \"\(rest[0])\"")
    default:
        log("  not a step this driver knows (see the top of Scripts/agent-drive.swift)")
        try? transcript.write(to: outDirectory.appendingPathComponent("transcript.txt"), atomically: true, encoding: .utf8)
        exit(2)
    }
}
step += 1
log("done: \(failures == 0 ? "every expectation held" : "\(failures) failed")")
try? transcript.write(to: outDirectory.appendingPathComponent("transcript.txt"), atomically: true, encoding: .utf8)
exit(failures == 0 ? 0 : 1)
