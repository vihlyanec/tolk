import AppKit
import Foundation
import Testing
import TaktCore
@testable import Takt

@Test @MainActor func deletingArchivedProjectKeepsEveryItemAndCanBeUndone() throws {
    let state = AppState(demo: true)
    var project = Project(name: "Архив"); project.archived = true
    var task = Item(title: "Сохранить", projectID: project.id)
    task.body = "Описание"; task.schedule = .timed(Date()); task.section = "Этап"
    var note = Item(title: "Заметка", kind: .note, projectID: project.id); note.deleted = true
    state.change { $0.projects.append(project); $0.items += [task, note] }
    state.scope = .project(project.id)
    let before = state.data
    state.deleteProject(project.id)
    #expect(!state.data.projects.contains { $0.id == project.id })
    let saved = try #require(state.item(task.id))
    #expect(saved.projectID == nil && saved.section == "Без раздела" && saved.body == task.body && saved.schedule == task.schedule)
    #expect(state.item(note.id)?.deleted == true && state.item(note.id)?.projectID == nil)
    #expect(state.scope == .inbox)
    _ = try state.data.validated()
    state.undo(); #expect(state.data == before)
}

@Test @MainActor func calendarClipboardCreatesIndependentCopiesAtPointerTimeAndUndo() throws {
    let state = AppState(demo: true)
    var source = try #require(state.data.items.first { $0.kind == .task })
    source.completed = true; source.recurrence = .weekly; source.duration = 75
    source.checklist = [CheckItem(title: "Проверить")]; source.checklist[0].done = true
    source.checklist[0].tickTickID = "external-checklist"
    let board = NSPasteboard.withUniqueName()
    defer { board.releaseGlobally() }
    CalendarClipboard.write(source, to: board)
    let before = state.data, target = Date().addingTimeInterval(86400)
    #expect(state.pasteCalendarItem(at: .timed(target), from: board))
    let copy = try #require(state.selected)
    #expect(copy.id != source.id && copy.title == source.title && copy.duration == 75)
    #expect(copy.schedule == .timed(target) && !copy.completed && copy.recurrence == .none)
    #expect(copy.recurrenceSourceID == nil && copy.repeatParentID == nil)
    #expect(copy.checklist[0].id != source.checklist[0].id && !copy.checklist[0].done && copy.checklist[0].tickTickID == nil)
    #expect(state.pasteCalendarItem(at: .day(target), from: board))
    #expect(state.selected?.schedule == .day(target) && state.selected?.id != copy.id)
    state.undo(); state.undo(); #expect(state.data == before)
}

@Test @MainActor func calendarCopyDropsMissingRelationsAndExternalProviderIdentity() throws {
    var source = Item(title: "Между аккаунтами", projectID: UUID()); source.tagIDs = [UUID()]
    let copy = CalendarClipboard.copy(of: source, at: .day(Date()), in: Snapshot())
    #expect(copy.projectID == nil && copy.tagIDs.isEmpty)
    let start = Date()
    let event = ExternalEvent(calendarID: "calendar", sourceID: "source", eventID: "event", title: "Встреча", notes: "Заметка", location: "Офис", start: start, end: start.addingTimeInterval(3600))
    let task = CalendarClipboard.item(from: event)
    #expect(task.title == "Встреча" && task.duration == 60)
    #expect(task.body == "Заметка\n\nОфис" && task.recurrence == .none)
    let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
    board.setString("Обычный текст", forType: .string)
    let state = AppState(demo: true), before = state.data
    #expect(!state.pasteCalendarItem(at: .timed(Date()), from: board))
    #expect(state.data == before)
}
