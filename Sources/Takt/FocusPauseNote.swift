import AppKit
import SwiftUI

enum FocusPauseGeometry {
    static func frame(in screen: NSRect, size: NSSize) -> NSRect {
        let size = NSSize(width: min(size.width, screen.width), height: min(size.height, screen.height))
        return NSRect(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2,
                      width: size.width, height: size.height)
    }
}

private final class FocusPauseHost: NSHostingView<AnyView> {
    override var acceptsFirstResponder: Bool { true }
    override var needsPanelToBecomeKey: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Takes text input over the current app without activating Tolk or its main window.
final class FocusPauseController {
    private let state: AppState
    private(set) var panel: KeyPanel?

    init(state: AppState) { self.state = state }

    func sync() {
        guard state.pomodoro.pausePrompt, let session = state.pomodoro.session,
              session.deadline == nil, session.remaining > 0 else {
            panel?.orderOut(nil)
            return
        }
        if let panel, panel.isVisible {
            applyAppearance(panel)
            return // Sync must not replace a draft or take focus again while typing.
        }
        let panel: KeyPanel
        if let existing = self.panel { panel = existing }
        else {
            panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 430, height: 320),
                             styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
                             backing: .buffered, defer: false)
            panel.title = "С чего продолжить?"
            panel.identifier = NSUserInterfaceItemIdentifier("tolk-focus-pause")
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.isReleasedWhenClosed = false
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.becomesKeyOnlyIfNeeded = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            panel.escape = { [weak self] in self?.state.pomodoro.skipResumeNote() }
            self.panel = panel
        }
        // Recreate the editor only on a fresh presentation so keyboard focus is
        // requested once; changing screens or sync callbacks never reset its draft.
        let host = FocusPauseHost(rootView: AnyView(PomodoroPauseNote(state: state)))
        panel.contentView = host
        panel.setContentSize(NSSize(width: 430, height: max(320, host.fittingSize.height)))
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main ?? NSScreen.screens.first
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        panel.setFrame(FocusPauseGeometry.frame(in: visibleFrame, size: panel.frame.size), display: true)
        applyAppearance(panel)
        panel.makeKeyAndOrderFront(nil)
    }

    private func applyAppearance(_ panel: NSPanel) {
        let theme = state.data.preferences.theme
        panel.appearance = theme == "dark" ? NSAppearance(named: .darkAqua)
            : theme == "light" ? NSAppearance(named: .aqua) : nil
    }
}
