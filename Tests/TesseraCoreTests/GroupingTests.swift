import CoreGraphics
import Testing
@testable import TesseraCore

@Suite("Grouping snapped windows")
struct GroupingTests {
    @Test("two side-by-side halves form one group")
    func sideBySideHalves() {
        let frames: [String: CGRect] = [
            "left": CGRect(x: 0, y: 0, width: 960, height: 1080),
            "right": CGRect(x: 960, y: 0, width: 960, height: 1080),
        ]
        #expect(groups(of: frames) == [["left", "right"]])
    }

    @Test("stacked halves form one group")
    func stackedHalves() {
        let frames: [String: CGRect] = [
            "top": CGRect(x: 0, y: 0, width: 1920, height: 540),
            "bottom": CGRect(x: 0, y: 540, width: 1920, height: 540),
        ]
        #expect(groups(of: frames) == [["bottom", "top"]])
    }

    @Test("a lone window forms no group")
    func loneWindow() {
        let frames: [String: CGRect] = [
            "solo": CGRect(x: 0, y: 0, width: 1920, height: 1080),
        ]
        #expect(groups(of: frames) == [])
    }

    @Test("windows with a gap between them are not grouped")
    func gapBreaksGroup() {
        let frames: [String: CGRect] = [
            "left": CGRect(x: 0, y: 0, width: 900, height: 1080),
            "right": CGRect(x: 960, y: 0, width: 960, height: 1080),
        ]
        #expect(groups(of: frames) == [])
    }

    @Test("small rounding differences still count as adjacent")
    func toleratesRounding() {
        let frames: [String: CGRect] = [
            "left": CGRect(x: 0, y: 0, width: 961, height: 1080),
            "right": CGRect(x: 960, y: 1, width: 960, height: 1079),
        ]
        #expect(groups(of: frames) == [["left", "right"]])
    }

    @Test("four quadrants form one group")
    func quadrants() {
        let frames: [String: CGRect] = [
            "tl": CGRect(x: 0, y: 0, width: 960, height: 540),
            "tr": CGRect(x: 960, y: 0, width: 960, height: 540),
            "bl": CGRect(x: 0, y: 540, width: 960, height: 540),
            "br": CGRect(x: 960, y: 540, width: 960, height: 540),
        ]
        #expect(groups(of: frames) == [["bl", "br", "tl", "tr"]])
    }

    // Real Rectangle layout with a 25 pt menu bar: the half is as tall as both quarters together.
    @Test("a half next to two quarters forms one group")
    func halfAndTwoQuarters() {
        let frames: [String: CGRect] = [
            "half": CGRect(x: 0, y: 25, width: 960, height: 1055),
            "topQuarter": CGRect(x: 960, y: 25, width: 960, height: 527),
            "bottomQuarter": CGRect(x: 960, y: 552, width: 960, height: 528),
        ]
        #expect(groups(of: frames) == [["bottomQuarter", "half", "topQuarter"]])
    }

    @Test("windows that touch but only partly overlap along the edge are not grouped")
    func partialOverlapIsNotAGroup() {
        let frames: [String: CGRect] = [
            "left": CGRect(x: 0, y: 0, width: 960, height: 1080),
            "shifted": CGRect(x: 960, y: 500, width: 960, height: 1080),
        ]
        #expect(groups(of: frames) == [])
    }

    @Test("windows that touch only at a corner are not grouped")
    func cornerTouchIsNotAGroup() {
        let frames: [String: CGRect] = [
            "topLeft": CGRect(x: 0, y: 0, width: 960, height: 540),
            "bottomRight": CGRect(x: 960, y: 540, width: 960, height: 540),
        ]
        #expect(groups(of: frames) == [])
    }
}

/// The raise rule on its own: every window counts as a possible partner, so the tiles alone decide.
func raised<ID: Hashable & Comparable>(focused: ID, frames: [ID: CGRect], displays: [CGRect]) -> [ID] {
    windowsToRaise(focused: focused, frames: frames, displays: displays, partners: Set(frames.keys))
}

// Window IDs ascend from back to front, the way the app numbers them.
@Suite("Deciding which windows to raise")
struct RaiseDecisionTests {
    let oneDisplay = [CGRect(x: 0, y: 0, width: 1920, height: 1080)]
    let leftHalf = CGRect(x: 0, y: 0, width: 960, height: 1080)
    let rightHalf = CGRect(x: 960, y: 0, width: 960, height: 1080)
    let maximized = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    @Test("a member hidden behind another window is raised")
    func coveredMemberIsRaised() {
        let frames = [0: rightHalf, 1: maximized, 2: leftHalf]
        #expect(raised(focused: 2, frames: frames, displays: oneDisplay) == [0])
    }

    // Raising windows that are already visible only makes the screen flicker.
    @Test("a group that is already fully visible raises nothing")
    func visibleGroupRaisesNothing() {
        let frames = [0: maximized, 1: rightHalf, 2: leftHalf]
        #expect(raised(focused: 2, frames: frames, displays: oneDisplay) == [])
    }

    @Test("a window outside any group raises nothing")
    func ungroupedWindow() {
        let frames = [0: leftHalf, 1: rightHalf, 2: CGRect(x: 300, y: 200, width: 500, height: 400)]
        #expect(raised(focused: 2, frames: frames, displays: oneDisplay) == [])
    }

    @Test("every hidden member of a half plus two quarters is raised")
    func halfAndTwoQuarters() {
        let frames = [
            0: CGRect(x: 960, y: 0, width: 960, height: 540),
            1: CGRect(x: 960, y: 540, width: 960, height: 540),
            2: maximized,
            3: leftHalf,
        ]
        #expect(raised(focused: 3, frames: frames, displays: oneDisplay) == [0, 1])
    }

    @Test("of two windows stacked on one tile, only the upper one is raised")
    func upperOfStackIsRaised() {
        let frames = [0: rightHalf, 1: rightHalf, 2: maximized, 3: leftHalf]
        #expect(raised(focused: 3, frames: frames, displays: oneDisplay) == [1])
    }

