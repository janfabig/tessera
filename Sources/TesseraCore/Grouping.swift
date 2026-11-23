import CoreGraphics

/// Points of slack for frames that Rectangle positions with rounding.
let edgeTolerance: CGFloat = 4

/// Two frames are adjacent when they touch and one's edge lies fully along the other's:
/// two halves, or a half next to a quarter.
func sharesFullEdge(_ a: CGRect, _ b: CGRect) -> Bool {
    let t = edgeTolerance
    func touch(_ aMin: CGFloat, _ aMax: CGFloat, _ bMin: CGFloat, _ bMax: CGFloat) -> Bool {
        abs(aMax - bMin) <= t || abs(bMax - aMin) <= t
    }
    func spanInside(_ aMin: CGFloat, _ aMax: CGFloat, _ bMin: CGFloat, _ bMax: CGFloat) -> Bool {
        (aMin >= bMin - t && aMax <= bMax + t) || (bMin >= aMin - t && bMax <= aMax + t)
    }
    let sideBySide = touch(a.minX, a.maxX, b.minX, b.maxX) && spanInside(a.minY, a.maxY, b.minY, b.maxY)
    let stacked = touch(a.minY, a.maxY, b.minY, b.maxY) && spanInside(a.minX, a.maxX, b.minX, b.maxX)
    return sideBySide || stacked
}

/// Connected components of adjacent windows with two or more members.
/// Each group is sorted, and groups come out ordered by their smallest member.
func groups<ID: Hashable & Comparable>(of frames: [ID: CGRect]) -> [[ID]] {
    var visited = Set<ID>()
    var result: [[ID]] = []
    for start in frames.keys.sorted() where !visited.contains(start) {
        var component: [ID] = []
        var stack = [start]
        visited.insert(start)
        while let current = stack.popLast() {
            component.append(current)
            for other in frames.keys where !visited.contains(other) {
                if sharesFullEdge(frames[current]!, frames[other]!) {
                    visited.insert(other)
                    stack.append(other)
                }
            }
        }
        if component.count >= 2 {
            result.append(component.sorted())
        }
    }
    return result
}

/// Whether the covers leave nothing of the frame showing, apart from slivers of rounding.
func isCovered(_ frame: CGRect, by covers: [CGRect]) -> Bool {
    if frame.width <= edgeTolerance || frame.height <= edgeTolerance { return true }
    guard let cut = covers.map({ $0.intersection(frame) })
        .first(where: { $0.width > edgeTolerance && $0.height > edgeTolerance }) else { return false }
    // Cut one cover out of the frame and check the up to four strips left around it.
    return [
        CGRect(x: frame.minX, y: frame.minY, width: cut.minX - frame.minX, height: frame.height),
        CGRect(x: cut.maxX, y: frame.minY, width: frame.maxX - cut.maxX, height: frame.height),
        CGRect(x: cut.minX, y: frame.minY, width: cut.width, height: cut.minY - frame.minY),
        CGRect(x: cut.minX, y: cut.maxY, width: cut.width, height: frame.maxY - cut.maxY),
    ].allSatisfy { isCovered($0, by: covers) }
}

/// The display that shows most of a frame. Displays touch each other, so without this, tiles at a
/// shared display edge would look adjacent.
func display(of frame: CGRect, in displays: [CGRect]) -> Int? {
    func shown(_ display: CGRect) -> CGFloat {
        let part = display.intersection(frame)
        return part.width * part.height
    }
    return displays.indices.max { shown(displays[$0]) < shown(displays[$1]) }
}

