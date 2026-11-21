import AppKit
import TesseraCore

// Private but long-stable (window switchers rely on it): the window-server number of an Accessibility window.
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

typealias Window = (element: AXUIElement, frame: CGRect, number: CGWindowID)

var observers: [pid_t: AXObserver] = [:]
var lastFocused: AXUIElement?
var layouts = Layouts<CGWindowID>()
var observation: Timer?
var loggedLayouts: [Set<CGWindowID>] = []

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value
}

func frameOf(_ window: AXUIElement) -> CGRect? {
    guard let position = attribute(window, kAXPositionAttribute),
          let size = attribute(window, kAXSizeAttribute) else { return nil }
    var frame = CGRect.zero
    AXValueGetValue(position as! AXValue, .cgPoint, &frame.origin)
    AXValueGetValue(size as! AXValue, .cgSize, &frame.size)
    return frame
}

func focusedWindow(of pid: pid_t) -> AXUIElement? {
    attribute(AXUIElementCreateApplication(pid), kAXFocusedWindowAttribute).map { $0 as! AXUIElement }
}

func owner(of element: AXUIElement) -> pid_t {
    var pid: pid_t = 0
    AXUIElementGetPid(element, &pid)
    return pid
}

func runningApp(_ note: Notification) -> NSRunningApplication? {
    note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
}

func log(_ message: String) {
    FileHandle.standardError.write(Data("\(Date().formatted(date: .omitted, time: .standard)) \(message)\n".utf8))
}

func describe(_ window: Window) -> String {
    let app = NSRunningApplication(processIdentifier: owner(of: window.element))?.localizedName ?? "?"
    let f = window.frame
    return "#\(window.number) \(app) (\(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))x\(Int(f.height)))"
}

func displayBounds() -> [CGRect] {
    var ids = [CGDirectDisplayID](repeating: 0, count: 16)
    var count: UInt32 = 0
    CGGetActiveDisplayList(16, &ids, &count)
    return ids.prefix(Int(count)).map { CGDisplayBounds($0) }
}

func windowsOf(pid: pid_t) -> [(element: AXUIElement, frame: CGRect)] {
    guard let windows = attribute(AXUIElementCreateApplication(pid), kAXWindowsAttribute) as? [AXUIElement] else { return [] }
    return windows.compactMap { window in
        guard attribute(window, kAXRoleAttribute) as? String == kAXWindowRole as String,
              attribute(window, kAXMinimizedAttribute) as? Bool != true,
              let frame = frameOf(window) else { return nil }
        return (window, frame)
    }
}

/// On-screen windows of all visible regular apps, backmost first. Windows the window server does not
/// list as on screen, such as those on another Space, are left out so they are never raised.
func allWindows() -> [Window] {
    let onScreen = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        as? [[String: Any]] ?? []
    // Normal-level windows only: a raise cannot lift a tile above an always-on-top window.
    let frontToBack = onScreen.filter { $0[kCGWindowLayer as String] as? Int == 0 }
        .compactMap { $0[kCGWindowNumber as String] as? CGWindowID }
    return NSWorkspace.shared.runningApplications
        .filter { $0.activationPolicy == .regular && !$0.isHidden }
        .flatMap { windowsOf(pid: $0.processIdentifier) }
        .compactMap { window -> (element: AXUIElement, frame: CGRect, number: CGWindowID, depth: Int)? in
            var number: CGWindowID = 0
            _ = _AXUIElementGetWindow(window.element, &number)
            return frontToBack.firstIndex(of: number).map { (window.element, window.frame, number, $0) }
        }
        .sorted { $0.depth > $1.depth }
        .map { ($0.element, $0.frame, $0.number) }
}

/// Looks at which windows were moved once the screen has settled: snapping animates, and the window
/// server reorders a moment after a switch.
func observeSoon() {
    observation?.invalidate()
    observation = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { _ in
        layouts.observe(allWindows().map { ($0.number, $0.frame) }, displays: displayBounds())
        if layouts.standing != loggedLayouts {
            loggedLayouts = layouts.standing
            log("arranged together: \(layouts.standing.map { $0.sorted() })")
        }
    }
}