    @Test("the lower window of a stack stays below the visible upper one")
    func lowerOfStackStaysPut() {
        let frames = [0: rightHalf, 1: maximized, 2: rightHalf, 3: leftHalf]
        #expect(raised(focused: 3, frames: frames, displays: oneDisplay) == [])
    }

    // An app that cannot shrink to its quarter overlaps the quarter next to it. Both still belong.
    @Test("members that partly overlap each other are both raised")
    func oversizeMembersAreBothRaised() {
        let frames = [
            0: CGRect(x: 960, y: 25, width: 960, height: 600),  // top quarter, 73 pt too tall
            1: CGRect(x: 960, y: 552, width: 960, height: 528),
            2: CGRect(x: 0, y: 25, width: 1920, height: 1055),
            3: CGRect(x: 0, y: 25, width: 960, height: 1055),
        ]
        #expect(raised(focused: 3, frames: frames, displays: oneDisplay) == [0, 1])
        // Without the cover everything is visible: members overlapping each other hide nothing.
        #expect(raised(focused: 3, frames: frames.filter { $0.key != 2 }, displays: oneDisplay) == [])
    }

    // A raised member must not jump over a member that was lying on it.
    @Test("a visible member lying on a raised one is raised again to stay on top")
    func raisedMemberKeepsItsPlaceInTheOrder() {
        let quarter = CGRect(x: 960, y: 540, width: 960, height: 540)
        let frames = [0: rightHalf, 1: maximized, 2: quarter, 3: leftHalf]
        #expect(raised(focused: 3, frames: frames, displays: oneDisplay) == [0, 2])
    }

    // The right half lies under the picked quarter, so it is another layout's window, not a member.
    @Test("a window lying under the picked one is a cover, not a member")
    func windowUnderThePickedOneIsACover() {
        let frames = [
            0: CGRect(x: 960, y: 552, width: 960, height: 528),  // bottom quarter, hidden by the half
            1: CGRect(x: 0, y: 25, width: 960, height: 1055),
            2: CGRect(x: 960, y: 25, width: 960, height: 1055),  // right half of an older layout
            3: CGRect(x: 960, y: 25, width: 960, height: 527),   // top quarter, picked
        ]
        #expect(raised(focused: 3, frames: frames, displays: oneDisplay) == [0])
    }

    @Test("a visible member partly lying on a raised one is raised again")
    func partlyOverlappingMemberKeepsItsPlace() {
        let frames = [
            0: CGRect(x: 960, y: 25, width: 960, height: 600),   // top quarter, too tall, hidden
            1: CGRect(x: 1200, y: 100, width: 500, height: 300), // floating window on the top quarter
            2: CGRect(x: 960, y: 552, width: 960, height: 528),  // bottom quarter, visible
            3: CGRect(x: 0, y: 25, width: 960, height: 1055),
        ]
        #expect(raised(focused: 3, frames: frames, displays: oneDisplay) == [0, 2])
    }

    @Test("a member lying on an earlier raised one is raised again, not only on the last")
    func orderIsKeptAcrossSeveralRaisedMembers() {
        let frames = [
            0: CGRect(x: 0, y: 0, width: 960, height: 600),      // top-left quarter, too tall, hidden
            1: CGRect(x: 100, y: 100, width: 300, height: 200),  // floating window on it
            2: CGRect(x: 960, y: 0, width: 960, height: 540),    // top-right quarter, hidden
            3: CGRect(x: 1200, y: 100, width: 300, height: 200), // floating window on it
            4: CGRect(x: 0, y: 540, width: 960, height: 540),    // bottom-left quarter, lies on window 0
            5: CGRect(x: 960, y: 540, width: 960, height: 540),  // bottom-right quarter, picked
        ]
        #expect(raised(focused: 5, frames: frames, displays: oneDisplay) == [0, 2, 4])
    }

    // Regression: the old half was raised over both visible quarters and they were raised again
    // on top of it, on every switch. Nothing changed on screen except a flicker.
    @Test("an older tile that newer tiles cover between them stays where it is")
    func tileCoveredByTwoMembersStaysPut() {
        let frames = [
            0: rightHalf,
            1: maximized,
            2: CGRect(x: 960, y: 0, width: 960, height: 540),
            3: CGRect(x: 960, y: 540, width: 960, height: 540),
            4: leftHalf,
        ]
        #expect(raised(focused: 4, frames: frames, displays: oneDisplay) == [])
    }

    @Test("a stacked window a few points larger than the one above stays put")
    func slightlyLargerStackedWindowStaysPut() {
        let frames = [0: CGRect(x: 958, y: 0, width: 962, height: 1080), 1: maximized, 2: rightHalf, 3: leftHalf]
        #expect(raised(focused: 3, frames: frames, displays: oneDisplay) == [])
    }

    // A cover counts from more than the rounding slack; tiles that overlap by rounding do not.
    @Test("a small cover hides a member, a rounding overlap between members does not")
    func overlapThreshold() {
        let frames = [
            0: CGRect(x: 960, y: 536, width: 960, height: 544),  // bottom quarter, 4 pt too tall
            1: CGRect(x: 500, y: 600, width: 520, height: 400),  // floating, 60 pt into the quarter
            2: CGRect(x: 960, y: 0, width: 960, height: 540),    // top quarter, visible
            3: leftHalf,
        ]
        #expect(raised(focused: 3, frames: frames, displays: oneDisplay) == [0])
    }

    // The picked quarter is 2 pt wider than its tile; the old half under it is still a cover.
    @Test("a window the picked one overhangs by rounding is still a cover")
    func roundingOverhangIsStillACover() {
        let frames = [
            0: CGRect(x: 960, y: 552, width: 960, height: 528),
            1: CGRect(x: 0, y: 25, width: 960, height: 1055),
            2: CGRect(x: 960, y: 25, width: 960, height: 1055),
            3: CGRect(x: 958, y: 25, width: 962, height: 527),
        ]
        #expect(raised(focused: 3, frames: frames, displays: oneDisplay) == [0])
    }

