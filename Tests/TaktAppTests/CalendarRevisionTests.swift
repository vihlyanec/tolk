import Foundation
import Testing
import UserNotifications
import TaktCore
@testable import Takt

@Test @MainActor func calendarRetainsCompletedTasksIndependentlyOfListPreference() throws {
    let state = AppState(demo: true)
    state.scope = .inbox; state.data.preferences.showCompleted = false
    let task = try #require(state.data.items.first { $0.kind == .task && $0.schedule.isTimed })
    state.anchor = task.schedule.date!
    state.complete(task.id)
    #expect(state.calendarItems.contains { $0.id == task.id && $0.completed })
    #expect(!state.visibleItems.contains { $0.id == task.id })
    state.complete(task.id)
    #expect(state.calendarItems.contains { $0.id == task.id && !$0.completed })
}
@Test @MainActor func futureOccurrenceCanBeEditedCompletedAndUndone() throws {
    let state = AppState(demo: true)
    let source = try #require(state.data.items.first { $0.schedule.isTimed })
    state.update(source.id) { $0.recurrence = .weekly }
    state.anchor = state.calendar.date(byAdding: .day, value: 7, to: source.schedule.date!)!
    let initial = state.data
    let future = try #require(state.calendarItems.first { $0.recurrenceSourceID == source.id })
    state.selectCalendar(future.id)
    #expect(state.data == initial) // Merely opening the card does not create records.
    state.update(future.id) { $0.title = "Изменённый повтор" }
    #expect(state.data.items.contains { $0.id == future.id && $0.title == "Изменённый повтор" })
    #expect(state.data.items.first { $0.id == source.id }?.title == source.title)
    state.complete(future.id)
    #expect(state.calendarItems.filter { $0.id == future.id }.count == 1)
    #expect(state.calendarItems.contains { $0.id == future.id && $0.completed })
    state.undo(); state.undo()
    #expect(state.data == initial)
    #expect(state.calendarItems.contains { $0.id == future.id && !$0.completed })
}
@Test @MainActor func notificationContentHasSoundAndStableTaskIdentity() throws {
    var snapshot = Snapshot()
    var item = Item(title: "Проверка уведомления"); item.schedule = .timed(Date().addingTimeInterval(3600)); item.timedReminderOffsets = [0,0]
    snapshot.items = [item]
    let plans = NotificationPlan.events(snapshot: snapshot)
    #expect(plans.count == 1)
    let plan = try #require(plans.first)
    let content = Reminders.content(for: plan)
    #expect(content.sound != nil && content.title == item.title)
    #expect(content.userInfo["eventKey"] as? String == plan.identifier)
    #expect(content.threadIdentifier == "task-" + item.id.uuidString)
}

@Test @MainActor func everyNotificationOwnsItsAttachmentFile() throws {
    let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/BrandIcon.png")
    let first = try #require(Reminders.makeLogo(source: source))
    let second = try #require(Reminders.makeLogo(source: source))
    defer { try? FileManager.default.removeItem(at: first.url); try? FileManager.default.removeItem(at: second.url) }
    #expect(first.url != second.url)
    try FileManager.default.removeItem(at: first.url) // The notification service consumes the first file.
    #expect(FileManager.default.fileExists(atPath: second.url.path))
    #expect(FileManager.default.fileExists(atPath: source.path))
}
