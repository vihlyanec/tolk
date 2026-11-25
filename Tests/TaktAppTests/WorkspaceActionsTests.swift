import Foundation
import Testing
import TaktCore
@testable import Takt

@Test @MainActor func creatingTaskFromADuplicateNoteLineChangesOnlyTheChosenLineAndSupportsUndo() throws {
    let state = AppState(demo: true)
    var note = Item(title: "Созвон", kind: .note)
    note.body = "## Решения\n\n* [ ] Позвонить\n\n  - [ ] Позвонить\n\nЧерновик"
    state.add(note)
    let taskID = try #require(state.createTaskFromNoteLine(noteID: note.id, sourceLine: "- [ ] Позвонить",
        occurrence: 1, title: "Позвонить", completed: false))
    #expect(state.item(taskID)?.projectID == nil)
    let link = "tolk-task://item/\(taskID.uuidString.lowercased())"
    let edited = try #require(state.item(note.id)?.body)
    #expect(edited == "## Решения\n\n* [ ] Позвонить\n\n  - [Позвонить](\(link))\n\nЧерновик")
    #expect(MarkdownHTML.body(edited).contains("href=\"\(link)\""))
    #expect(MarkdownHTML.safeURL(link) == nil)
    state.openLinkedTask(taskID)
    #expect(state.selectedID == taskID && state.scope == .inbox)
    state.undo()
    #expect(state.item(taskID) == nil && state.item(note.id)?.body == note.body)
}

@Test @MainActor func savedQueueRestoresAllFiltersAndCompactModeSurvivesTaskUndoAndReload() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("takt.sqlite")
    let state = AppState(storageURL: url)
    let project = Project(name: "Работа"), tag = Tag(name: "важное")
    state.change { $0.projects.append(project); $0.tags.append(tag) }
    state.queueProjectID = project.id; state.queueTagID = tag.id; state.queuePriority = 1
    state.queueDateFilter = "Без даты"; state.queueSearch = "отчёт"; state.queueSorting = .priority
    #expect(state.saveQueueFilter(named: " Работа "))
    state.toggleCompactTaskList()
    state.add(Item(title: "Проверка"))
    state.undo()
    let reopened = AppState(storageURL: url)
    #expect(reopened.compactTaskList)
    let filter = try #require(reopened.savedQueueFilters.first)
    reopened.applyQueueFilter(filter)
    #expect(reopened.matchesQueueFilter(filter))
    #expect(reopened.queueProjectID == project.id && reopened.queueTagID == tag.id && reopened.queuePriority == 1)
    #expect(reopened.queueDateFilter == "Без даты" && reopened.queueSearch == "отчёт" && reopened.queueSorting == .priority)
    reopened.removeQueueFilter(filter.id)
    #expect(reopened.savedQueueFilters.isEmpty)
}

@Test @MainActor func noteConversionKeepsTheFormattedSuffixAndUsesOnlyThePrefixAsTitle() throws {
    let state = AppState(demo: true)
    var note = Item(title: "Поручения", kind: .note)
    note.body = "Встреча\n\n- [ ] Позвонить **в сервис завтра** и записать ответ\n\nПосле встречи"
    state.add(note)
    let taskID = try #require(state.createTaskFromNoteLine(noteID: note.id,
        sourceLine: "- [ ] Позвонить **в сервис завтра** и записать ответ",
        occurrence: 0, title: "Позвонить в сервис", completed: false, suffix: " **завтра** и записать ответ"))
    let link = "tolk-task://item/\(taskID.uuidString.lowercased())"
    #expect(state.item(taskID)?.title == "Позвонить в сервис")
    #expect(state.item(note.id)?.body == "Встреча\n\n- [Позвонить в сервис](\(link)) **завтра** и записать ответ\n\nПосле встречи")
    state.undo()
    #expect(state.item(taskID) == nil && state.item(note.id)?.body == note.body)
}

@Test @MainActor func focusHistoryLogsCompletedPhasesOnceAndUsesSafeSpreadsheetCells() throws {
    let state = AppState(demo: true)
    let task = Item(title: "=Подготовить\tотчёт\nв срок")
    state.add(task)
    state.configureAccountFocus()
    let base = Date().addingTimeInterval(60)
    state.pomodoro.start(task, now: base)
    state.pomodoro.pause(now: base.addingTimeInterval(600))
    state.pomodoro.resume(now: base.addingTimeInterval(1_000))
    state.pomodoro.next(now: base.addingTimeInterval(1_899))
    #expect(state.focusedMinutes(for: task.id) == 0)
    state.pomodoro.next(now: base.addingTimeInterval(1_900))
    #expect(state.focusedMinutes(for: task.id) == 25)
    let completion = try #require(state.data.workspaceOptions?.completedFocus.last)
    state.recordFocusCompletion(completion)
    state.pomodoro.stop(now: base.addingTimeInterval(2_000))
    #expect(state.focusedMinutes(for: task.id) == 25)
    let table = state.taskTable([task, task])
    #expect(table.components(separatedBy: "\n").count == 2)
    #expect(table.contains("\n'=Подготовить отчёт в срок\t"))
    #expect(table.contains("\t30\t25\t"))
}

@Test @MainActor func stageEntryUsesItsSectionAndMovingByDayPreservesTheClockTime() throws {
    let state = AppState(demo: true)
    var project = Project(name: "Студия")
    project.sections = ["В работе", "Согласование"]
    state.change { $0.projects.append(project) }
    state.scope = .project(project.id)
    let emptyStage = TaskListView(state: state).displayGroups.last
    #expect(emptyStage?.id == "Согласование" && emptyStage?.items.isEmpty == true)
    let parsed = QuickParser.parse("Сверить план", projects: state.activeProjects, tags: state.data.tags)
    let id = try #require(state.capture(parsed, defaultSection: "Согласование"))
    #expect(state.item(id)?.section == "Согласование")
    let date = try #require(state.calendar.date(bySettingHour: 14, minute: 45, second: 0, of: Date()))
    state.schedule(id, at: date)
    let tomorrow = try #require(state.calendar.date(byAdding: .day, value: 1, to: date))
    state.moveTask(id, toDay: tomorrow)
    #expect(state.item(id)?.schedule == .timed(tomorrow))
    #expect(state.moveTask(id, toSection: "В работе", in: project.id))
}

@Test @MainActor func weekHeaderIncludesBothMonthsAndVirtualOccurrencesHaveTheirOwnScope() throws {
    let state = AppState(demo: true)
    let calendar = state.calendar
    let anchor = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 30)))
    #expect(CalendarDateJump.periodTitle(for: anchor, mode: "Неделя", calendar: calendar) == "30 ноября — 6 декабря")
    let friday = try #require(calendar.date(byAdding: .day, value: 4, to: anchor))
    var task = Item(title: "Повтор")
    task.recurrence = .daily
    task.schedule = .day(anchor)
    state.add(task)
    let occurrence = try #require(RecurringCalendar.occurrences(items: [task], from: anchor, to: friday, calendar: calendar).dropFirst().first)
    #expect(state.isProjectedOccurrence(occurrence))
    #expect(!state.isProjectedOccurrence(task))
    #expect(state.recurringMoveLabel(for: occurrence) == "Этот повтор")
    #expect(state.recurringMoveLabel(for: task) == "Сдвиг серии")
}