    // Tiles may overlap by rounding; that must not count as one covering the other.
    @Test("a partner that overlaps the picked window by rounding only is still raised")
    func roundingOverlapIsNotCovering() {
        let frames = [0: CGRect(x: 956, y: 0, width: 964, height: 1080), 1: maximized, 2: leftHalf]
        #expect(raised(focused: 2, frames: frames, displays: oneDisplay) == [0])
    }

    @Test("the picked window is never returned, even when something covers it")
    func pickedWindowIsNotRaised() {
        let frames = [0: leftHalf, 1: CGRect(x: 100, y: 300, width: 400, height: 300), 2: rightHalf]
        #expect(raised(focused: 0, frames: frames, displays: oneDisplay) == [])
    }

    @Test("a window belongs to the display that shows most of it")
    func windowBelongsToTheDisplayShowingMostOfIt() {
        let displays = [CGRect(x: 0, y: 0, width: 1920, height: 1080), CGRect(x: 1920, y: 0, width: 1920, height: 1080)]
        let mostlyOnTheOther = CGRect(x: 1500, y: 200, width: 1200, height: 600)
        #expect(raised(focused: 2, frames: [0: rightHalf, 1: mostlyOnTheOther, 2: leftHalf], displays: displays) == [])
        // Dragged mostly below the screen: its centre is on no display, but it still hides the partner.
        let hangingOff = CGRect(x: 1000, y: 700, width: 900, height: 900)
        #expect(raised(focused: 2, frames: [0: rightHalf, 1: hangingOff, 2: leftHalf], displays: displays) == [0])
    }

    // Regression, taken from the live layout: a laptop display left of an external one. The window
    // maximized on the laptop touches every window at the external display's left edge, which made
    // one group of everything, including the maximized window that covered the tiles.
    @Test("windows on another display are not part of the group")
    func otherDisplayIsNotGrouped() {
        let displays = [CGRect(x: 0, y: 0, width: 1470, height: 956), CGRect(x: 1470, y: 0, width: 1920, height: 1080)]
        let frames = [
            0: CGRect(x: 2750, y: 30, width: 640, height: 1050),  // right third
            1: CGRect(x: 2110, y: 30, width: 640, height: 1050),  // middle third
            2: CGRect(x: 0, y: 33, width: 1470, height: 923),     // maximized on the laptop display
            3: CGRect(x: 1470, y: 30, width: 1920, height: 1050), // maximized on the external display
            4: CGRect(x: 1470, y: 30, width: 640, height: 1050),  // left third, picked
        ]
        #expect(raised(focused: 4, frames: frames, displays: displays) == [0, 1])
    }
}

/// A model of the screen that does what the app does on each event. Windows are kept back to front.
struct Desk {
    var displays: [CGRect]
    var stack: [(id: String, frame: CGRect)] = []
    var hidden: [String: CGRect] = [:]
    var layouts = Layouts<String>()

    init(displays: [CGRect]) {
        self.displays = displays
        look()  // the app's first look, here at an empty screen
    }

    mutating func look() {
        layouts.observe(stack, displays: displays)
    }

    private mutating func toFront(_ id: String, at frame: CGRect? = nil) {
        let current = stack.first { $0.id == id }?.frame
        stack.removeAll { $0.id == id }
        stack.append((id, frame ?? current!))
    }

    /// A window opens or is moved or resized; the app looks at the settled screen.
    mutating func put(_ id: String, at frame: CGRect) {
        toFront(id, at: frame)
        look()
    }

    /// A window opens somewhere and is then snapped to a tile, the way a person arranges it.
    mutating func arrange(_ id: String, at frame: CGRect) {
        put(id, at: CGRect(x: 1600, y: 200, width: 900, height: 600))
        put(id, at: frame)
    }

    /// The user switches to a window; the app raises its hidden partners.
    mutating func pick(_ id: String) {
        toFront(id)
        let raised = windowsToRaise(picked: id, windows: stack, displays: displays,
                                    partners: layouts.partners(of: id), taken: layouts.grouped(among: Set(stack.map(\.id))))
        raised.forEach { toFront($0) }
        toFront(id)
        look()
    }

    /// Closed, minimized, or a tab that went to the background: the window is off screen.
    mutating func hide(_ id: String) {
        hidden[id] = stack.first { $0.id == id }?.frame
        stack.removeAll { $0.id == id }
    }

    mutating func show(_ id: String) {
        put(id, at: hidden.removeValue(forKey: id)!)
    }

    func top(at frame: CGRect) -> String? {
        stack.last { $0.frame == frame }?.id
    }

    func isAbove(_ upper: String, _ lower: String) -> Bool {
        stack.firstIndex { $0.id == upper }! > stack.firstIndex { $0.id == lower }!
    }
}

@Suite("Remembering which windows were arranged together")
struct LayoutMemoryTests {
    let displays = [CGRect(x: 0, y: 0, width: 1470, height: 956), CGRect(x: 1470, y: 0, width: 1920, height: 1080)]
    let left = CGRect(x: 1470, y: 30, width: 960, height: 1050)
    let right = CGRect(x: 2430, y: 30, width: 960, height: 1050)
    let maximized = CGRect(x: 1470, y: 30, width: 1920, height: 1050)
    let floating = CGRect(x: 2000, y: 300, width: 700, height: 500)
    let topRight = CGRect(x: 2430, y: 30, width: 960, height: 525)
    let bottomRight = CGRect(x: 2430, y: 555, width: 960, height: 525)
    let thirds = [1470, 2110, 2750].map { CGRect(x: $0, y: 30, width: 640, height: 1050) }

    func desk(_ arranged: [(String, CGRect)]) -> Desk {
        var desk = Desk(displays: displays)
        arranged.forEach { desk.arrange($0.0, at: $0.1) }
        return desk
    }