/// The windows to bring forward with the one the user switched to, in the order to raise them.
///
/// `frames` holds every window on screen, with IDs ascending from back to front. `partners` are the
/// windows the picked one was last arranged with that are on screen, `partnerAway` says whether
/// another one is off screen, and `taken` are the windows of other layouts on screen.
func windowsToRaise<ID: Hashable & Comparable>(
    focused: ID, frames: [ID: CGRect], displays: [CGRect], partners: Set<ID>, partnerAway: Bool = false, taken: Set<ID> = []
) -> [ID] {
    guard let picked = frames[focused] else { return [] }
    let local = frames.filter { display(of: $0.value, in: displays) == display(of: picked, in: displays) }

    func overlap(_ a: ID, _ b: ID) -> Bool {
        let shared = local[a]!.intersection(local[b]!)
        return shared.width > edgeTolerance && shared.height > edgeTolerance
    }
    func liesUnder(_ lower: ID, _ upper: ID) -> Bool {
        local[upper]!.insetBy(dx: -edgeTolerance, dy: -edgeTolerance).contains(local[lower]!)
    }
    // A window the picked one lies on belongs to an older layout; it covers tiles, it is not one.
    let tiles = local.filter { $0.key == focused || !liesUnder(focused, $0.key) }
    // Remembered partners come first, as long as they still tile with the picked window: a window
    // moved away by hand has left its layout. Without them, a tile next to it stands in, but never
    // a window that has a layout of its own or is buried under one that has.
    func free(_ id: ID) -> Bool {
        !taken.contains { local[$0] != nil && ($0 == id || ($0 > id && overlap($0, id))) }
    }
    let mine = tiles.filter { $0.key == focused || partners.contains($0.key) }
    // With a partner off screen the rest need not touch each other: the middle one may be the gone one.
    let remembered = partnerAway ? [mine.keys.sorted()].filter { $0.count >= 2 } : groups(of: mine)
    let standIns = groups(of: tiles.filter { $0.key == focused || free($0.key) })
    guard let group = (remembered + standIns).first(where: { $0.contains(focused) }) else { return [] }

    var raised: [ID] = []
    for member in group where member != focused {
        let inFront = local.keys.filter { $0 > member && overlap($0, member) }
        // Raising a window nothing hides only flickers.
        let hidden = inFront.contains { !group.contains($0) }
        // A member that the members in front cover completely, alone or between them, stays where it is.
        let buried = isCovered(local[member]!, by: inFront.filter(group.contains).map { local[$0]! })
        // A member lying on a raised one comes up again, so the raised one does not jump over it.
        let keepsOrder = raised.contains { overlap($0, member) }
        if (hidden && !buried) || keepsOrder {
            raised.append(member)
        }
    }
    return raised
}

/// The same decision for windows listed back to front under any kind of ID.
public func windowsToRaise<ID: Hashable>(
    picked: ID, windows: [(id: ID, frame: CGRect)], displays: [CGRect], partners: Set<ID>, taken: Set<ID>
) -> [ID] {
    guard let focused = windows.firstIndex(where: { $0.id == picked }) else { return [] }
    let frames = Dictionary(uniqueKeysWithValues: windows.enumerated().map { ($0.offset, $0.element.frame) })
    func ranks(_ ids: Set<ID>) -> Set<Int> { Set(windows.indices.filter { ids.contains(windows[$0].id) }) }
    let away = !partners.isSubset(of: windows.map(\.id))
    return windowsToRaise(focused: focused, frames: frames, displays: displays, partners: ranks(partners),
                          partnerAway: away, taken: ranks(taken))
        .map { windows[$0].id }
}

/// The groups of tiles in view among windows listed back to front. In view: the windows in front
/// leave some of it showing, and none of them hides half of it or more.
func layoutsInView<ID: Hashable>(_ windows: [(id: ID, frame: CGRect)], displays: [CGRect]) -> [Set<ID>] {
    let frames = Dictionary(uniqueKeysWithValues: windows.enumerated().map { ($0.offset, $0.element.frame) })
    let inView = frames.filter { rank, frame in
        let covers = frames.filter { $0.key > rank }.map(\.value)
        return !isCovered(frame, by: covers) && !covers.contains { cover in
            let hidden = cover.intersection(frame)
            return hidden.width * hidden.height >= frame.width * frame.height / 2
        }
    }
    return Dictionary(grouping: inView.keys, by: { display(of: frames[$0]!, in: displays) }).values
        .flatMap { onOneDisplay in groups(of: inView.filter { onOneDisplay.contains($0.key) }) }
        .map { group in Set(group.map { windows[$0].id }) }
}

/// Remembers which windows were arranged together. Frames alone cannot tell which windows belong
/// together once two layouts share the same tiles.
///
/// A layout forms when a window is moved or resized next to tiles that are in view. Windows that
/// merely become visible side by side, because one in front was closed, do not form one. Neither
/// does a window that just appeared: a new window, or a tab coming to the front, which is a window
/// of its own that sits exactly where the tab before it sat.
public struct Layouts<ID: Hashable> {
    /// The layouts that hold right now. No window is in two of them.
    public private(set) var standing: [Set<ID>] = []
    /// Every layout that formed, oldest first, to return to when a newer one breaks up.
    private var formed: [Set<ID>] = []
    /// Where each window was at the last look, to tell which ones moved.
    private var frames: [ID: CGRect]?
    /// The displays at the last look.
    private var displays: [CGRect] = []
    /// The windows on screen at the last look.
    private var onScreen: Set<ID> = []

    public init() {}

