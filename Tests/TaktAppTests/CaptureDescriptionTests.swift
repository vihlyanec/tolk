import AppKit
import Foundation
import Testing
import TaktCore
@testable import Takt

@MainActor private func returnKey(_ flags: NSEvent.ModifierFlags, code: UInt16 = 36) throws -> NSEvent {
    try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: code))
}

@Test @MainActor func shiftReturnOpensDescriptionWithoutInsertingText() throws {
    let view = CaptureTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 32))
    view.string = "Задача завтра"
    var opens = 0
    view.onShiftReturn = { opens += 1 }
    view.keyDown(with: try returnKey(.shift))
    #expect(opens == 1 && view.string == "Задача завтра")
    view.keyDown(with: try returnKey(.shift, code: 76))
    #expect(opens == 2 && view.string == "Задача завтра")
}

@Test @MainActor func commandReturnSavesDescriptionWhileOrdinaryReturnMakesANewLine() throws {
    let view = TagTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 120))
    view.string = "Первая строка"
    view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
    var saves = 0
    view.onCommandReturn = { saves += 1 }
    view.insertNewline(nil)
    #expect(saves == 0 && view.string == "Первая строка\n")
    view.keyDown(with: try returnKey(.command))
    #expect(saves == 1 && view.string == "Первая строка\n")
}

@Test @MainActor func descriptionIsSavedWithExactlyOneTaskAndDraftRoundTrips() throws {
    let state = AppState(demo: true)
    let count = state.data.items.count
    let body = "Первая строка\n\n**Подробности** и https://example.com"
    let parsed = QuickParser.parse("Подготовить завтра", projects: [], tags: [], calendar: state.calendar)
    let id = try #require(state.capture(parsed, body: body))
    let item = try #require(state.data.items.first { $0.id == id })
    #expect(state.data.items.count == count + 1)
    #expect(item.body == body && item.title == "Подготовить" && item.schedule == parsed.schedule)
    var preferences = Preferences()
    preferences.quickDraft = "Подготовить завтра"; preferences.quickDraftBody = body; preferences.quickDraftDescriptionExpanded = true
    let restored = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences))
    #expect(restored.quickDraftBody == body && restored.quickDraftDescriptionExpanded == true)
    let old = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(Preferences()))
    #expect(old.quickDraftBody == nil && old.quickDraftDescriptionExpanded == nil)
}

@Test @MainActor func captureDescriptionTagsAndTaskAreOneUndoableChange() throws {
    let state = AppState(demo: true)
    let count = state.data.items.count, tags = state.data.tags.count
    let id = try #require(state.capture(QuickParser.parse("Задача", projects: [], tags: []), body: "Описание #новыйтег "))
    let tag = try #require(state.data.tags.first { $0.name == "новыйтег" })
    #expect(state.data.items.first { $0.id == id }?.tagIDs == [tag.id])
    state.undo()
    #expect(state.data.items.count == count && state.data.tags.count == tags)
}