    // Regression, taken from the live log: a Ghostty pair, then Dispatch snapped onto the right
    // tile and Notes onto the left one. Picking a window showed whichever window was on top of
    // the other tile instead of its real partner.
    @Test("two pairs built on the same tiles keep their own partners")
    func twoPairsOnTheSameTiles() {
        var desk = desk([("ghosttyR", right), ("ghosttyL", left), ("dispatch", right), ("notes", left)])
        #expect(desk.layouts.partners(of: "ghosttyL") == ["ghosttyR"])
        #expect(desk.layouts.partners(of: "ghosttyR") == ["ghosttyL"])
        #expect(desk.layouts.partners(of: "dispatch") == ["notes"])
        #expect(desk.layouts.partners(of: "notes") == ["dispatch"])

        desk.pick("ghosttyL")
        #expect(desk.top(at: right) == "ghosttyR")
        desk.put("word", at: maximized)
        desk.pick("dispatch")
        #expect(desk.top(at: left) == "notes")
        #expect(desk.isAbove("notes", "word"))
    }

    @Test("a pair that was never taken apart survives pairs built and rebuilt beside it")
    func untouchedPairSurvives() {
        let desk = desk([("a", left), ("b", right), ("c", right), ("d", left), ("e", right)])
        #expect(desk.layouts.partners(of: "a") == ["b"])
        #expect(desk.layouts.partners(of: "d") == ["e"])
        #expect(desk.layouts.partners(of: "c") == [])
    }

    @Test("two layouts of thirds built on the same tiles keep their own partners")
    func twoThirdLayoutsOnTheSameTiles() {
        let desk = desk(Array(zip(["a", "b", "c", "x", "y", "z"], thirds + thirds)))
        #expect(desk.layouts.partners(of: "b") == ["a", "c"])
        #expect(desk.layouts.partners(of: "y") == ["x", "z"])
    }

    @Test("a half and two quarters come back together after a pair was built on top")
    func halfAndQuartersUnderAPair() {
        let desk = desk([("h", left), ("q1", topRight), ("q2", bottomRight), ("l", left), ("r", right)])
        #expect(desk.layouts.partners(of: "q1") == ["h", "q2"])
        #expect(desk.layouts.partners(of: "l") == ["r"])
    }

    // Regression: each quarter hides exactly half of the old right half, and together all of it.
    @Test("a tile that two tiles in front cover between them is not in view")
    func tileCoveredByTwoQuartersIsNotInView() {
        let desk = desk([("l", left), ("r", right), ("h", left), ("q1", topRight), ("q2", bottomRight)])
        #expect(desk.layouts.partners(of: "l") == ["r"])
        #expect(desk.layouts.partners(of: "h") == ["q1", "q2"])
    }

    // The first look takes the layouts in view as they are.
    @Test("at the first look the tiles in view form layouts")
    func firstLook() {
        var layouts = Layouts<String>()
        layouts.observe([("laptop", CGRect(x: 0, y: 33, width: 1470, height: 923)), ("a", left), ("b", right),
                         ("small", CGRect(x: 2600, y: 300, width: 500, height: 400))], displays: displays)
        #expect(layouts.partners(of: "a") == ["b"])
        #expect(layouts.partners(of: "laptop") == [])
    }

    @Test("tiles hidden behind another window are not in view")
    func hiddenTilesAreNotInView() {
        var layouts = Layouts<String>()
        layouts.observe([("a", left), ("b", right), ("cover", maximized)], displays: displays)
        #expect(layouts.partners(of: "a") == [])
    }

    @Test("a tile under three windows that each hide less than half is not in view")
    func tileCoveredByThreeStripsIsNotInView() {
        var layouts = Layouts<String>()
        let strips = [30, 380, 730].map { CGRect(x: 2400, y: $0, width: 1000, height: 350) }
        layouts.observe([("a", left), ("b", right), ("s1", strips[0]), ("s2", strips[1]), ("s3", strips[2])], displays: displays)
        #expect(layouts.partners(of: "a") == [])
    }

    @Test("a tile hidden by exactly half is not in view")
    func halfHiddenTileIsNotInView() {
        var layouts = Layouts<String>()
        layouts.observe([("a", left), ("b", right), ("q", topRight)], displays: displays)
        #expect(layouts.partners(of: "a") == ["q"])
    }

    // Regression: windows that merely became visible side by side were remembered as a layout,
    // which mixed two pairs for good once the window in front of one of them was closed.
    @Test("closing or minimizing a window does not pair the windows it uncovers")
    func uncoveredWindowsAreNotPaired() {
        var desk = desk([("a", left), ("b", right), ("c", left), ("d", right)])
        desk.hide("d")
        desk.pick("c")
        #expect(desk.layouts.partners(of: "a") == ["b"])
        #expect(desk.layouts.partners(of: "c") == ["d"])
        desk.show("d")
        #expect(desk.layouts.partners(of: "d") == ["c"])
    }

    // Regression: each native tab is a window of its own with the same frame. Switching tabs
    // looked like a new window arranged on the tile and took the partner from the first tab.
    @Test("switching tabs in a tiled window keeps the partner for every tab")
    func tabSwitch() {
        var desk = desk([("tab1", left), ("partner", right)])
        desk.hide("tab1")
        desk.put("tab2", at: left)
        #expect(desk.layouts.partners(of: "partner") == ["tab1", "tab2"])
        desk.put("word", at: maximized)
        desk.pick("tab2")
        #expect(desk.isAbove("partner", "word"))
        desk.hide("tab2")
        desk.show("tab1")
        desk.pick("word")
        desk.pick("tab1")
        #expect(desk.isAbove("partner", "word"))
    }

    @Test("a window that opens on a tile was not arranged there")
    func openedOnATile() {
        var desk = desk([("a", left), ("b", right)])
        desk.put("new", at: right)
        #expect(desk.layouts.partners(of: "a") == ["b"])
    }

    // Regression: unplugging the external display moves every window at once and wiped the memory.
    @Test("a display that goes away and comes back does not rearrange anything")
    func displayGoneAndBack() {
        var desk = desk([("a", left), ("b", right), ("c", left), ("d", right)])
        let arranged = desk.stack
        desk.displays = [displays[0]]
        desk.stack = arranged.map { ($0.id, CGRect(x: $0.id < "c" ? 0 : 510, y: 33, width: 960, height: 923)) }
        desk.look()
        desk.displays = displays
        desk.stack = arranged
        desk.look()
        #expect(desk.layouts.partners(of: "a") == ["b"])
        #expect(desk.layouts.partners(of: "c") == ["d"])
    }

