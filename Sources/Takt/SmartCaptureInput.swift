import AppKit
import SwiftUI
import TaktCore

/// Uses the parser's accepted source ranges: unknown tags and invalid dates stay plain.
struct SmartCaptureInput: NSViewRepresentable {
    @Binding var text: String
    @Binding var literals: [QuickLiteralToken]
    let parsed: ParsedTask
    let projects: [Project]
    let tags: [Tag]
    let placeholder: String
    var fontSize: CGFloat = 20
    var autoFocus = false
    var focusRequest: UUID? = nil
    var singleLine = false
    var calendar = Dates.calendar()
    var onFocus: (Bool) -> Void = { _ in }
    var expandDescription: (() -> Void)? = nil
    let submit: () -> Void
    var move: (Int) -> Bool = { _ in false }
    var complete: () -> Bool = { false }

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false; scroll.hasVerticalScroller = false
        let editor = CaptureTextView(frame: NSRect(x: 0, y: 0, width: 560, height: 32))
        editor.isRichText = false; editor.drawsBackground = false
        editor.isVerticallyResizable = true; editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]; editor.textContainer?.widthTracksTextView = true
        if singleLine {
            editor.isVerticallyResizable = false; editor.isHorizontallyResizable = true
            editor.autoresizingMask = [.height]
            editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: 32)
            editor.textContainer?.widthTracksTextView = false
            editor.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: 32)
            editor.textContainer?.maximumNumberOfLines = 1
            editor.textContainer?.lineBreakMode = .byClipping
        }
        editor.textContainerInset = .zero
        editor.textContainer?.lineFragmentPadding = 0
        editor.allowsUndo = true; editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false; editor.isAutomaticTextReplacementEnabled = false
        editor.delegate = context.coordinator; editor.placeholder = placeholder; editor.onShiftReturn = expandDescription
        editor.setAccessibilityLabel(placeholder)
        scroll.documentView = editor
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator; coordinator.parent = self
        guard let editor = scroll.documentView as? CaptureTextView else { return }
        editor.placeholder = placeholder; editor.font = .systemFont(ofSize: fontSize); editor.onShiftReturn = expandDescription
        if editor.string != text && !editor.hasMarkedText() {
            let selection = editor.selectedRange()
            let wasAtEnd = selection.length == 0 && selection.location == (editor.string as NSString).length
            editor.string = text
            let length = (text as NSString).length
            editor.setSelectedRange(NSRange(location: wasAtEnd ? length : min(selection.location, length), length: 0))
        }
        coordinator.highlight(editor)
        if (autoFocus && !coordinator.requestedFocus) || (focusRequest != nil && focusRequest != coordinator.lastFocusRequest) {
            coordinator.requestedFocus = true; coordinator.lastFocusRequest = focusRequest
            DispatchQueue.main.async { [weak editor] in if let editor { editor.window?.makeFirstResponder(editor) } }
        }
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SmartCaptureInput
        var requestedFocus = false
        var lastFocusRequest: UUID?
        init(_ parent: SmartCaptureInput) { self.parent = parent }
        func textDidBeginEditing(_ notification: Notification) { parent.onFocus(true) }
        func textDidEndEditing(_ notification: Notification) { parent.onFocus(false) }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            parent.literals = QuickLiteralToken.rebased(parent.literals, from: parent.text, to: editor.string)
            parent.text = editor.string
            if !editor.hasMarkedText() { highlight(editor, parsed: parse(editor.string)) }
        }
        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard !textView.hasMarkedText() else { return false }
            if selector == #selector(NSResponder.deleteBackward(_:)) || selector == #selector(NSResponder.deleteForward(_:)) {
                let backward = selector == #selector(NSResponder.deleteBackward(_:))
                if let token = QuickLiteralToken.tokenToLiteralize(parsed: parse(textView.string), selection: textView.selectedRange(), backward: backward) {
                    textView.breakUndoCoalescing()
                    setLiterals(parent.literals + [QuickLiteralToken(token)], in: textView)
                    return true
                }
            }
            if selector == #selector(NSResponder.insertNewline(_:)) { parent.submit(); return true }
            if selector == #selector(NSResponder.moveDown(_:)) { return parent.move(1) }
            if selector == #selector(NSResponder.moveUp(_:)) { return parent.move(-1) }
            if selector == #selector(NSResponder.insertTab(_:)) { return parent.complete() }
            return false
        }
        private func parse(_ text: String) -> ParsedTask {
            QuickParser.parse(text, projects: parent.projects, tags: parent.tags, calendar: parent.calendar, literalRanges: QuickLiteralToken.ranges(parent.literals, in: text))
        }
        private func setLiterals(_ literals: [QuickLiteralToken], in editor: NSTextView) {
            let previous = parent.literals
            editor.undoManager?.registerUndo(withTarget: self) { [weak editor] coordinator in
                MainActor.assumeIsolated { if let editor { coordinator.setLiterals(previous, in: editor) } }
            }
            editor.undoManager?.setActionName("Распознавание команды")
            parent.literals = literals
            highlight(editor, parsed: parse(editor.string))
        }
        func highlight(_ editor: NSTextView, parsed: ParsedTask? = nil) {
            guard !editor.hasMarkedText(), let storage = editor.textStorage else { return }
            let base: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: parent.fontSize), .foregroundColor: NSColor.labelColor]
            storage.beginEditing(); storage.setAttributes(base, range: NSRange(location: 0, length: storage.length))
            let dark = editor.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            for token in (parsed ?? parent.parsed).tokens where NSMaxRange(token.range) <= storage.length {
                let color = SemanticTint.token(token, projects: parent.projects, tags: parent.tags, dark: dark)
                storage.addAttributes([.foregroundColor: color, .backgroundColor: color.withAlphaComponent(0.12), .font: NSFont.systemFont(ofSize: parent.fontSize, weight: .medium)], range: token.range)
            }
            storage.endEditing(); editor.typingAttributes = base
            if parent.singleLine, let container = editor.textContainer, let manager = editor.layoutManager {
                manager.ensureLayout(for: container)
                let width = max(editor.enclosingScrollView?.contentSize.width ?? 560, manager.usedRect(for: container).width + 8)
                let height = editor.enclosingScrollView?.contentSize.height ?? 32
                editor.setFrameSize(NSSize(width: width, height: max(1, height)))
                if editor.window?.firstResponder === editor { editor.scrollRangeToVisible(editor.selectedRange()) }
            }
            editor.needsDisplay = true
        }
    }
}

final class CaptureTextView: NSTextView {
    var placeholder = ""
    var onShiftReturn: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        if !hasMarkedText(), [36, 76].contains(event.keyCode), event.modifierFlags.contains(.shift),
           event.modifierFlags.intersection([.command, .control, .option]).isEmpty, let onShiftReturn {
            onShiftReturn(); return
        }
        super.keyDown(with: event)
    }
    override var textContainerOrigin: NSPoint {
        let font = font ?? .systemFont(ofSize: 20)
        let lineHeight = layoutManager?.defaultLineHeight(for: font) ?? font.boundingRectForFont.height
        let height = enclosingScrollView?.contentSize.height ?? bounds.height
        // Use the same origin for glyphs, the caret and the empty-field placeholder.
        return NSPoint(x: super.textContainerOrigin.x, y: max(0, (height - lineHeight) / 2))
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty {
            (placeholder as NSString).draw(at: textContainerOrigin, withAttributes: [.font: font ?? .systemFont(ofSize: 20), .foregroundColor: NSColor.placeholderTextColor])
        }
    }
}
