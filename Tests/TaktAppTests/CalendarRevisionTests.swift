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

@Test @MainActor func notificationRefreshReplacesOldThumbnailFormatWithoutChangingIdentity() throws {
    var snapshot = Snapshot()
    var item = Item(title: "Проверка формата"); item.schedule = .timed(Date().addingTimeInterval(3600)); item.timedReminderOffsets = [0]
    snapshot.items = [item]
    let reminder = try #require(NotificationPlan.events(snapshot: snapshot).first)
    let content = Reminders.content(for: reminder)
    #expect(content.attachments.isEmpty)
    #expect(content.userInfo["formatVersion"] as? Int == 3)
    let current = UNNotificationRequest(identifier: reminder.identifier, content: content, trigger: nil)
    #expect(Reminders.isCurrent(current, for: reminder))
    let old = try #require(content.mutableCopy() as? UNMutableNotificationContent)
    old.userInfo["formatVersion"] = 2
    #expect(!Reminders.isCurrent(UNNotificationRequest(identifier: reminder.identifier, content: old, trigger: nil), for: reminder))
    old.userInfo["formatVersion"] = 3; old.title = "Старое название"
    #expect(!Reminders.isCurrent(UNNotificationRequest(identifier: reminder.identifier, content: old, trigger: nil), for: reminder))
    old.title = reminder.title
    let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/BrandIcon.png")
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("tolk-attachment-regression-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let copy = directory.appendingPathComponent("old-logo.png")
    try FileManager.default.copyItem(at: source, to: copy)
    old.attachments = [try UNNotificationAttachment(identifier: "old-logo", url: copy)]
    #expect(!Reminders.isCurrent(UNNotificationRequest(identifier: reminder.identifier, content: old, trigger: nil), for: reminder))
}

@Test @MainActor func recurringDeletionRequiresChoiceAndCanBeCancelled() throws {
    let state = AppState(demo: true)
    let task = try #require(state.data.items.first { $0.schedule.isTimed })
    state.update(task.id) { $0.recurrence = .daily }
    let before = state.data
    state.delete(task.id)
    #expect(state.pendingRecurringDeletion?.id == task.id)
    #expect(state.data == before)
    state.pendingRecurringDeletion = nil
    #expect(state.data == before)
    state.delete(task.id); state.confirmRecurringDeletion(following: false)
    #expect(state.data.items.first { $0.id == task.id }?.deleted == true)
    #expect(state.calendarItems.contains { $0.recurrenceSourceID == task.id && !$0.deleted })
    state.undo()
    #expect(state.data == before)
}

@Test @MainActor func deletingFutureSeriesKeepsHistoryAndStopsProjectionAndCompletion() throws {
    let state = AppState(demo: true)
    var root = Item(title: "Цепочка"); root.recurrence = .daily
    root.schedule = .timed(state.calendar.startOfDay(for: state.anchor).addingTimeInterval(6 * 3600))
    state.data.items = [root]
    let next = try #require(RecurringCalendar.next(root, in: [root], calendar: state.calendar))
    let later = try #require(RecurringCalendar.next(next, in: [root, next], calendar: state.calendar))
    state.add(later)
    let before = state.data
    state.delete(next.id); state.confirmRecurringDeletion(following: true)
    #expect(state.data.items.first { $0.id == root.id }?.deleted == false)
    #expect(state.data.items.first { $0.id == later.id }?.deleted == true)
    #expect(state.calendarItems.map(\.id) == [root.id])
    state.complete(root.id)
    #expect(state.calendarItems.map(\.id) == [root.id])
    let saved = try JSONDecoder().decode(Snapshot.self, from: JSONEncoder().encode(state.data))
    #expect(saved.items.first { $0.id == root.id }?.recurrenceEndDate == next.schedule.date)
    state.undo(); state.undo()
    #expect(state.data == before)
    state.delete(root.id); state.confirmRecurringDeletion(following: true)
    #expect(state.calendarItems.isEmpty)
    #expect(state.data.items.allSatisfy { $0.deleted })
}

@Test @MainActor func deletingMovedOccurrenceUsesOriginalSeriesDate() throws {
    let state = AppState(demo: true)
    var root = Item(title: "Перенос"); root.recurrence = .daily
    root.schedule = .day(state.calendar.startOfDay(for: state.anchor))
    state.data.items = [root]
    var moved = try #require(RecurringCalendar.next(root, in: [root], calendar: state.calendar))
    let original = try #require(moved.schedule.date)
    moved.schedule = .day(state.calendar.date(byAdding: .day, value: -1, to: original)!)
    state.add(moved)
    state.delete(moved.id); state.confirmRecurringDeletion(following: true)
    #expect(state.data.items.first { $0.id == root.id }?.recurrenceEndDate == original)
    #expect(state.calendarItems.map(\.id) == [root.id])
}
