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
    #expect(!state.queueInboxOnly && !state.queueHasFilters)
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