    @Test("a floating window moved over one tile does not change the layout")
    func floatingWindowOverATile() {
        var desk = desk([("h", left), ("q", topRight), ("r", bottomRight)])
        desk.put("finder", at: floating)
        desk.put("finder", at: CGRect(x: 2450, y: 60, width: 920, height: 436))
        #expect(desk.layouts.partners(of: "h") == ["q", "r"])
    }

    @Test("a window moved out by hand has left, and belongs again once it is snapped back")
    func movedOutAndSnappedBack() {
        var desk = desk([("a", left), ("b", right)])
        desk.put("b", at: floating)
        #expect(desk.layouts.partners(of: "a") == [])
        desk.put("b", at: right)
        #expect(desk.layouts.partners(of: "a") == ["b"])
    }

    @Test("when a window that replaced another is moved away, the old partner is back")
    func replacementMovedAway() {
        var desk = desk([("a", left), ("b", right), ("c", right)])
        #expect(desk.layouts.partners(of: "a") == ["c"])
        desk.put("c", at: floating)
        #expect(desk.layouts.partners(of: "a") == ["b"])
    }

    // Regression: with its replacement closed, b's old neighbour still counted as taken and never came up.
    @Test("when a window that replaced another is closed, the old neighbour stands in again")
    func replacementClosed() {
        var desk = desk([("a", left), ("b", right), ("c", right)])
        desk.hide("c")
        desk.put("word", at: maximized)
        desk.pick("b")
        #expect(desk.isAbove("a", "word"))
    }

    // Regression: the half was taken for "part of the old layout in view" and the buried quarter stayed its partner.
    @Test("a quarter grown to a half over its sibling leaves the sibling behind")
    func quarterGrownToAHalf() {
        var desk = desk([("f", left), ("a", topRight), ("b", bottomRight)])
        desk.put("a", at: right)
        #expect(desk.layouts.partners(of: "f") == ["a"])
    }

    // Regression: d went back to a, the window c had replaced long before, and c was left alone.
    @Test("when one of three windows leaves, the other two stay together")
    func twoOfThreeStayTogether() {
        var desk = desk([("a", thirds[0]), ("d", thirds[1]), ("c", thirds[0]), ("f", thirds[2])])
        desk.put("f", at: left)
        desk.arrange("g", at: right)
        #expect(desk.layouts.partners(of: "d") == ["c"])
        #expect(desk.layouts.partners(of: "f") == ["g"])
    }

    // Regression: a came back next to d, and c was sent to b, a pairing that existed only for the
    // moment while the second pair was being built.
    @Test("a layout that was only a step towards another one is not returned to")
    func stepLayoutIsForgotten() {
        var desk = desk([("a", left), ("b", right), ("c", left), ("d", right)])
        desk.pick("a")
        desk.put("a", at: maximized)
        desk.pick("c")
        desk.pick("a")
        desk.put("a", at: left)
        #expect(desk.layouts.partners(of: "a") == ["d"])
        #expect(desk.layouts.partners(of: "b") == [])
        #expect(desk.layouts.partners(of: "c") == [])
    }

    @Test("a layout rebuilt again and again does not push the others out")
    func repeatedLayoutIsRememberedOnce() {
        var desk = desk([("a", left), ("b", right), ("c", left), ("d", right)])
        for _ in 1...60 {
            desk.put("c", at: floating)
            desk.put("c", at: left)
        }
        desk.put("c", at: floating)
        desk.put("d", at: floating)
        #expect(desk.layouts.partners(of: "a") == ["b"])
    }

    @Test("a partner moved out of the layout by hand is no longer raised")
    func movedPartnerIsDropped() {
        let windows = [("b", floating), ("cover", maximized), ("a", left)]
        #expect(windowsToRaise(picked: "a", windows: windows, displays: displays, partners: ["b"], taken: []) == [])
    }

    @Test("remembered partners come before a free window on the same tile")
    func rememberedPartnerBeatsAFreeWindow() {
        let windows = [("b", right), ("free", right), ("cover", maximized), ("a", left)]
        #expect(windowsToRaise(picked: "a", windows: windows, displays: displays, partners: ["b"], taken: ["a", "b"]) == ["b"])
    }

    @Test("without a remembered partner a free tile next to the picked window stands in")
    func freeTileStandsIn() {
        let windows = [("b", right), ("cover", maximized), ("a", left)]
        #expect(windowsToRaise(picked: "a", windows: windows, displays: displays, partners: [], taken: []) == ["b"])
        // The same when the picked window itself has a layout whose other windows are gone.
        #expect(windowsToRaise(picked: "a", windows: windows, displays: displays, partners: ["gone"], taken: ["a", "gone"]) == ["b"])
    }

    // Regression: with the partner closed or minimized, the tile next to the picked window belongs
    // to another pair. Raising it mixed two pairs.
    @Test("a window remembered in another layout does not stand in")
    func rememberedWindowsDoNotStandIn() {
        let windows = [("b", right), ("a", left), ("cover", maximized), ("c", right)]
        #expect(windowsToRaise(picked: "c", windows: windows, displays: displays, partners: ["gone"], taken: ["a", "b", "c"]) == [])
    }

    // Regression: a free window was dug out from under the visible tile of another pair.
    @Test("a free window buried under another layout's tile does not stand in")
    func buriedFreeWindowDoesNotStandIn() {
        let windows = [("free", left), ("a", left), ("b", right), ("d", right)]
        #expect(windowsToRaise(picked: "d", windows: windows, displays: displays, partners: ["gone"], taken: ["a", "b", "d", "gone"]) == [])
    }

