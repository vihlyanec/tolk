import AppKit
import SwiftUI

/// Collapse keeps the top edge fixed. A moved strip restores at its new position.
enum StickyGeometry {
    static let collapsedHeight: CGFloat = 36
    static func toggledFrame(_ frame: NSRect, wasCollapsed: Bool, expandedHeight: CGFloat, visibleFrame: NSRect) -> NSRect {
        let height = min(wasCollapsed ? max(220, expandedHeight) : collapsedHeight, visibleFrame.height)
        let width = min(frame.width, visibleFrame.width)
        return NSRect(x: max(visibleFrame.minX, min(frame.minX, visibleFrame.maxX - width)),
                      y: max(visibleFrame.minY, min(frame.maxY - height, visibleFrame.maxY - height)),
                      width: width, height: height)
    }
}

struct StickyDragHandle: NSViewRepresentable {
    let title: String
    let collapsed: Bool
    let toggle: () -> Void
    func makeNSView(context: Context) -> StickyDragRegion { StickyDragRegion() }
    func updateNSView(_ view: StickyDragRegion, context: Context) {
        view.noteTitle = title; view.collapsed = collapsed; view.toggle = toggle
        view.setAccessibilityElement(true); view.setAccessibilityRole(.button)
        view.setAccessibilityLabel(collapsed ? "Развернуть заметку: " + title : "Свернуть заметку в полоску")
        view.setAccessibilityHelp("Двойной клик — свернуть или развернуть. Потяните, чтобы переместить.")
        view.toolTip = "Двойной клик — " + (collapsed ? "развернуть" : "свернуть") + ". Потяните, чтобы переместить."
        view.needsDisplay = true
    }
}

final class StickyDragRegion: NSView {
    var noteTitle = ""
    var collapsed = false
    var toggle: () -> Void = {}
    override var mouseDownCanMoveWindow: Bool { false }
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { toggle() }
        else { window?.performDrag(with: event) }
    }
    override func accessibilityPerformPress() -> Bool { toggle(); return true }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if collapsed {
            let style = NSMutableParagraphStyle(); style.lineBreakMode = .byTruncatingTail
            let font = NSFont.systemFont(ofSize: 12, weight: .medium)
            let title = noteTitle.isEmpty ? "Заметка" : noteTitle
            (title as NSString).draw(in: NSRect(x: 12, y: (bounds.height - 16)/2, width: max(0, bounds.width - 24), height: 16),
                                     withAttributes: [.font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: style])
        } else {
            NSColor.secondaryLabelColor.withAlphaComponent(0.35).setFill()
            NSBezierPath(roundedRect: NSRect(x: bounds.midX - 16, y: bounds.midY - 1.5, width: 32, height: 3), xRadius: 1.5, yRadius: 1.5).fill()
        }
    }
}