/// Watches one app for switches between its own windows and for windows being moved or resized.
func attach(_ pid: pid_t) {
    guard observers[pid] == nil else { return }
    var observer: AXObserver?
    let callback: AXObserverCallback = { _, element, notification, _ in
        guard notification as String == kAXFocusedWindowChangedNotification else {
            observeSoon()  // a window was moved or resized, for example snapped into a layout
            return
        }
        let pid = owner(of: element)
        // Raising a background window makes its app report a focus change; following it would loop.
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
        focusMoved(in: pid)
    }
    let app = AXUIElementCreateApplication(pid)
    guard AXObserverCreate(pid, callback, &observer) == .success, let observer,
          AXObserverAddNotification(observer, app, kAXFocusedWindowChangedNotification as CFString, nil) == .success
    else { return }  // retried on the app's next activation
    for change in [kAXWindowMovedNotification, kAXWindowResizedNotification] {
        AXObserverAddNotification(observer, app, change as CFString, nil)
    }
    CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    observers[pid] = observer
}

/// Raises the hidden members of the group of an app's focused window. Runs when the app is activated
/// or reports a focus change between its own windows. The group is the layout the window was last
/// arranged in, checked against the current frames.
func focusMoved(in pid: pid_t) {
    // Ask the app rather than trust the notification: after our own raises its window is stale.
    guard let focused = focusedWindow(of: pid) else { return }
    // Our raises can echo back as focus reports for the window just handled; following them would loop.
    if let lastFocused, CFEqual(lastFocused, focused) { return }
    lastFocused = focused

    // A snap just before this switch is looked at now, before the switch covers it.
    if observation?.isValid == true { observation?.fire() }
    let windows = allWindows()
    guard let picked = windows.first(where: { CFEqual($0.element, focused) }) else { return }
    let partners = layouts.partners(of: picked.number)
    let raised = windowsToRaise(
        picked: picked.number, windows: windows.map { ($0.number, $0.frame) }, displays: displayBounds(), partners: partners, taken: layouts.grouped(among: Set(windows.map(\.number)))
    ).compactMap { number in windows.first { $0.number == number } }
    log("picked \(describe(picked)), remembered partners \(partners.sorted()), raising \(raised.map(describe)), back to front: \(windows.map(describe))")
    observeSoon()  // a new window has no move to announce it

    let others = raised.map(\.element)
    for other in others {
        AXUIElementPerformAction(other, kAXRaiseAction as CFString)
    }
    // Put the picked window back on top, unless the user has moved on within this app: an oversized
    // member can overlap it, and a member of the same app may take focus. This runs on every switch,
    // so a switch handled late, after the user has already switched on, is covered again by the next.
    guard let now = focusedWindow(of: pid),
          CFEqual(now, focused) || others.contains(where: { CFEqual($0, now) }) else { return }
    AXUIElementPerformAction(focused, kAXRaiseAction as CFString)
    AXUIElementSetAttributeValue(focused, kAXMainAttribute as CFString, kCFBooleanTrue)
}

let trusted = AXIsProcessTrustedWithOptions(
    [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
)
guard trusted else {
    print("Grant Accessibility access to the app you started Tessera from (your terminal) in System Settings, then start it again.")
    exit(1)
}

// A hung app must not stall every switch: the default wait per Accessibility call is several seconds.
AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 1.0)

for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
    attach(app.processIdentifier)
}
observeSoon()
let center = NSWorkspace.shared.notificationCenter
// Switching between apps (AltTab, Dock, Cmd-Tab) reports only an activation, never a focus change.
center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
    lastFocused = nil  // an activation is never an echo of our own raises
    guard let app = runningApp(note), app.activationPolicy == .regular else { return }
    attach(app.processIdentifier)  // covers apps launched after Tessera
    focusMoved(in: app.processIdentifier)
}
center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { note in
    guard let app = runningApp(note), let observer = observers.removeValue(forKey: app.processIdentifier) else { return }
    CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
}
RunLoop.main.run()
