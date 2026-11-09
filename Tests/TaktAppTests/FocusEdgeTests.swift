import AppKit
import Testing
import TaktCore
@testable import Takt

@Test @MainActor func edgeTimerKeepsRightEdgeAndPointerInsideWhileExpanding() {
    for screen in [NSRect(x: 0, y: 25, width: 1440, height: 850), NSRect(x: -1920, y: 0, width: 1920, height: 1080)] {
        for position in [0.0, 0.6, 1.0, Double.nan] {
            let compact = FocusEdgeGeometry.frame(in: screen, expanded: false, fraction: position)
            let expanded = FocusEdgeGeometry.frame(in: screen, expanded: true, fraction: position)
            #expect(compact.maxX == screen.maxX && expanded.maxX == screen.maxX)
            #expect(screen.contains(compact) && screen.contains(expanded))
            #expect(expanded.contains(NSPoint(x: compact.midX, y: compact.midY)))
        }
    }
}

@Test @MainActor func edgeTimerHoverCanBeInterruptedAndHidingDoesNotStopFocus() async throws {
    let state = AppState(demo: true)
    let edge = FocusEdgeController(state: state)
    edge.sync()
    #expect(edge.panel == nil)
    state.pomodoro.start(Item(title: "Вымышленный сеанс"))
    edge.sync()
    let panel = try #require(edge.panel)
    defer { panel.orderOut(nil) }
    #expect(panel.styleMask.contains(.nonactivatingPanel))
    #expect(panel.level == .floating && !panel.hidesOnDeactivate)
    #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
    edge.hover(true)
    #expect(edge.presentation.expanded && panel.frame.size == FocusEdgeGeometry.expanded)
    edge.hover(false)
    edge.hover(true)
    try await Task.sleep(for: .milliseconds(280))
    #expect(edge.presentation.expanded)
    edge.hover(false)
    try await Task.sleep(for: .milliseconds(280))
    #expect(!edge.presentation.expanded && panel.frame.size == FocusEdgeGeometry.compact)
    let before = state.pomodoro.session
    edge.hide()
    #expect(!panel.isVisible && state.pomodoro.session == before)
    edge.show()
    #expect(panel.isVisible)
    state.pomodoro.stop(); edge.sync()
    #expect(!panel.isVisible)
}
