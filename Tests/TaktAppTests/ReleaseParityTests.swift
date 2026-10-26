import Foundation
import Testing
import TaktCore
@testable import Takt

@Test @MainActor func projectsCanMoveDownPastTargetAndBackUpWithOneUndo() throws {
    let state = AppState(demo: true)
    let first = try #require(state.activeProjects.first)
    let second = try #require(state.activeProjects.dropFirst().first)
    let before = state.data
    #expect(state.acceptProjectDrop("takt-project:" + first.id.uuidString, on: second.id, after: true))
    #expect(state.activeProjects.first?.id == second.id)
    #expect(state.activeProjects.dropFirst().first?.id == first.id)
    state.undo(); #expect(state.data == before)
    #expect(state.acceptProjectDrop("takt-project:" + second.id.uuidString, on: first.id, after: false))
    #expect(state.activeProjects.first?.id == second.id)
}

@Test @MainActor func aTagListsNotesAndTasksAndProjectGroupingDoesNotDropNotes() throws {
    let state = AppState(demo: true)
    let tag = try #require(state.data.tags.first)
    let project = try #require(state.activeProjects.first { $0.kind == .note })
    var note = Item(title: "Заметка с тегом", kind: .note); note.projectID = project.id
    state.add(note); state.update(note.id) { $0.body = "Текст #" + tag.name }
    var task = Item(title: "Задача с тегом"); task.tagIDs = [tag.id]; state.add(task)
    state.area = .tasks; state.filterByTag(tag.id)
    #expect(state.visibleItems.contains { $0.id == note.id })
    #expect(state.visibleItems.contains { $0.id == task.id })
    #expect(state.taskCount(in: .tag(tag.id)) == state.visibleItems.filter { !$0.completed }.count)
    state.grouping = .project
    #expect(state.groups.flatMap(\.items).contains { $0.id == note.id })
    state.select(note.id)
    #expect(state.area == .notes && state.notes().contains { $0.id == note.id })
    #expect(state.selectedID == note.id)
    let newID = state.createNote()
    #expect(state.item(newID)?.tagIDs == [tag.id])
    #expect(state.notes().contains { $0.id == newID })
}

@Test @MainActor func finishingRichNoteCommitsFinalHashtagWithoutCreatingPartialTags() throws {
    let state = AppState(demo: true)
    let id = state.createNote()
    let before = state.data.tags.count
    state.update(id) { $0.body = "#новый" }
    #expect(state.data.tags.count == before)
    state.update(id) { $0.body = "#новыйтег" }
    #expect(state.data.tags.count == before)
    state.commitHashtags(id)
    let tag = try #require(state.data.tags.first { $0.name == "новыйтег" })
    #expect(state.item(id)?.tagIDs == [tag.id])
    #expect(state.data.tags.count == before + 1)
    state.filterByTag(tag.id)
    #expect(state.notes().contains { $0.id == id })
    state.commitHashtags(id)
    #expect(state.data.tags.count == before + 1)
}

@Test @MainActor func oldNoteHashtagsAreSearchableWithoutEditingOrMigratingRecords() throws {
    let state = AppState(demo: true)
    let tag = try #require(state.data.tags.first)
    var note = Item(title: "Старая заметка", kind: .note)
    note.body = "Запись #" + tag.name
    state.add(note) // Simulate a legacy record with empty stored tagIDs.
    let before = state.data
    state.area = .tasks; state.filterByTag(tag.id)
    #expect(state.visibleItems.contains { $0.id == note.id })
    #expect(state.matchesQuery(note, "#" + tag.name))
    #expect(state.notes().contains { $0.id == note.id })
    #expect(state.data == before)
    state.grouping = .tag
    #expect(state.groups.flatMap(\.items).contains { $0.id == note.id })
}

@Test @MainActor func submittingDescriptionFinishesLastHashtagInSameUndoStep() throws {
    let state = AppState(demo: true), before = state.data
    let id = try #require(state.capture(QuickParser.parse("С описанием", projects: [], tags: []), body: "Детали #конечныйтег"))
    let tag = try #require(state.data.tags.first { $0.name == "конечныйтег" })
    #expect(state.item(id)?.tagIDs == [tag.id])
    state.undo(); #expect(state.data == before)
}
