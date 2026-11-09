import Foundation
import Testing
import UserNotifications
import TaktCore
@testable import Takt

@Test @MainActor func focusActionOnlyAppearsAtTimedTaskStart() throws {
    let now = Date()
    var snapshot = Snapshot()
    var task = Item(title: "Начало события")
    task.schedule = .timed(now.addingTimeInterval(3600)); task.timedReminderOffsets = [15, 0]
    snapshot.items = [task]
    let plans = NotificationPlan.events(snapshot: snapshot, now: now)
    #expect(plans.count == 2)
    #expect(plans.filter(\.isStart).count == 1)
    for plan in plans {
        let content = Reminders.content(for: plan)
        #expect(content.categoryIdentifier == (plan.isStart ? Reminders.focusCategory : ""))
        #expect(Reminders.isCurrent(UNNotificationRequest(identifier: plan.identifier, content: content, trigger: nil), for: plan))
        if plan.isStart {
            let old = try #require(content.mutableCopy() as? UNMutableNotificationContent)
            old.categoryIdentifier = ""
            #expect(!Reminders.isCurrent(UNNotificationRequest(identifier: plan.identifier, content: old, trigger: nil), for: plan))
        }
    }
    // No new notification is invented when reminders were explicitly disabled.
    task.timedReminderOffsets = []; snapshot.items = [task]
    #expect(NotificationPlan.events(snapshot: snapshot, now: now).isEmpty)
    task.schedule = .day(now.addingTimeInterval(86400)); task.allDayReminders = [AllDayReminder()]
    snapshot.items = [task]
    #expect(NotificationPlan.events(snapshot: snapshot, now: now).allSatisfy { !$0.isStart })
}

@Test @MainActor func notificationFocusUsesCurrentRecordAndDoesNotRestartAnActiveSession() throws {
    let state = AppState(demo: true)
    let task = Item(title: "Задача из уведомления")
    state.add(task)
    #expect(state.focusFromNotification(task.id))
    let started = try #require(state.pomodoro.session)
    #expect(started.taskID == task.id && started.deadline != nil)
    #expect(state.focusFromNotification(task.id))
    #expect(state.pomodoro.session == started)
    state.pomodoro.pause()
    let remaining = state.pomodoro.session?.remaining
    #expect(state.focusFromNotification(task.id))
    #expect(state.pomodoro.session?.deadline != nil && state.pomodoro.session?.remaining == remaining)
    #expect(!state.pomodoro.pausePrompt)
    var second = Item(title: "Другой сеанс")
    state.add(second)
    #expect(state.focusFromNotification(second.id))
    #expect(state.pendingFocusTask?.id == second.id)
    #expect(state.pomodoro.session?.taskID == task.id)
    state.pendingFocusTask = nil
    second.completed = true
    state.update(second.id) { $0.completed = true }
    #expect(!state.focusFromNotification(second.id))
    state.update(second.id) { $0.completed = false; $0.deleted = true }
    #expect(!state.focusFromNotification(second.id))
    let note = Item(title: "Заметка", kind: .note)
    state.add(note)
    #expect(!state.focusFromNotification(note.id))
    #expect(!state.focusFromNotification(UUID()))
    #expect(state.pomodoro.session?.taskID == task.id)
}
