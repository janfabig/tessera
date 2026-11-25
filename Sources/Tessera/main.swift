import AppKit
import ServiceManagement
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
var paused = false

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
    guard !paused else { return }  // windows moved meanwhile are still remembered: observing goes on
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

func start() {
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
}

/// Three by three mosaic stones with one lit, as in the app icon. A template image, so macOS tints it.
func mosaicGlyph() -> NSImage {
    let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
        let stone: CGFloat = 4.4, step: CGFloat = 6, inset: CGFloat = 0.8
        for row in 0..<3 {
            for column in 0..<3 {
                let lit = row == litStone.row && column == litStone.column
                NSColor.black.withAlphaComponent(lit ? 1 : 0.4).setFill()
                let frame = NSRect(x: inset + CGFloat(column) * step, y: inset + CGFloat(row) * step, width: stone, height: stone)
                NSBezierPath(roundedRect: frame, xRadius: 1.1, yRadius: 1.1).fill()
            }
        }
        return true
    }
    image.isTemplate = true
    return image
}
let litStone = (row: 0, column: 2)

/// The menu bar icon: pause grouping, start at login, hide the icon, quit.
final class Menu: NSObject, NSMenuDelegate, NSApplicationDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    let pause = NSMenuItem(title: "Pause Grouping", action: #selector(togglePause), keyEquivalent: "")
    let login = NSMenuItem(title: "Start at Login", action: #selector(toggleLogin), keyEquivalent: "")

    override init() {
        super.init()
        item.button?.image = mosaicGlyph()
        item.button?.toolTip = "Tessera"
        let menu = NSMenu()
        menu.delegate = self
        for entry in [pause, login] {
            entry.target = self
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        let hide = NSMenuItem(title: "Hide Menu Bar Icon", action: #selector(hideIcon), keyEquivalent: "")
        hide.target = self
        menu.addItem(hide)
        item.isVisible = !UserDefaults.standard.bool(forKey: hiddenKey)
        let quit = NSMenuItem(title: "Quit Tessera", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
        item.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        pause.state = paused ? .on : .off
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc func togglePause() {
        paused.toggle()
        item.button?.appearsDisabled = paused
    }

    @objc func hideIcon() {
        item.isVisible = false
        UserDefaults.standard.set(true, forKey: hiddenKey)
    }

    /// Opening Tessera.app while it runs brings the hidden icon back: the only way left to reach the menu.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        item.isVisible = true
        UserDefaults.standard.set(false, forKey: hiddenKey)
        return false
    }

    @objc func toggleLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            // macOS may refuse or want approval first; its Login Items page lets the user decide.
            SMAppService.openSystemSettingsLoginItems()
        }
    }
}

// Start at login, once: after that the choice in the menu or in System Settings stands. Only an
// installed copy is added, never one opened from Downloads or the build folder.
let loginKey = "addedToLoginItems"
if Bundle.main.bundlePath.contains("/Applications/"),
   !UserDefaults.standard.bool(forKey: loginKey), (try? SMAppService.mainApp.register()) != nil {
    UserDefaults.standard.set(true, forKey: loginKey)
}

let app = NSApplication.shared
let hiddenKey = "menuBarIconHidden"
let menu = Menu()
app.delegate = menu

// macOS shows its own Accessibility prompt; Tessera starts as soon as access is granted, no restart needed.
if AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary) {
    start()
} else {
    Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
        guard AXIsProcessTrusted() else { return }
        timer.invalidate()
        start()
    }
}
app.run()
