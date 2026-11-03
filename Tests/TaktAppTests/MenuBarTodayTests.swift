import Foundation
import Testing
import TaktCore
@testable import Takt

@Test @MainActor func menuTodayIgnoresMainFiltersButExcludesHiddenOrCompletedTasks() {
    let state = AppState(demo: true)
    state.data = Snapshot()
    let day = state.calendar.startOfDay(for: Date())
    func task(_ title: String, offset: Int = 0) -> Item {
        var value = Item(title: title)
        value.schedule = .day(state.calendar.date(byAdding: .day, value: offset, to: day)!)
        return value
    }
    let overdue = task("Просроченная",offset: -1), today = task("Сегодня")
    var completed = task("Готово"); completed.completed = true
    var deleted = task("Удалена"); deleted.deleted = true
    var note = task("Заметка"); note.kind = .note
    var archive = Project(name: "Архив"); archive.archived = true
    var hidden = task("Архивная"); hidden.projectID = archive.id
    state.data.projects = [archive]
    state.data.items = [today,task("Завтра",offset: 1),Item(title: "Без даты"),completed,deleted,note,hidden,overdue]
    state.data.preferences.showCompleted = true
    state.area = .notes; state.scope = .project(archive.id); state.search = "Совсем другое"
    let before = state.data
    #expect(state.menuTodayTasks.map(\.id) == [overdue.id,today.id])
    #expect(state.area == .notes && state.scope == .project(archive.id) && state.search == "Совсем другое")
    #expect(state.data == before)
}

@Test @MainActor func menuCaptureAddsTodayToInboxWithoutChangingMainContextAndSupportsUndo() throws {
    let state = AppState(demo: true)
    state.area = .calendar; state.scope = .tag(UUID()); state.search = "Мой поиск"
    state.selectedID = state.data.items.first?.id
    let before = state.data, selection = state.selectedID, scope = state.scope
    #expect(state.captureMenuToday(" \n ") == nil)
    #expect(state.data == before)
    let id = try #require(state.captureMenuToday("  Проверить договор  "))
    let task = try #require(state.item(id))
    #expect(task.title == "Проверить договор" && task.projectID == nil && task.kind == .task)
    #expect(task.schedule == .day(state.calendar.startOfDay(for: Date())))
    #expect(state.area == .calendar && state.scope == scope && state.selectedID == selection && state.search == "Мой поиск")
    #expect(state.menuTodayTasks.contains { $0.id == id })
    state.complete(id)
    #expect(!state.menuTodayTasks.contains { $0.id == id })
    state.undo(); #expect(state.menuTodayTasks.contains { $0.id == id })
    state.undo(); #expect(state.data == before)
}

@Test @MainActor func menuTodayUsesConfiguredTimeZoneAndIncludesEndOfToday() {
    let state = AppState(demo: true); state.data = Snapshot()
    for zone in ["Europe/Moscow","Pacific/Kiritimati","America/Los_Angeles"] {
        state.data.preferences.timeZone = zone
        let tomorrow = state.calendar.date(byAdding: .day, value: 1, to: state.calendar.startOfDay(for: Date()))!
        var lastMinute = Item(title: "Поздно сегодня"); lastMinute.schedule = .timed(tomorrow.addingTimeInterval(-60))
        var nextDay = Item(title: "Завтра"); nextDay.schedule = .timed(tomorrow)
        state.data.items = [lastMinute,nextDay]
        #expect(state.menuTodayTasks.map(\.id) == [lastMinute.id])
    }
}
