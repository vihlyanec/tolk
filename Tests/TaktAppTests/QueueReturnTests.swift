import Foundation
import Testing
import TaktCore
@testable import Takt

@Test @MainActor func returningCalendarTaskPreservesDateDurationAndSupportsUndo() throws {
    let state = AppState(demo: true)
    let item = try #require(state.data.items.first { $0.schedule.isTimed })
    let previous = state.data
    _ = state.beginDrag(item)
    #expect(state.returnToQueue(item.id))
    let returned = try #require(state.item(item.id))
    #expect(returned.schedule == .day(state.calendar.startOfDay(for: item.schedule.date!)))
    #expect(returned.duration == item.duration && state.draggingID == nil)
    #expect(state.queue.contains { $0.id == item.id })
    state.undo(); #expect(state.data == previous)
}
@Test @MainActor func returningToUndatedQueueClearsDateAndOtherFiltersCannotHideTask() throws {
    let state = AppState(demo: true)
    let item = try #require(state.data.items.first { $0.schedule.isTimed && $0.projectID != nil })
    state.queueDateFilter = "Без даты"; state.queueInboxOnly = true; state.queueSearch = "не совпадает"
    #expect(state.returnToQueue(item.id))
    #expect(state.item(item.id)?.schedule == .unscheduled)
    #expect(state.queue.contains { $0.id == item.id })
    #expect(state.queueInboxOnly && !state.queueHasFilters)
    #expect(state.item(item.id)?.projectID == nil && state.item(item.id)?.section == "Без раздела")
}
@Test @MainActor func withoutTimeQueueIncludesDatedAndUndatedTasksButNeverTimedTasks() throws {
    let state = AppState(demo: true)
    let timed = try #require(state.data.items.first { $0.schedule.isTimed })
    var dated = Item(title: "На дату без часа"); dated.schedule = .day(state.calendar.startOfDay(for: Date()))
    let undated = Item(title: "Совсем без даты")
    state.add(dated); state.add(undated); state.queueDateFilter = "Без времени"
    #expect(state.queue.contains { $0.id == dated.id } && state.queue.contains { $0.id == undated.id })
    #expect(!state.queue.contains { $0.id == timed.id })
    #expect(state.queue.allSatisfy { !$0.schedule.isTimed })
}

@Test @MainActor func queueDragPayloadSurvivesSessionCleanupAndSchedulesOriginalTask() async throws {
    let state = AppState(demo: true)
    let item = try #require(state.queue.first)
    let provider = state.beginDrag(item)
    // A native drop loads the provider asynchronously, after drag cleanup.
    state.endDrag()
    let payload: String? = await withCheckedContinuation { continuation in
        _ = provider.loadObject(ofClass: String.self) { value, _ in
            continuation.resume(returning: value)
        }
    }
    let id = try #require(payload.flatMap(UUID.init(uuidString:)))
    #expect(id == item.id)
    let destination = try #require(state.calendar.date(bySettingHour: 11, minute: 15, second: 0, of: Date()))
    state.schedule(id, at: destination)
    #expect(state.item(id)?.schedule == .timed(destination))
    #expect(state.item(id)?.duration == item.duration)
    #expect(!state.queue.contains { $0.id == id })
    state.undo()
    #expect(state.item(id) == item)
}

@Test @MainActor func returningToInboxAlwaysClearsDayAndProjectInOneUndoWithoutSwitchingQueue() throws {
    for filter in ["Без времени", "Без даты", "С датой", "Просрочено"] {
        let state = AppState(demo: true)
        let item = try #require(state.data.items.first { $0.schedule.isTimed && $0.projectID != nil })
        state.update(item.id) { $0.section = "В работе" }
        let before = state.data
        let original = try #require(state.item(item.id))
        state.queueInboxOnly = true; state.queueDateFilter = filter
        state.queueSearch = "Не совпадает"; state.queuePriority = (original.priority + 1) % 4
        state.calendarEditingID = item.id
        _ = state.beginDrag(original)
        #expect(state.returnToQueue(item.id))
        let returned = try #require(state.item(item.id))
        #expect(returned.projectID == nil && returned.section == "Без раздела" && returned.schedule == .unscheduled)
        #expect(returned.title == original.title && returned.body == original.body && returned.tagIDs == original.tagIDs)
        #expect(returned.priority == original.priority && returned.duration == original.duration && returned.recurrence == original.recurrence)
        #expect(state.queueInboxOnly && state.queue.contains { $0.id == item.id })
        #expect(state.draggingID == nil && state.calendarEditingID == nil)
        state.undo(); #expect(state.data == before)
        state.redo(); #expect(state.item(item.id)?.projectID == nil && state.item(item.id)?.schedule == .unscheduled)
    }
}

@Test @MainActor func asynchronousQueueDropUsesOriginalDestinationAndPreservesLaterUserSelection() async throws {
    let state = AppState(demo: true)
    let item = try #require(state.data.items.first { $0.schedule.isTimed && $0.projectID != nil })
    state.queueInboxOnly = true
    let inbox = state.queueInboxOnly, clearDate = state.queueDateFilter == "Без даты"
    let provider = state.beginDrag(item); state.endDrag()
    let payload: String? = await withCheckedContinuation { continuation in
        _ = provider.loadObject(ofClass: String.self) { value, _ in continuation.resume(returning: value) }
    }
    state.queueInboxOnly = false // User changed the view while the provider was loading.
    let id = try #require(payload.flatMap(UUID.init(uuidString:)))
    #expect(state.returnToQueue(id, intoInbox: inbox, clearDate: clearDate))
    #expect(state.item(id)?.projectID == nil && state.item(id)?.schedule == .unscheduled)
    #expect(!state.queueInboxOnly)
}