    @Test("only layouts with two or more windows on screen count as taken")
    func takenNeedsTwoOnScreen() {
        let desk = desk([("a", left), ("b", right), ("c", left), ("d", right)])
        #expect(desk.layouts.grouped(among: ["a", "b", "c"]) == ["a", "b"])
    }

    // Regression: a tab that came to the front joined no layout, so with a second pair stacked on
    // the tiles, or in a layout of three, its partners did not come up.
    @Test("a tab switched in on a tile of a stacked pair still brings its partner")
    func tabSwitchOverAnotherPair() {
        var desk = desk([("c", left), ("d", right), ("tab1", left), ("b", right)])
        desk.hide("tab1")
        desk.put("tab2", at: left)
        desk.pick("c")
        desk.pick("tab2")
        #expect(desk.top(at: right) == "b", "\(desk.stack.map(\.id))")
    }

    @Test("a tab switched in on the half of a half and two quarters still brings the quarters")
    func tabSwitchInHalfAndQuarters() {
        var desk = desk([("tab1", left), ("q1", topRight), ("q2", bottomRight)])
        desk.hide("tab1")
        desk.put("tab2", at: left)
        desk.put("word", at: maximized)
        desk.pick("tab2")
        #expect(desk.isAbove("q1", "word") && desk.isAbove("q2", "word"), "\(desk.stack.map(\.id))")
        desk.pick("word")
        desk.pick("q1")
        #expect(desk.isAbove("tab2", "word"), "\(desk.stack.map(\.id))")
    }

    // Regression: the tab layout re-formed with tab2 only (partner moved out and snapped back), and
    // tab1, seen before, never joined again when it came back, so its partner stayed under another pair.
    @Test("a tab seen before rejoins its sibling's re-formed layout when it comes back")
    func tabBackAfterLayoutReformed() {
        var desk = desk([("c", left), ("d", right), ("tab1", left), ("p", right)])
        desk.hide("tab1")
        desk.put("tab2", at: left)
        desk.pick("tab2")
        desk.put("p", at: floating)
        desk.put("p", at: right)
        desk.hide("tab2")
        desk.show("tab1")
        #expect(desk.layouts.partners(of: "tab1").contains("p"))
        desk.pick("tab1")
        desk.pick("c")
        desk.pick("tab1")
        #expect(desk.top(at: right) == "p", "\(desk.stack.map(\.id))")
        let all = desk.layouts.standing.flatMap { $0 }
        #expect(all.count == Set(all).count)
    }

    // Regression: a tab joined the standing layout but not the remembered one, so a layout that came
    // back after a cover moved away brought the tab that was off screen, not the one in view.
    @Test("a tab switched in comes back with its layout after a cover moves away")
    func tabComesBackWithItsLayout() {
        var three = desk([("t1", thirds[0]), ("b", thirds[1]), ("c", thirds[2])])
        three.hide("t1")
        three.put("t2", at: thirds[0])
        three.pick("t2")
        three.arrange("x", at: CGRect(x: 1470, y: 30, width: 1280, height: 1050))
        three.put("x", at: floating)
        #expect(three.layouts.partners(of: "c") == ["t1", "t2", "b"])
        three.put("word", at: maximized)
        three.pick("c")
        #expect(three.isAbove("t2", "word"), "\(three.stack.map(\.id))")

        var pair = desk([("t1", left), ("b", right)])
        pair.hide("t1")
        pair.put("t2", at: left)
        pair.arrange("x", at: right)
        pair.put("x", at: floating)
        #expect(pair.layouts.partners(of: "b") == ["t1", "t2"])
        pair.arrange("e", at: left)
        pair.arrange("f", at: right)
        pair.pick("t2")
        #expect(pair.top(at: right) == "b", "\(pair.stack.map(\.id))")

        var quarters = desk([("tab1", left), ("q1", topRight), ("q2", bottomRight)])
        quarters.hide("tab1")
        quarters.put("tab2", at: left)
        quarters.arrange("x", at: right)
        quarters.put("x", at: floating)
        #expect(quarters.layouts.partners(of: "tab2") == ["tab1", "q1", "q2"])
    }

    // Regression: dragging a tab out moved it, and a moved window deleted every remembered layout
    // it was in, so the layout its sibling tab and partner still form was forgotten.
    @Test("a tab dragged out of a tiled window leaves its sibling's layout remembered")
    func tabDraggedOut() {
        var desk = desk([("c", left), ("dd", right), ("t1", left), ("p", right)])
        desk.hide("t1")
        desk.put("t2", at: left)
        desk.pick("t2")
        // One look: t2 dragged out to the laptop, t1 back on screen as the remaining tab.
        desk.stack.removeAll { $0.id == "t2" }
        desk.stack.append(("t1", desk.hidden.removeValue(forKey: "t1")!))
        desk.stack.append(("t2", CGRect(x: 0, y: 30, width: 735, height: 926)))
        desk.look()
        #expect(desk.layouts.partners(of: "t1") == ["p"])
        desk.arrange("x", at: right)
        desk.put("x", at: floating)
        #expect(desk.layouts.partners(of: "t1") == ["p"])
        desk.pick("c")
        desk.pick("t1")
        #expect(desk.top(at: right) == "p", "\(desk.stack.map(\.id))")
    }

    // Regression: tabs move together, but a background tab keeps the frame it had when last on screen.
    // Coming to the front at its sibling's tile looked like a move and paired it with another layout's window.
    @Test("a tab last seen elsewhere joins its sibling's layout, not the pair under it")
    func tabWithStaleFrame() {
        var desk = desk([("c", left), ("d", right)])
        desk.put("t1", at: floating)
        desk.hide("t1")
        desk.put("t2", at: floating)
        desk.hide("t2")
        desk.show("t1")
        desk.arrange("p", at: right)
        desk.put("t1", at: left)
        desk.put("word", at: maximized)
        desk.pick("c")
        desk.hide("t1")
        desk.put("t2", at: left)
        #expect(desk.layouts.partners(of: "t2") == ["t1", "p"])
        #expect(desk.layouts.partners(of: "c") == ["d"])
        desk.pick("t2")
        #expect(desk.top(at: right) == "p", "\(desk.stack.map(\.id))")
    }

