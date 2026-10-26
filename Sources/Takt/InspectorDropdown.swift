import SwiftUI
import AppKit

struct InspectorMenuOption {
    var title: String
    var symbol: String? = nil
    var selected = false
    var separator = false
    var action: () -> Void
}

/// A real NSMenu behind a plain SwiftUI button: macOS must not flatten the colored pill label.
struct InspectorDropdown: View {
    let symbol: String
    let title: String
    var tint: Color = .secondary
    let options: [InspectorMenuOption]
    @ViewState private var anchor = InspectorMenuAnchor()
    var body: some View {
        Button { DispatchQueue.main.async { show() } } label: { InspectorPill(symbol: symbol, title: title, tint: tint) }
            .buttonStyle(.plain).background(InspectorAnchorView(anchor: anchor))
    }
    private func show() {
        guard let view = anchor.view else { return }
        let menu = NSMenu(); menu.autoenablesItems = false; menu.appearance = view.effectiveAppearance
        var handlers: [InspectorMenuHandler] = []
        for option in options {
            if option.separator { menu.addItem(.separator()); continue }
            let handler = InspectorMenuHandler(option.action); handlers.append(handler)
            let row = NSMenuItem(title: option.title, action: #selector(InspectorMenuHandler.run), keyEquivalent: "")
            row.target = handler; row.state = option.selected ? .on : .off
            if let symbol = option.symbol { row.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
            menu.addItem(row)
        }
        withExtendedLifetime(handlers) {
            _ = menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.isFlipped ? view.bounds.maxY : view.bounds.minY), in: view)
        }
    }
}
final class InspectorMenuHandler: NSObject {
    private let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func run() { action() }
}
final class InspectorMenuAnchor { weak var view: NSView? }
struct InspectorAnchorView: NSViewRepresentable {
    let anchor: InspectorMenuAnchor
    func makeNSView(context: Context) -> InspectorAnchorRegion { let view = InspectorAnchorRegion(); anchor.view = view; return view }
    func updateNSView(_ view: InspectorAnchorRegion, context: Context) { anchor.view = view }
}
final class InspectorAnchorRegion: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
