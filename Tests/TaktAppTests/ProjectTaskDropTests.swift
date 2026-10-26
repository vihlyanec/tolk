import Foundation
import Testing
import TaktCore
@testable import Takt

@Test @MainActor func inboxTaskDropChangesProjectAndCountsWithoutChangingOtherFields() throws {
    let state = AppState(demo: true)
    let project = try #require(state.activeProjects.first { $0.kind == .task })
    var task = Item(title: "Перенос из входящих")
    task.body = "Описание"; task.priority = 1; task.duration = 75
    task.schedule = .timed(Date()); task.tagIDs = state.data.tags.map(\.id)
    task.checklist = [CheckItem(title: "Пункт")]
    state.add(task); state.scope = .inbox
    let before = state.data, count = state.taskCount(in: .project(project.id))
    #expect(state.visibleItems.contains { $0.id == task.id })
    #expect(state.acceptProjectDrop(task.id.uuidString, on: project.id))
    let moved = try #require(state.item(task.id))
    #expect(moved.projectID == project.id && moved.section == project.sections.first)
    #expect(moved.schedule == task.schedule && moved.duration == task.duration && moved.body == task.body)
    #expect(moved.tagIDs == task.tagIDs && moved.priority == task.priority && moved.checklist == task.checklist)
    #expect(!state.visibleItems.contains { $0.id == task.id })
    #expect(state.taskCount(in: .project(project.id)) == count + 1)
    state.undo(); #expect(state.data == before)
}
@Test @MainActor func todayTaskRemainsInTodayAfterProjectDropAndSameProjectKeepsSection() throws {
    let state = AppState(demo: true)
    var project = Project(name: "Назначение"); project.sections = ["В работу", "Позже"]
    state.change { $0.projects.append(project) }
    var task = Item(title: "Перенос сегодня"); task.schedule = .day(state.calendar.startOfDay(for: Date()))
    state.add(task); state.scope = .today
    #expect(state.acceptProjectDrop(task.id.uuidString, on: project.id))
    #expect(state.visibleItems.contains { $0.id == task.id && $0.projectID == project.id })
    state.update(task.id) { $0.section = "Позже" }
    #expect(state.acceptProjectDrop(task.id.uuidString, on: project.id))
    #expect(state.item(task.id)?.section == "Позже")
}
@Test @MainActor func projectDropStillReordersProjectsAndRejectsInvalidTaskDestinations() throws {
    let state = AppState(demo: true)
    let projects = state.activeProjects.filter { $0.kind == .task }
    let first = try #require(projects.first), last = try #require(projects.last)
    #expect(state.acceptProjectDrop("takt-project:" + last.id.uuidString, on: first.id))
    #expect(state.data.projects.first?.id == last.id)
    let task = try #require(state.data.items.first { $0.kind == .task })
    let notes = try #require(state.activeProjects.first { $0.kind == .note })
    let before = state.data
    #expect(!state.acceptProjectDrop(task.id.uuidString, on: notes.id))
    #expect(!state.acceptProjectDrop("посторонний текст", on: first.id))
    #expect(state.data == before)
}
