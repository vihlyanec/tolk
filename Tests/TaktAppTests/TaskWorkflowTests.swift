import Foundation
import Testing
import TaktCore
@testable import Takt

extension Item {
    var withoutTaskActivity: Item {
        var copy = self
        copy.taskActivity = nil
        return copy
    }
}

extension Snapshot {
    var withoutTaskActivity: Snapshot {
        var copy = self
        copy.items = items.map(\.withoutTaskActivity)
        return copy
    }
}

@Test @MainActor func projectRulesMoveOnlyThatProjectsTasksAndKeepRecurringSourceStage() throws {
    let state = AppState(demo: true)
    var project = Project(name: "Заказы")
    project.sections = ["В работе", "Готово", "Проверить"]
    project.moveOnCompletion = "Готово"
    project.moveOnReopen = "Проверить"
    let other = Project(name: "Личное")
    var task = Item(title: "Подготовить смету", projectID: project.id)
    task.section = "В работе"
    task.recurrence = .daily
    task.schedule = .day(state.anchor)
    let otherTask = Item(title: "Полить цветы", projectID: other.id)
    state.data.projects = [project, other]
    state.data.items = [task, otherTask]
    state.scope = .project(project.id)

    state.complete(task.id)
    let done = try #require(state.item(task.id))
    #expect(done.section == "Готово" && done.completed && done.completedAt != nil)
    #expect(done.taskActivity?.last?.changes == ["completed", "section"])
    #expect(state.visibleItems.contains { $0.id == task.id })
    let next = try #require(state.data.items.first { $0.repeatParentID == task.id })
    #expect(next.section == "В работе" && next.completedAt == nil && next.taskActivity == nil)
    state.undo()
    #expect(state.item(task.id)?.section == "В работе" && state.item(task.id)?.completedAt == nil)
    #expect(state.item(task.id)?.taskActivity?.flatMap(\.changes) == ["completed", "section", "reopened", "section"])
    #expect(!state.data.items.contains { $0.id == next.id })

    state.redo()
    state.complete(task.id)
    #expect(state.item(task.id)?.section == "Проверить" && state.item(task.id)?.completed == false)
    state.complete(otherTask.id)
    #expect(state.item(otherTask.id)?.section == "Без раздела")
}

@Test @MainActor func wontDoOnlyClosesOneOccurrenceAndEntersItsOwnList() throws {
    let state = AppState(demo: true)
    var task = Item(title: "Отправить письмо")
    task.schedule = .timed(Date().addingTimeInterval(3600))
    task.timedReminderOffsets = [0]
    task.recurrence = .daily
    state.data.items = [task]
    state.anchor = task.schedule.date!
    state.toggleWontDo(task.id)

    let skipped = try #require(state.item(task.id))
    #expect(skipped.wontDoAt != nil && !skipped.completed)
    #expect(!state.visibleItems.contains { $0.id == task.id })
    #expect(!state.calendarItems.contains { $0.id == task.id })
    #expect(!NotificationPlan.events(snapshot: state.data).contains { $0.itemID == task.id })
    #expect(state.taskCount(in: .wontDo) == 1 && state.taskCount(in: .completed) == 0)
    #expect(state.data.items.filter { $0.repeatParentID == task.id && $0.isActiveTask }.count == 1)
    state.scope = .wontDo
    #expect(state.visibleItems.map(\.id) == [task.id])
    state.toggleWontDo(task.id)
    #expect(state.visibleItems.isEmpty)
    #expect(state.item(task.id)?.taskActivity?.map(\.changes) == [["wontDo"], ["reopened"]])
    state.undo()
    #expect(state.visibleItems.map(\.id) == [task.id])
    state.undo()
    #expect(state.data.items.map(\.id) == [task.id])
    #expect(state.item(task.id)?.isActiveTask == true)
}

@Test @MainActor func taskDescriptionLinksCopyTheirExactTextAndSkipEmailCodeAndFences() throws {
    let value = " текст + & 100% 💡 "
    let url = try #require(MarkdownHTML.copyURL(value))
    #expect(MarkdownHTML.copyText(from: url) == value)
    let html = MarkdownHTML.body("Код: `\(value)`. @vihlyanec и a@sample.test\n\n```\n@example\n```\n\n`@person`", taskLinks: true)
    #expect(html.contains("https://t.me/vihlyanec"))
    #expect(html.components(separatedBy: "https://t.me/").count == 2)
    #expect(html.components(separatedBy: "class=\"copy-code\"").count == 3)
    #expect(!MarkdownHTML.body("@vihlyanec и `текст`").contains("href"))
}