    /// Looks at the settled screen. `windows` are listed back to front. The first look takes the
    /// layouts in view as they are; later ones act on the windows whose frame changed.
    public mutating func observe(_ windows: [(id: ID, frame: CGRect)], displays: [CGRect]) {
        let inView = layoutsInView(windows, displays: displays)
        let present = Set(windows.map(\.id))
        defer { onScreen = present }
        if frames == nil {
            inView.forEach { form($0) }
        } else if let frames, displays == self.displays {
            // A tab coming to the front sits exactly where the tab it replaces was at the last look. It may
            // be new, or back after its layout re-formed without it; either way it is in no layout yet.
            // Its own last frame may be stale: a background tab moves with its window unseen.
            // That layout keeps a window on screen: a Space switch takes all of them away at once.
            let gone = onScreen.subtracting(present)
            var tabs = Set<ID>()
            for tab in windows where !onScreen.contains(tab.id) && !standing.contains(where: { $0.contains(tab.id) }) {
                let siblings = gone.filter { frames[$0] == tab.frame }
                // A tab that replaced a sibling never counts as moved, even when it joins nothing.
                if !siblings.isEmpty { tabs.insert(tab.id) }
                if let i = standing.firstIndex(where: { !$0.isDisjoint(with: siblings) && !$0.isDisjoint(with: present) }) {
                    standing[i].insert(tab.id)
                    // The remembered copies get it too, so it comes back with its layout after a break.
                    for j in formed.indices where !formed[j].isDisjoint(with: siblings) { formed[j].insert(tab.id) }
                }
            }
            // A display that comes or goes moves every window at once; nobody arranged them.
            for moved in windows where !tabs.contains(moved.id) && frames[moved.id] != moved.frame {
                guard frames[moved.id] != nil else {
                    // A window seen for the first time forms a layout only where it takes no partner away:
                    // started at login, Tessera looks before the apps reopen their windows already tiled.
                    if let layout = inView.first(where: { $0.contains(moved.id) }),
                       standing.allSatisfy({ $0.isDisjoint(with: layout) || $0.isSubset(of: layout) }) {
                        form(layout)
                    }
                    continue
                }
                // A window that moved has left the layouts it formed before; the rest of each is still
                // remembered, unless an older layout without it holds that rest: then that one comes back.
                let without = formed.filter { !$0.contains(moved.id) }
                formed = formed.compactMap { old in
                    let rest = old.subtracting([moved.id])
                    return rest.count >= 2 && (rest == old || !without.contains { rest.isSubset(of: $0) }) ? rest : nil
                }
                if let layout = inView.first(where: { $0.contains(moved.id) }) {
                    form(layout, moved: moved.id)
                } else if let old = standing.firstIndex(where: { $0.contains(moved.id) }) {
                    settle(standing.remove(at: old).subtracting([moved.id]))
                }
            }
        }
        // shortcut: closed windows are never pruned, only the oldest formed layouts; fine at this size.
        // After a display change, windows off screen count as new when they come back: the system moved them.
        frames = (displays == self.displays ? frames ?? [:] : [:]).merging(windows.map { ($0.id, $0.frame) }) { $1 }
        self.displays = displays
        formed.removeFirst(max(0, formed.count - 50))
    }

    private mutating func form(_ layout: Set<ID>, moved: ID? = nil) {
        let broken = standing.filter { !$0.isDisjoint(with: layout) }
        standing.removeAll { !$0.isDisjoint(with: layout) }
        standing.append(layout)
        formed.removeAll { $0.isSubset(of: layout) }  // also the steps on the way to this layout
        formed.append(layout)
        // Each rest settles while the other rests still hold their windows, so no window lands in two layouts.
        let rests = broken.map { $0.subtracting(layout) }
        standing += rests
        for (old, rest) in zip(broken, rests) {
            standing.removeAll { $0 == rest }
            // Windows the moved one left behind stay together; windows a new layout pushed out did not move.
            let keepTogether = moved.map(old.contains) ?? false
            // A broken layout whose windows went back to an earlier one was only a step on the way; forget it.
            if settle(rest, keepTogether: keepTogether) { formed.removeAll { $0 == old } }
        }
    }

    /// Windows left behind when their layout broke up return to the newest layout that held all of
    /// them and is free again. That skips layouts that formed only for a moment while another one
    /// was being built. With no such layout they stay together, if `keepTogether`.
    /// Returns whether they went back to an earlier layout.
    @discardableResult
    private mutating func settle(_ rest: Set<ID>, keepTogether: Bool = true) -> Bool {
        guard !rest.isEmpty else { return false }
        let earlier = formed.last { old in rest.isSubset(of: old) && standing.allSatisfy { $0.isDisjoint(with: old) } }
        if let layout = earlier ?? (keepTogether && rest.count >= 2 ? rest : nil) {
            standing.append(layout)
        }
        return earlier != nil
    }

    /// The windows this one currently belongs with.
    public func partners(of window: ID) -> Set<ID> {
        standing.first { $0.contains(window) }?.subtracting([window]) ?? []
    }

    /// Every window whose layout still has two or more windows on screen. A window whose partners
    /// are all closed, minimized or background tabs is free for a neighbour again.
    public func grouped(among present: Set<ID>) -> Set<ID> {
        Set(standing.filter { $0.intersection(present).count >= 2 }.joined())
    }
}
