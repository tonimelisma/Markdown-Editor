// Research probe (not a test, not merged): what can an agent on a GitHub Mac runner see and do
// in the app? `ax trusted | dump <pid> | press <pid> <title> | type <text> | key <letter> [cmd] |
// activate <pid>`.
import AppKit
import ApplicationServices

func attr(_ e: AXUIElement, _ name: String) -> AnyObject? {
    var v: AnyObject?
    return AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success ? v : nil
}
func str(_ e: AXUIElement, _ name: String) -> String {
    guard let v = attr(e, name) else { return "" }
    if let s = v as? String { return s }
    if let n = v as? NSNumber { return n.stringValue }
    return ""
}
func frame(_ e: AXUIElement) -> String {
    var p = CGPoint.zero, s = CGSize.zero
    if let pv = attr(e, kAXPositionAttribute) { AXValueGetValue(pv as! AXValue, .cgPoint, &p) }
    if let sv = attr(e, kAXSizeAttribute) { AXValueGetValue(sv as! AXValue, .cgSize, &s) }
    return "\(Int(p.x)),\(Int(p.y)) \(Int(s.width))x\(Int(s.height))"
}
func children(_ e: AXUIElement) -> [AXUIElement] { (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] }

func dump(_ e: AXUIElement, _ depth: Int) {
    if depth > 14 { return }
    var line = String(repeating: "  ", count: depth) + str(e, kAXRoleAttribute)
    for (k, label) in [(kAXTitleAttribute, "title"), (kAXDescriptionAttribute, "desc"),
                       (kAXIdentifierAttribute, "id"), (kAXHelpAttribute, "help")] {
        let v = str(e, k)
        if !v.isEmpty { line += " \(label)=\"\(v.prefix(60))\"" }
    }
    let value = str(e, kAXValueAttribute)
    if !value.isEmpty { line += " value=\"\(value.prefix(160).replacingOccurrences(of: "\n", with: "⏎"))\"" }
    line += " [\(frame(e))]"
    print(line)
    for c in children(e) { dump(c, depth + 1) }
}
func find(_ e: AXUIElement, _ match: String, _ depth: Int = 0) -> AXUIElement? {
    if depth > 16 { return nil }
    let role = str(e, kAXRoleAttribute)
    if ["AXButton", "AXRadioButton", "AXCheckBox", "AXMenuButton", "AXPopUpButton"].contains(role),
       str(e, kAXTitleAttribute) == match || str(e, kAXDescriptionAttribute) == match {
        return e
    }
    for c in children(e) { if let f = find(c, match, depth + 1) { return f } }
    return nil
}
func post(_ event: CGEvent?) { event?.post(tap: .cghidEventTap) }

let args = CommandLine.arguments
switch args.count > 1 ? args[1] : "" {
case "trusted":
    print("AXIsProcessTrusted=\(AXIsProcessTrusted())")
case "dump":
    let app = AXUIElementCreateApplication(pid_t(args[2])!)
    dump(app, 0)
case "press":
    let app = AXUIElementCreateApplication(pid_t(args[2])!)
    guard let target = find(app, args[3]) else { print("press: no control titled \(args[3])"); exit(4) }
    print("press \(args[3]): \(AXUIElementPerformAction(target, kAXPressAction as CFString).rawValue)")
case "type":
    let src = CGEventSource(stateID: .hidSystemState)
    for unit in args[2].utf16 {
        var ch = unit
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: down)
            e?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &ch)
            post(e)
        }
        usleep(20_000)
    }
    print("type: posted \(args[2].utf16.count) characters")
case "key":
    let codes: [String: CGKeyCode] = ["a": 0, "s": 1, "b": 11, "i": 34, "z": 6]
    let code = codes[args[2]]!
    let src = CGEventSource(stateID: .hidSystemState)
    for down in [true, false] {
        let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down)
        if args.count > 3 { e?.flags = .maskCommand }
        post(e)
    }
    print("key: \(args[2]) \(args.count > 3 ? "with command" : "")")
case "activate":
    let ok = NSRunningApplication(processIdentifier: pid_t(args[2])!)?.activate() ?? false
    print("activate: \(ok)")
default:
    print("usage: ax trusted|dump|press|type|key|activate"); exit(2)
}
