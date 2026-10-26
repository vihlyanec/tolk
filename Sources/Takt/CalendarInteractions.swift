import AppKit
import SwiftUI

struct CalendarResizeMath {
    static func clampedDelta(_ delta: Double, top: Bool, duration: Int, pixels: Double) -> Double {
        if top { return min(Double(max(0, duration - 15)) * pixels, max(-Double(10080 - duration) * pixels, delta)) }
        return max(Double(min(0, 15 - duration)) * pixels, min(Double(10080 - duration) * pixels, delta))
    }
    static func snappedMinutes(_ delta: Double, pixels: Double) -> Int { Int((delta / pixels / 15).rounded()) * 15 }
}

/// AppKit keeps mouse capture on this view even as its SwiftUI parent changes size.
struct CalendarResizeHandle: NSViewRepresentable {
    let label: String
    let step: Double
    let began: () -> Void
    let changed: (Double) -> Void
    let ended: (Double) -> Void
    func makeNSView(context: Context) -> CalendarResizeRegion { CalendarResizeRegion() }
    func updateNSView(_ view: CalendarResizeRegion, context: Context) {
        view.began = began; view.changed = changed; view.ended = ended; view.step = step
        view.setAccessibilityElement(true); view.setAccessibilityRole(.incrementor); view.setAccessibilityLabel(label)
        view.setAccessibilityHelp("Потяните границу. Шаг клавиатурного изменения — 15 минут.")
    }
}
final class CalendarResizeRegion: NSView {
    var began: () -> Void = {}
    var changed: (Double) -> Void = { _ in }
    var ended: (Double) -> Void = { _ in }
    var step = 24.0
    override func accessibilityPerformIncrement() -> Bool { began(); ended(step); return true }
    override func accessibilityPerformDecrement() -> Bool { began(); ended(-step); return true }
    private var startY: CGFloat = 0
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeUpDown) }
    override func mouseDown(with event: NSEvent) { startY = event.locationInWindow.y; began() }
    override func mouseDragged(with event: NSEvent) { changed(Double(startY - event.locationInWindow.y)) }
    override func mouseUp(with event: NSEvent) { ended(Double(startY - event.locationInWindow.y)) }
}

struct CalendarSwipeAccumulator {
    var x = 0.0, y = 0.0
    var fired = false
    var vertical = false
    mutating func reset() { x = 0; y = 0; fired = false; vertical = false }
    mutating func feed(dx: Double, dy: Double) -> Int? {
        x += dx; y += dy
        if abs(y) > 12 && abs(y) > abs(x) * 1.4 { vertical = true }
        guard !vertical, !fired, abs(x) >= 150, abs(x) > abs(y) * 1.8 else { return nil }
        fired = true; return x < 0 ? 1 : -1
    }
    var consumesHorizontal: Bool { !vertical && abs(x) > 3 && abs(x) > abs(y) * 1.8 }
}
struct CalendarSwipeSurface: NSViewRepresentable {
    let advance: (Int) -> Void
    func makeNSView(context: Context) -> CalendarSwipeRegion { CalendarSwipeRegion() }
    func updateNSView(_ view: CalendarSwipeRegion, context: Context) { view.advance = advance }
    static func dismantleNSView(_ view: CalendarSwipeRegion, coordinator: ()) { view.stop() }
}
final class CalendarSwipeRegion: NSView {
    var advance: (Int) -> Void = { _ in }
    private var monitor: Any?
    private var accumulator = CalendarSwipeAccumulator()
    private var lastTime = 0.0
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stop(); return }
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, event.window === self.window,
                  self.bounds.contains(self.convert(event.locationInWindow, from: nil)), event.hasPreciseScrollingDeltas else { return event }
            if event.phase.contains(.began) || (event.phase.isEmpty && event.momentumPhase.isEmpty && event.timestamp - self.lastTime > 0.3) { self.accumulator.reset() }
            self.lastTime = event.timestamp
            if !event.momentumPhase.isEmpty { return self.accumulator.consumesHorizontal ? nil : event }
            if let direction = self.accumulator.feed(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY) { self.advance(direction) }
            return self.accumulator.consumesHorizontal ? nil : event
        }
    }
    func stop() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
}
