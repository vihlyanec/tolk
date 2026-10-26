import Foundation
import AppKit
import SwiftUI
import Testing
import TaktCore
@testable import Takt

@MainActor private final class CaptureDraftBox {
    var text = "Дело сегодня"
    var literals: [QuickLiteralToken] = []
    var submissions = 0
    func input() -> SmartCaptureInput {
        SmartCaptureInput(text: Binding(get: { self.text }, set: { self.text = $0 }), literals: Binding(get: { self.literals }, set: { self.literals = $0 }), parsed: QuickParser.parse(text, projects: [], tags: []), projects: [], tags: [], placeholder: "", submit: { self.submissions += 1 })
    }
}

@Test @MainActor func firstBackspaceRemovesSemanticsAndNextBackspaceEditsCharacters() throws {
    let draft = CaptureDraftBox(), view = CaptureTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 32))
    view.string = draft.text; view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
    let coordinator = draft.input().makeCoordinator()
    coordinator.highlight(view)
    let index = ("Дело " as NSString).length
    #expect(view.textStorage?.attribute(.backgroundColor, at: index, effectiveRange: nil) != nil)
    #expect(coordinator.textView(view, doCommandBy: #selector(NSResponder.deleteBackward(_:))))
    #expect(view.string == "Дело сегодня" && draft.text == view.string)
    #expect(draft.literals.count == 1 && draft.submissions == 0)
    #expect(view.textStorage?.attribute(.backgroundColor, at: index, effectiveRange: nil) == nil)
    #expect(!coordinator.textView(view, doCommandBy: #selector(NSResponder.deleteBackward(_:))))
    let parsed = QuickParser.parse(draft.text, projects: [], tags: [], literalRanges: QuickLiteralToken.ranges(draft.literals, in: draft.text))
    #expect(parsed.title == "Дело сегодня" && parsed.schedule == .unscheduled)
}

@Test @MainActor func spaceAndSelectedTextUseNormalEditingWithoutRejectingACommand() {
    let draft = CaptureDraftBox(), view = CaptureTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 32))
    view.string = draft.text; view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
    let coordinator = draft.input().makeCoordinator()
    #expect(!coordinator.textView(view, doCommandBy: #selector(NSResponder.insertText(_:))))
    #expect(draft.literals.isEmpty)
    view.string += " "
    coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: view))
    #expect(draft.literals.isEmpty)
    #expect(QuickParser.parse(draft.text, projects: [], tags: []).tokens.count == 1)
    view.setSelectedRange(NSRange(location: 0, length: (view.string as NSString).length))
    #expect(!coordinator.textView(view, doCommandBy: #selector(NSResponder.deleteBackward(_:))))
}