    // Regression: a moved window was only taken out of its remembered layouts, so {a,b} left of
    // {a,b,d} stood newer than {a,b,c} and settled in its place, dropping c.
    @Test("when a window that replaced one of three is moved away, the old layout of three is back")
    func replacementOfThreeMovedAway() {
        var desk = desk(Array(zip(["a", "b", "c"], thirds)))
        desk.arrange("d", at: thirds[2])
        #expect(desk.layouts.partners(of: "a") == ["b", "d"])
        desk.put("d", at: floating)
        #expect(desk.layouts.partners(of: "a") == ["b", "c"])
        desk.put("word", at: maximized)
        desk.pick("a")
        #expect(desk.isAbove("c", "word"))
    }

    // Regression: a background tab keeps the frame it had when last seen. Switched in while its layout
    // had nothing on screen, it joined nothing but counted as moved, so it paired with the tile beside
    // it and broke that layout up.
    @Test("a tab with a stale frame switched in while its partners are away breaks no other layout")
    func staleTabBreaksNothing() {
        var desk = desk([("c", left), ("d", right)])
        desk.put("t1", at: floating)
        desk.hide("t1")
        desk.put("t2", at: floating)
        desk.hide("t2")
        desk.show("t1")
        desk.put("t1", at: left)
        desk.arrange("p", at: right)
        #expect(desk.layouts.partners(of: "c") == ["d"])
        desk.hide("p")
        desk.hide("t1")
        desk.put("t2", at: left)
        #expect(desk.layouts.partners(of: "c") == ["d"])
        #expect(desk.layouts.partners(of: "d") == ["c"])
        desk.put("word", at: maximized)
        desk.pick("c")
        #expect(desk.isAbove("d", "word"), "\(desk.stack.map(\.id))")
    }

    // Only a window gone in the same look counts as the sibling of a tab; one closed long ago does not.
    @Test("a new window on the tile of a window closed earlier joins nothing")
    func newWindowOnTileOfWindowClosedEarlier() {
        var desk = desk([("c", left), ("d", right), ("a", left), ("b", right)])
        desk.hide("a")
        desk.pick("c")
        desk.put("n", at: left)
        #expect(desk.layouts.partners(of: "n") == [])
        desk.pick("n")
        #expect(desk.top(at: right) == "d")
    }

    // A background tab moved with its window, which a drag took out of a layout that then stayed
    // behind without it. Coming to the front, it is a moved window, not a tab joining a second layout.
    @Test("switching to a tab after its window was moved keeps each window in one layout")
    func tabAfterWindowMoved() {
        var desk = desk([("c", left), ("d", right), ("t1", left), ("p", right)])
        desk.hide("t1")
        desk.put("t2", at: left)
        desk.put("t2", at: right)
        desk.hide("t2")
        desk.put("t1", at: right)
        let all = desk.layouts.standing.flatMap { $0 }
        #expect(all.count == Set(all).count, "\(desk.layouts.standing)")
        #expect(desk.layouts.partners(of: "t1").contains("c"), "\(desk.layouts.standing)")
        #expect(!desk.layouts.partners(of: "p").contains("t1"), "\(desk.layouts.standing)")
    }

    // Only a tab that replaced a gone sibling is exempt from counting as moved. Here the window was
    // snapped with tab1 in the background, so tab1's last frame is stale; dragging tab2 out brings
    // tab1 up on the tile while tab2 stays on screen: tab1 moved there and pairs with p.
    @Test("a background tab left on the tile when its sibling is dragged out pairs with the partner")
    func staleTabLeftByDragOut() {
        var desk = desk([("p", right)])
        desk.put("tab1", at: floating)
        desk.hide("tab1")
        desk.put("tab2", at: floating)
        desk.put("tab2", at: left)
        desk.stack.removeAll { $0.id == "tab2" }
        desk.stack.append(("tab1", left))
        desk.stack.append(("tab2", CGRect(x: 100, y: 100, width: 600, height: 500)))
        desk.look()
        #expect(desk.layouts.partners(of: "tab1") == ["p"])
        #expect(desk.layouts.partners(of: "tab2") == [])
    }

    // Regression: a Space switch takes every window off screen at once, and the tiles on the other
    // Space sit at the same frames, so they were taken for tabs and merged into the pair left behind.
    @Test("windows on another Space at the same tiles are not tabs of the pair left behind")
    func spaceSwitch() {
        var desk = desk([("a", left), ("b", right)])
        desk.stack = [("c", left), ("d", right)]
        desk.look()
        desk.arrange("e", at: right)
        #expect(desk.layouts.partners(of: "a") == ["b"])
    }

    // Regression: the two quarters a half was snapped over stayed a layout of their own, which kept
    // the half and quarters from coming back and kept the quarters from standing in.
    @Test("quarters a half was snapped over do not stay a layout of their own")
    func quartersUnderAHalfAreLoose() {
        var moved = desk([("h", left), ("q1", topRight), ("q2", bottomRight), ("x", right)])
        #expect(moved.layouts.partners(of: "q1") == [])
        moved.put("x", at: floating)
        #expect(moved.layouts.partners(of: "h") == ["q1", "q2"])
        moved.put("word", at: maximized)
        moved.pick("h")
        #expect(moved.isAbove("q1", "word") && moved.isAbove("q2", "word"))

        var closed = desk([("h", left), ("q1", topRight), ("q2", bottomRight), ("x", right)])
        closed.hide("x")
        closed.put("word", at: maximized)
        closed.pick("h")
        #expect(closed.isAbove("q1", "word") && closed.isAbove("q2", "word"))
    }

    // Regression: a window snapped over two members of a layout, then moved away, left the third
    // member alone and the other two split from it.
    @Test("a layout comes back when a window that covered two of its members moves away")
    func coverOfTwoMembersMovesAway() {
        var desk = desk([("a", thirds[0]), ("b", thirds[1]), ("c", thirds[2])])
        desk.arrange("x", at: CGRect(x: 1470, y: 30, width: 1280, height: 1050))  // first two thirds
        desk.put("x", at: floating)
        #expect(desk.layouts.partners(of: "c") == ["a", "b"])
        desk.put("word", at: maximized)
        desk.pick("c")
        #expect(desk.isAbove("a", "word"))
        #expect(desk.isAbove("b", "word"))
    }

