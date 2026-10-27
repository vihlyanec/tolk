import Foundation
import AppKit
import SwiftUI
import Testing
import TaktCore
@testable import Takt

@Test @MainActor func demoKanbanImportGroupsTasksAndLocalMoveSurvivesRefreshAndUndo() throws {
    let state = AppState(demo: true)
    let remote = TickTickProject(["id": .string("qa-board"), "name": .string("Канбан TickTick · проверка"), "viewMode": .string("kanban")])
    let columns = [TickTickColumn(id: "a", projectId: remote.id, name: "В работе", sortOrder: 0),
                   TickTickColumn(id: "b", projectId: remote.id, name: "В работе", sortOrder: 1),
                   TickTickColumn(id: "c", projectId: remote.id, name: "Готово к обсуждению с командой", sortOrder: 2)]
    let tasks = columns.enumerated().map { i, column in
        TickTickTask(["id": .string("qa-task-\(i)"), "projectId": .string(remote.id), "title": .string(["Подготовить макет", "Проверить договор", "Обсудить следующий шаг"][i]), "columnId": .string(column.id)])
    }
    state.change(undo: false) { snapshot in
        snapshot.tickTick = TickTickSyncState(connectionID: UUID())
        SyncEngine.ingest(projects: [remote], tasks: tasks, inboxIDs: ["inbox"], columns: [remote.id: columns], into: &snapshot)
    }
    let project = try #require(state.data.projects.first { $0.name == remote.name })
    state.area = .tasks; state.scope = .project(project.id); state.grouping = .section
    #expect(state.groups.map(\.id) == ["В работе", "В работе (TickTick 2)", "Готово к обсуждению с командой"])
    let item = try #require(state.visibleItems.first { $0.title == "Подготовить макет" })
    state.update(item.id) { $0.section = "В работе (TickTick 2)" }
    #expect(state.data.tickTick?.outbox.isEmpty == true)
    state.change(undo: false) { SyncEngine.ingest(projects: [remote], tasks: tasks, inboxIDs: ["inbox"], columns: [remote.id: columns], into: &$0) }
    #expect(state.item(item.id)?.section == "В работе (TickTick 2)")
    state.undo()
    #expect(state.item(item.id)?.section == "В работе")
    #expect(state.groups.count == 3 && state.data.tickTick != nil)
    // Optional visual QA artifact; normal test runs do not write screenshots.
    if let output = ProcessInfo.processInfo.environment["TOLK_KANBAN_QA_OUTPUT"] {
        let root = NSHostingView(rootView: MainView(state: state).frame(width: 1440, height: 880).environment(\.colorScheme, .dark))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1440, height: 880), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua); window.contentView = root
        root.frame = window.contentLayoutRect; root.layoutSubtreeIfNeeded(); window.displayIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2)); root.layoutSubtreeIfNeeded()
        let bitmap = try #require(root.bitmapImageRepForCachingDisplay(in: root.bounds))
        root.cacheDisplay(in: root.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: output))
        window.contentView = nil
    }
}

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
