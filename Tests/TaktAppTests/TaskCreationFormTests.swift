import Foundation
import AppKit
import SwiftUI
import Testing
import TaktCore
@testable import Takt

@MainActor private final class FormFocusProbeWindow: NSWindow {
    var traversals: [String] = []
    override func selectNextKeyView(_ sender: Any?) { traversals.append("next") }
    override func selectPreviousKeyView(_ sender: Any?) { traversals.append("previous") }
}

@Test @MainActor func fullTaskDraftStartsEmptyRegardlessOfListOrQuickDraft() throws {
    let state = AppState(demo: true)
    state.data.preferences.quickDraft = "Чужой быстрый черновик !1"
    let project = try #require(state.activeProjects.first)
    let tag = try #require(state.data.tags.first)
    for scope in [Scope.inbox, .today, .week, .project(project.id), .tag(tag.id)] {
        state.scope = scope
        let draft = TaskCreationDraft()
        #expect(draft.item.title.isEmpty && draft.item.body.isEmpty)
        #expect(draft.item.projectID == nil && draft.item.schedule == .unscheduled)
        #expect(draft.item.priority == 0 && draft.item.tagIDs.isEmpty && draft.item.checklist.isEmpty)
        #expect(draft.item.recurrence == .none && draft.item.timedReminderOffsets == nil)
    }
    #expect(state.data.preferences.quickDraft == "Чужой быстрый черновик !1")
}

@Test @MainActor func smartFormTransfersCommandsAndKeepsOtherManualFields() throws {
    let project = Project(name: "Рабочий проект")
    let tag = Tag(name: "идеи")
    let calendar = Dates.calendar()
    let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 9)))
    var draft = TaskCreationDraft()
    draft.item.body = "Не разбирать описание завтра !3"
    draft.item.recurrence = .weekly
    draft.item.timedReminderOffsets = [0,15]
    draft.item.checklist = [CheckItem(title: "Первый шаг")]
    let id = draft.item.id
    draft.item.title = "🚀 Отправить план завтра в 10 !1 /\"Рабочий проект\" #идеи на 45 мин "
    draft.recognize(projects: [project], tags: [tag], now: now, calendar: calendar)
    #expect(draft.item.title == "🚀 Отправить план ")
    #expect(draft.item.priority == 1 && draft.item.projectID == project.id && draft.item.tagIDs == [tag.id])
    #expect(draft.item.duration == 45 && draft.item.schedule.isTimed)
    #expect(calendar.component(.day, from: try #require(draft.item.schedule.date)) == 15)
    #expect(calendar.component(.hour, from: try #require(draft.item.schedule.date)) == 10)
    #expect(draft.item.id == id && draft.item.body == "Не разбирать описание завтра !3")
    #expect(draft.item.recurrence == .weekly && draft.item.timedReminderOffsets == [0,15] && draft.item.checklist.count == 1)
    draft.item.priority = 3
    draft.item.title += "коллегам "
    draft.recognize(projects: [project], tags: [tag], now: now, calendar: calendar)
    #expect(draft.item.priority == 3)
    draft.item.title += "!0 "
    draft.recognize(projects: [project], tags: [tag], now: now, calendar: calendar)
    #expect(draft.item.priority == 0 && !draft.item.title.contains("!0"))
}

@Test @MainActor func smartFormLeavesInvalidUnknownAndRejectedTextIntact() {
    var draft = TaskCreationDraft()
    draft.item.title = "Проверить /неизвестный #нет 31.02.2026 !9"
    draft.recognize(projects: [], tags: [])
    #expect(draft.item.title == "Проверить /неизвестный #нет 31.02.2026 !9")
    #expect(draft.item.schedule == .unscheduled && draft.item.priority == 0)
    draft.item.title = "Дело сегодня"
    let token = QuickParser.parse(draft.item.title, projects: [], tags: []).tokens[0]
    draft.literals = [QuickLiteralToken(token)]
    draft.recognize(projects: [], tags: [])
    #expect(draft.item.title == "Дело сегодня" && draft.item.schedule == .unscheduled)
}