    // Regression: with the middle third closed or minimized the outer thirds no longer touch.
    // The right third stayed buried, and a free window on the middle tile came up instead.
    @Test("with the middle window of a layout gone, its outer partner still comes up")
    func middleOfLayoutGone() {
        var desk = Desk(displays: displays)
        desk.put("old", at: thirds[1])
        zip(["a", "b", "c"], thirds).forEach { desk.arrange($0.0, at: $0.1) }
        desk.put("word", at: maximized)
        desk.hide("b")
        desk.pick("a")
        #expect(desk.isAbove("c", "word"))
        #expect(!desk.isAbove("old", "word"))
    }

    @Test("with two diagonal quarters gone, the other two still come up together")
    func diagonalQuartersGone() {
        let q = [(1470, 30), (2430, 30), (1470, 555), (2430, 555)].map { CGRect(x: $0.0, y: $0.1, width: 960, height: 525) }
        var desk = desk(Array(zip(["tl", "tr", "bl", "br"], q)))
        desk.put("word", at: maximized)
        desk.hide("tr")
        desk.hide("bl")
        desk.pick("tl")
        #expect(desk.isAbove("br", "word"))
    }

    // Regression: one snap broke two layouts, and the first one's leftover took back a window the
    // second one's leftovers still held, so that window ended up in two layouts.
    @Test("a snap that breaks two layouts leaves each window in one layout")
    func doubleBreak() {
        let topLeft = CGRect(x: 1470, y: 30, width: 960, height: 525)
        let bottomLeft = CGRect(x: 1470, y: 555, width: 960, height: 525)
        var desk = Desk(displays: displays)
        desk.arrange("p", at: left)
        desk.arrange("q", at: right)
        desk.arrange("x", at: right)
        desk.pick("q")
        desk.arrange("y", at: topLeft)
        desk.arrange("r", at: bottomLeft)
        desk.pick("x")
        desk.put("y", at: left)  // breaks {p,x} and {q,y,r} at once
        let all = desk.layouts.standing.flatMap { $0 }
        #expect(all.count == Set(all).count)
        #expect(desk.layouts.partners(of: "q") == ["r"])
        desk.arrange("word", at: maximized)
        desk.pick("q")
        #expect(desk.isAbove("r", "word"))
        #expect(!desk.isAbove("p", "word"))
    }

    // Regression: b was minimized while the display went away and came back on the laptop.
    // Its frame from before the change made it look moved by hand, which broke its pair.
    @Test("a window off screen while a display goes away is not moved by hand when it comes back")
    func displayGoneWhileMinimized() {
        var desk = desk([("a", left), ("b", right)])
        desk.hide("b")
        desk.displays = [displays[0]]
        desk.stack = [("a", CGRect(x: 0, y: 33, width: 960, height: 923))]
        desk.look()
        desk.hidden["b"] = CGRect(x: 510, y: 33, width: 960, height: 923)  // restored on the laptop
        desk.show("b")
        desk.displays = displays
        desk.stack = [("a", left), ("b", right)]
        desk.look()
        #expect(desk.layouts.partners(of: "a") == ["b"])
    }

    // Regression: layouts of closed windows stay in `standing`, and a cap on it pushed out live pairs.
    @Test("layouts of closed windows do not push out a live pair")
    func closedPairsKeepLivePair() {
        var desk = desk([("a", left), ("b", right), ("c", left), ("d", right)])
        let laptopLeft = CGRect(x: 0, y: 33, width: 735, height: 923)
        let laptopRight = CGRect(x: 735, y: 33, width: 735, height: 923)
        for n in 0..<50 {  // two live and fifty closed pairs: past the old cap of 50
            desk.arrange("p\(n)", at: laptopLeft)
            desk.arrange("q\(n)", at: laptopRight)
            desk.hide("p\(n)")
            desk.hide("q\(n)")
        }
        #expect(desk.layouts.partners(of: "a") == ["b"])
        desk.put("word", at: maximized)
        desk.pick("a")
        #expect(desk.isAbove("b", "word"))
    }

    // Everything the app does, on a model of the screen: arrange, pick, raise, look.
    @Test("pairs stacked on the same two tiles always come back with their own partner")
    func stackedPairsSimulation() {
        for pairs in 2...4 {
            for leftFirst in [true, false] {
                var desk = Desk(displays: displays)
                var partner: [String: String] = [:]
                for n in 0..<pairs {
                    let (l, r) = ("l\(n)", "r\(n)")
                    (partner[l], partner[r]) = (r, l)
                    for id in leftFirst ? [l, r] : [r, l] {
                        desk.arrange(id, at: id.hasPrefix("l") ? left : right)
                    }
                }
                desk.put("word", at: maximized)
                let ids = partner.keys.sorted()
                for step in 0..<60 {
                    if step % 3 == 0 { desk.pick("word") }
                    let id = ids[(step * 7 + step / 5) % ids.count]
                    desk.pick(id)
                    let other = id.hasPrefix("l") ? right : left
                    #expect(desk.top(at: other) == partner[id], "pairs \(pairs), step \(step), picked \(id)")
                    #expect(desk.isAbove(partner[id]!, "word"), "pairs \(pairs), step \(step), picked \(id)")
                }
            }
        }
    }

    @Test("closing a window of the top pair leaves the pair underneath intact")
    func closingAWindowSimulation() {
        var desk = desk([("a", left), ("b", right), ("c", left), ("d", right)])
        desk.hide("d")
        desk.pick("c")
        desk.put("word", at: maximized)
        desk.pick("a")
        #expect(desk.top(at: right) == "b")
        #expect(desk.isAbove("b", "word"))
        desk.pick("word")
        desk.pick("b")
        #expect(desk.isAbove("a", "word"))
    }
}
