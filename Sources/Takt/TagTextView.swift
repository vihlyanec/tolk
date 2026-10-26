import AppKit
import SwiftUI
import TaktCore

final class TagTextView: NSTextView {
    var tags: [Tag] = []
    var placeholder = ""
    var isTitleField = false
    var onCommandReturn: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        if !hasMarkedText(), [36, 76].contains(event.keyCode), event.modifierFlags.contains(.command),
           event.modifierFlags.intersection([.control, .option, .shift]).isEmpty, let onCommandReturn {
            onCommandReturn(); return
        }
        super.keyDown(with: event)
    }
    override func mouseDown(with event: NSEvent) {
        // A normal click opens a link; Option-click still places the editing caret.
        if !event.modifierFlags.contains(.option), !event.modifierFlags.contains(.shift),
           let manager = layoutManager, let container = textContainer {
            let point = convert(event.locationInWindow, from: nil)
            let local = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
            let glyph = manager.glyphIndex(for: local, in: container)
            if glyph < manager.numberOfGlyphs,
               manager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container).contains(local),
               let url = textStorage?.attribute(.link, at: manager.characterIndexForGlyph(at: glyph), effectiveRange: nil) as? URL,
               MarkdownHTML.safeURL(url.absoluteString) != nil {
                NSWorkspace.shared.open(url); return
            }
        }
        super.mouseDown(with: event)
    }
    override var rangeForUserCompletion: NSRange {
        let caret = selectedRange().location
        guard caret != NSNotFound, caret <= (string as NSString).length else { return NSRange(location: NSNotFound, length: 0) }
        let prefix = (string as NSString).substring(to: caret)
        guard let range = prefix.range(of: #"(?<![\p{L}\p{N}_/])#[^\s#]*$"#, options: .regularExpression) else { return NSRange(location: NSNotFound, length: 0) }
        return NSRange(range, in: prefix)
    }
    override func completions(forPartialWordRange charRange: NSRange, indexOfSelectedItem index: UnsafeMutablePointer<Int>) -> [String]? {
        guard charRange.location != NSNotFound, NSMaxRange(charRange) <= (string as NSString).length else { return nil }
        let query = String((string as NSString).substring(with: charRange).dropFirst()).replacingOccurrences(of: "\"", with: "")
        index.pointee = -1
        return Array(tags.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }.prefix(12).map { Hashtags.command($0.name) })
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty { (placeholder as NSString).draw(at: textContainerOrigin, withAttributes: [.font: font ?? .systemFont(ofSize: 13), .foregroundColor: NSColor.placeholderTextColor]) }
    }
    func refreshAttributes() {
        guard !hasMarkedText(), let storage = textStorage else { return }
        let range = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.removeAttribute(.link, range: range)
        storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range)
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            for match in detector.matches(in: string, range: range) {
                if let url = match.url, MarkdownHTML.safeURL(url.absoluteString) != nil { storage.addAttribute(.link, value: url, range: match.range) }
            }
        }
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        for tag in tags {
            let pattern = #"(?<![\p{L}\p{N}_/])"# + NSRegularExpression.escapedPattern(for: Hashtags.command(tag.name)) + #"(?![\p{L}\p{N}_-])"#
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            for match in regex.matches(in: string, range: range) { storage.addAttribute(.foregroundColor, value: SemanticTint.color(hex: tag.color, dark: dark), range: match.range) }
        }
        storage.endEditing()
        typingAttributes = [.font: font ?? .systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor]
    }
}

struct TagTitleInput: View {
    @Binding var text: String
    let tags: [Tag]
    var fontSize: CGFloat = 20
    var placeholder = "Название"
    var autoFocus = false
    var onCommit: () -> Void = {}
    var body: some View {
        MarkdownEditor(text: $text, tags: tags, fontSize: fontSize, placeholder: placeholder, autoFocus: autoFocus, fitContent: true, onCommit: onCommit)
    }
}