@Test @MainActor func smartFormWaitsForTheWholeDatePhraseWhileConsumingPriority() throws {
    let calendar = Dates.calendar()
    let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 9)))
    var draft = TaskCreationDraft()
    for word in ["План ", "12 ", "дек ", "2027 ", "в ", "10 ", "!1 "] {
        draft.item.title += word
        draft.recognize(projects: [], tags: [], now: now, calendar: calendar, finishing: false)
    }
    #expect(draft.item.priority == 1 && !draft.item.title.contains("!1"))
    #expect(draft.item.title.contains("12 дек 2027 в 10") && draft.item.schedule == .unscheduled)
    draft.recognize(projects: [], tags: [], now: now, calendar: calendar)
    let date = try #require(draft.item.schedule.date)
    #expect(draft.item.title == "План ")
    #expect(calendar.component(.year, from: date) == 2027 && calendar.component(.month, from: date) == 12)
    #expect(calendar.component(.day, from: date) == 12 && calendar.component(.hour, from: date) == 10)
}

@Test @MainActor func fullFormSubmissionDoesNotInheritContextAndCreatesOneUndoableTask() throws {
    let state = AppState(demo: true)
    let project = try #require(state.activeProjects.first)
    let tag = try #require(state.data.tags.first)
    for scope in [Scope.today, .project(project.id), .tag(tag.id)] {
        state.scope = scope
        let before = state.data.items.count
        var draft = TaskCreationDraft()
        draft.item.title = "  Новая задача  "
        draft.item.body = "Описание #новаяметка"
        draft.item.checklist = [CheckItem(title: "Подзадача")]
        draft.item.recurrence = .intervalDays; draft.item.repeatEveryDays = 4
        draft.item.allDayReminders = [AllDayReminder()]
        let id = try #require(state.capture(draft.item))
        let saved = try #require(state.item(id))
        #expect(saved.title == "Новая задача" && saved.projectID == nil && saved.schedule == .unscheduled)
        #expect(!saved.tagIDs.contains(tag.id) && saved.tagIDs.count == 1)
        #expect(saved.body == draft.item.body && saved.checklist == draft.item.checklist)
        #expect(saved.recurrence == .intervalDays && saved.repeatEveryDays == 4 && saved.allDayReminders == draft.item.allDayReminders)
        #expect(state.capture(draft.item) == nil && state.data.items.count == before + 1)
        state.undo()
        #expect(state.item(id) == nil && state.data.items.count == before)
    }
    let count = state.data.items.count
    #expect(state.capture(TaskCreationDraft().item) == nil && state.data.items.count == count)
}

@Test @MainActor func fullFormRejectsDeletedProjectWithoutMutatingTheDraftOrCreatingATask() {
    let state = AppState(demo: true)
    var draft = TaskCreationDraft()
    draft.item.title = "Не терять текст"; draft.item.projectID = UUID()
    let count = state.data.items.count
    #expect(state.capture(draft.item) == nil && state.data.items.count == count)
    #expect(draft.item.title == "Не терять текст" && state.errorMessage != nil)
}

@Test @MainActor func consumingMiddleCommandPreservesCaretAndSelectionWithEmoji() {
    let old = "🚀 План !1 коллеге", new = "🚀 План коллеге"
    let caret = ("🚀 План !1 " as NSString).length
    #expect(CaptureInputSelection.replacing(old, with: new, selection: NSRange(location: caret, length: 0)) == NSRange(location: ("🚀 План " as NSString).length, length: 0))
    #expect(CaptureInputSelection.replacing(old, with: new, selection: (old as NSString).range(of: "коллеге")) == (new as NSString).range(of: "коллеге"))
    #expect(CaptureInputSelection.replacing("", with: "План", selection: NSRange(location: 0, length: 0)) == NSRange(location: 4, length: 0))
    #expect(CaptureInputSelection.replacing("План", with: "План ", selection: NSRange(location: 4, length: 0)) == NSRange(location: 5, length: 0))
}

