import Foundation
import Testing
import TaktCore
@testable import Takt

@Test @MainActor func demoNeverConnectsRealProvidersAndImportedCompletionDoesNotDuplicate() async throws {
    let state = AppState(demo: true)
    let coordinator = SyncCoordinator(state: state)
    coordinator.start(); coordinator.connectApple(); coordinator.previewTickTick(token: "fixture")
    #expect(!coordinator.appleBusy && !coordinator.tickTickBusy && coordinator.preview == nil)
    state.change(undo: false) { snapshot in
        snapshot.tickTick = TickTickSyncState(connectionID: UUID())
        SyncEngine.ingest(projects: [], tasks: [TickTickTask(["id": .string("r1"), "projectId": .string("inbox"), "title": .string("Из TickTick"), "repeatFlag": .string("RRULE:FREQ=DAILY"), "startDate": .string(TickTickCodec.stamp(Date())), "status": .number(0)])], inboxIDs: ["inbox"], into: &snapshot)
    }
    let item = try #require(state.data.items.first { $0.title == "Из TickTick" })
    let count = state.data.items.count
    state.complete(item.id)
    #expect(state.data.items.count == count)
    #expect(state.data.tickTick?.outbox[item.id.uuidString]?.task.completed == true)
    state.undo()
    #expect(state.data.items.first { $0.id == item.id }?.completed == false)
    #expect(state.data.tickTick != nil)
}
@Test @MainActor func undoAfterIncomingSyncRestoresOnlyUserAction() throws {
    let state = AppState(demo: true)
    let item = try #require(state.data.items.first)
    state.update(item.id) { $0.title = "Моя правка" }
    state.change(undo: false) { s in
        s.items.append(Item(title: "Удалённая новая")); s.appleCalendar = AppleCalendarState()
        if let i = s.items.firstIndex(where: { $0.id == item.id }) { s.items[i].body = "Входящие данные" }
    }
    state.undo()
    #expect(state.data.items.first { $0.id == item.id }?.title == item.title)
    #expect(state.data.items.first { $0.id == item.id }?.body == "Входящие данные")
    #expect(state.data.items.contains { $0.title == "Удалённая новая" } && state.data.appleCalendar != nil)
    state.redo()
    #expect(state.data.items.first { $0.id == item.id }?.title == "Моя правка")
    #expect(state.data.items.first { $0.id == item.id }?.body == "Входящие данные")
}
@Test @MainActor func externalAppleEventsAreNeverTasksOrPlanningQueueItems() throws {
    let state = AppState(demo: true)
    let before = state.data.items.count
    var connection = AppleCalendarState(); connection.selected = ["a"]
    connection.calendars = [ExternalCalendar(id: "a", sourceID: "s", name: "Тестовый", account: "Demo", color: "598BFF")]
    let event = ExternalEvent(calendarID: "a", sourceID: "s", eventID: "1", title: "Внешнее событие", start: Date(), end: Date().addingTimeInterval(3600))
    connection.replace(AppleCalendarWindow(start: Date().addingTimeInterval(-86400), end: Date().addingTimeInterval(86400), events: [event]))
    state.change(undo: false) { $0.appleCalendar = connection }
    #expect(state.externalEvents.count == 1 && state.data.items.count == before)
    #expect(state.item(event.id) == nil && !state.queue.contains { $0.id == event.id })
    state.complete(event.id)
    #expect(state.data.items.count == before)
}
