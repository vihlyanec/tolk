import Foundation
import Testing
@testable import TaktCore

private let recurrenceCalendar = Dates.calendar()
private func recurrenceDate(_ day: Int, month: Int = 10, hour: Int = 12) -> Date {
    recurrenceCalendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
}
@Test func futureWeeklyOccurrencesAreStableWithoutChangingRecords() throws {
    var task = Item(title: "Еженедельная встреча")
    task.schedule = .timed(recurrenceDate(26)); task.recurrence = .weekly
    let items = [task], lower = recurrenceDate(1, month: 11, hour: 0), upper = recurrenceDate(9, month: 11, hour: 0)
    let values = RecurringCalendar.occurrences(items: items, from: lower, to: upper, calendar: recurrenceCalendar)
    let next = try #require(values.first)
    #expect(values.count == 1 && next.schedule.date == recurrenceDate(2, month: 11))
    #expect(next.id == RecurringCalendar.occurrences(items: items, from: lower, to: upper, calendar: recurrenceCalendar).first?.id)
    #expect(next.recurrenceSourceID == task.id && next.recurrenceOriginalDate == next.schedule.date)
    #expect(items == [task])
}
@Test func completedRecurringRootAndLegacyChildProduceOneOccurrencePerDate() throws {
    var root = Item(title: "Старая серия"); root.schedule = .timed(recurrenceDate(19)); root.recurrence = .weekly; root.completed = true
    let child = try #require(Dates.nextOccurrence(root, calendar: recurrenceCalendar))
    let values = RecurringCalendar.occurrences(items: [root, child], from: recurrenceDate(18), to: recurrenceDate(4, month: 11), calendar: recurrenceCalendar)
    #expect(values.count == 3)
    #expect(values.filter { $0.schedule.date == child.schedule.date }.count == 1)
    #expect(values.contains { $0.id == root.id && $0.completed })
}
@Test func movedDeletedAndCompletedExceptionsDoNotReappearOrDuplicate() throws {
    var root = Item(title: "Каждый день"); root.schedule = .day(recurrenceDate(26, hour: 0)); root.recurrence = .daily
    var moved = try #require(RecurringCalendar.next(root, in: [root], calendar: recurrenceCalendar))
    moved.schedule = .day(recurrenceDate(30, hour: 0))
    var deleted = try #require(RecurringCalendar.next(moved, in: [root, moved], calendar: recurrenceCalendar)); deleted.deleted = true
    var completed = try #require(RecurringCalendar.next(deleted, in: [root, moved, deleted], calendar: recurrenceCalendar)); completed.completed = true
    let items = [root, moved, deleted, completed]
    let values = RecurringCalendar.occurrences(items: items, from: recurrenceDate(26, hour: 0), to: recurrenceDate(31, hour: 0), calendar: recurrenceCalendar)
    #expect(!values.contains { $0.schedule.date == recurrenceDate(27, hour: 0) || $0.schedule.date == recurrenceDate(28, hour: 0) })
    #expect(values.contains { $0.id == completed.id && $0.completed })
    #expect(values.filter { $0.id == moved.id }.count == 1)
    #expect(Set(values.map(\.id)).count == values.count)
}
@Test func intervalAndWeekdayProjectionsRespectCalendarRules() {
    var interval = Item(title: "Интервал"); interval.recurrence = .intervalDays; interval.repeatEveryDays = 3; interval.schedule = .timed(recurrenceDate(26))
    var weekdays = Item(title: "Будни"); weekdays.recurrence = .weekdays; weekdays.schedule = .timed(recurrenceDate(30))
    let values = RecurringCalendar.occurrences(items: [interval, weekdays], from: recurrenceDate(1, month: 11, hour: 0), to: recurrenceDate(5, month: 11, hour: 0), calendar: recurrenceCalendar)
    #expect(values.filter { $0.title == "Интервал" }.map(\.schedule.date) == [recurrenceDate(1, month: 11), recurrenceDate(4, month: 11)])
    #expect(values.filter { $0.title == "Будни" }.count == 3)
}

@Test func earlyCalendarTasksExpandOnlyTheDisplayedPeriod() {
    var task = Item(title: "Рано"); task.schedule = .timed(recurrenceDate(26, hour: 5))
    #expect(CalendarLayout.startHour(preferred: 9, days: [recurrenceDate(26)], items: [task], calendar: recurrenceCalendar) == 5)
    #expect(CalendarLayout.startHour(preferred: 9, days: [recurrenceDate(27)], items: [task], calendar: recurrenceCalendar) == 9)
    task.deleted = true
    #expect(CalendarLayout.startHour(preferred: 9, days: [recurrenceDate(26)], items: [task], calendar: recurrenceCalendar) == 9)
    task.deleted = false; task.schedule = .day(recurrenceDate(26))
    #expect(CalendarLayout.startHour(preferred: 9, days: [recurrenceDate(26)], items: [task], calendar: recurrenceCalendar) == 9)
    task.schedule = .timed(recurrenceDate(26, hour: 23)); task.duration = 120
    #expect(CalendarLayout.startHour(preferred: 9, days: [recurrenceDate(27)], items: [task], calendar: recurrenceCalendar) == 0)
}

@Test func deletingOneRootOccurrencePreservesFutureProjection() throws {
    var root = Item(title: "Повтор"); root.recurrence = .daily; root.schedule = .timed(recurrenceDate(26)); root.deleted = true
    let values = RecurringCalendar.occurrences(items: [root], from: recurrenceDate(26, hour: 0), to: recurrenceDate(29, hour: 0), calendar: recurrenceCalendar)
    #expect(values.count == 2)
    #expect(!values.contains { $0.id == root.id })
    root.recurrenceEndDate = recurrenceDate(27)
    #expect(RecurringCalendar.occurrences(items: [root], from: recurrenceDate(26, hour: 0), to: recurrenceDate(29, hour: 0), calendar: recurrenceCalendar).isEmpty)
}