@Test @MainActor func fullFormMissingTagCanBeRemovedBeforeRetry() throws {
    let state = AppState(demo: true)
    var draft = TaskCreationDraft()
    draft.item.title = "Восстановить выбор"
    let missing = UUID(); draft.item.tagIDs = [missing]
    let count = state.data.items.count
    #expect(state.capture(draft.item) == nil && state.data.items.count == count)
    draft.item.tagIDs.removeAll { $0 == missing }
    #expect(state.capture(draft.item) == draft.item.id && state.data.items.count == count + 1)
}

@Test @MainActor func fullFormFailedStorageDoesNotCreateTaskOrChangeDraft() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("not-a-directory")
    try Data().write(to: file)
    let state = AppState(storageURL: file.appendingPathComponent("tasks.sqlite"))
    var draft = TaskCreationDraft(); draft.item.title = "Не потерять задачу"; draft.item.body = "Описание"
    #expect(state.capture(draft.item) == nil && state.data.items.isEmpty)
    #expect(draft.item.title == "Не потерять задачу" && draft.item.body == "Описание" && state.errorMessage != nil)
}

@Test @MainActor func pastedCompetingCommandsKeepLastChoiceAcrossRecognitionAndSave() throws {
    let first = Project(name: "Первый"), last = Project(name: "Второй")
    let raw = "План !1 !3 /Первый /Второй "
    let quick = QuickParser.parse(raw, projects: [first,last], tags: [])
    #expect(quick.priority == 3 && quick.projectID == last.id)
    #expect(quick.title.contains("!1") && quick.title.contains("/Первый"))
    var draft = TaskCreationDraft(); draft.item.title = raw
    draft.recognize(projects: [first,last], tags: [], finishing: false)
    for _ in 0..<3 { draft.recognize(projects: [first,last], tags: []) }
    #expect(draft.item.title == "План " && draft.item.priority == 3 && draft.item.projectID == last.id)
    let state = AppState(demo: true); state.data.projects += [first,last]
    let id = try #require(state.capture(draft.item))
    #expect(state.item(id)?.priority == 3 && state.item(id)?.projectID == last.id)
    draft.item.title += "!0 /Первый "
    draft.recognize(projects: [first,last], tags: [], finishing: false)
    draft.recognize(projects: [first,last], tags: [])
    #expect(draft.item.title == "План " && draft.item.priority == 0 && draft.item.projectID == first.id)
}

@Test @MainActor func formTitleTraversesFocusWhileQuickInputKeepsCompletion() {
    let editor = CaptureTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 38))
    let window = FormFocusProbeWindow(contentRect: editor.frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = editor
    editor.string = "План"
    let parsed = QuickParser.parse("План", projects: [], tags: [])
    let form = SmartCaptureInput(text: .constant("План"), literals: .constant([]), parsed: parsed, projects: [], tags: [], placeholder: "", tabMovesFocus: true, submit: {})
    let coordinator = form.makeCoordinator()
    #expect(coordinator.textView(editor, doCommandBy: #selector(NSResponder.insertTab(_:))))
    #expect(coordinator.textView(editor, doCommandBy: #selector(NSResponder.insertBacktab(_:))))
    #expect(window.traversals == ["next", "previous"] && editor.string == "План")
    var completions = 0
    let quick = SmartCaptureInput(text: .constant("План"), literals: .constant([]), parsed: parsed, projects: [], tags: [], placeholder: "", submit: {}, complete: { completions += 1; return true })
    #expect(quick.makeCoordinator().textView(editor, doCommandBy: #selector(NSResponder.insertTab(_:))))
    #expect(completions == 1 && window.traversals == ["next", "previous"])
}
