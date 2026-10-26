import Foundation
import Testing
@testable import TaktCore

private let calendar = Dates.calendar()
private func date(_ day: Int = 25, _ hour: Int = 12, _ minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
}

@Test func smartInputPreservesURLAndParsesProperties() {
    let project = Project(name: "Рабочие задачи"), tag = Tag(name: "работа")
    let p = QuickParser.parse("Отчёт https://example.com/x завтра в 14:00 на 45 минут !1 #работа /\"Рабочие задачи\"", projects: [project], tags: [tag], now: date())
    #expect(p.title == "Отчёт https://example.com/x")
    #expect(p.projectID == project.id && p.tagIDs == [tag.id])
    #expect(p.priority == 1 && p.duration == 45)
    #expect(p.schedule == .timed(date(26, 14)))
}
@Test func dateWithoutTimeAndInvalidDates() {
    let p = QuickParser.parse("Купить завтра на 1 час", projects: [], tags: [], now: date())
    #expect(p.schedule == .day(date(26, 0)))
    #expect(p.duration == 60)
    let invalid = QuickParser.parse("Встреча 31.02.2026", projects: [], tags: [], now: date())
    #expect(invalid.schedule == .unscheduled)
    #expect(invalid.title.contains("31.02.2026"))
    #expect(!invalid.warnings.isEmpty)
}
@Test func unknownMetadataDoesNotLoseText() {
    let p = QuickParser.parse("Привет! /новый #неизвестный", projects: [], tags: [], now: date())
    #expect(p.title == "Привет! /новый #неизвестный")
    #expect(p.warnings.count == 2)
}
@Test func identicalHourTasksShareDayWidth() throws {
    var a = Item(title: "Отчёт"), b = Item(title: "Созвон"), c = Item(title: "Почта")
    a.schedule = .timed(date(25, 14)); b.schedule = a.schedule
    a.duration = 60; b.duration = 60
    c.schedule = .timed(date(25, 15)); c.duration = 30
    let layout = CalendarLayout.placements(items: [a,b,c], day: date(), calendar: calendar)
    let first = try #require(layout.first(where: { $0.id == a.id }))
    let second = try #require(layout.first(where: { $0.id == b.id }))
    #expect(first.laneCount == 2 && second.laneCount == 2)
    #expect(first.lane != second.lane)
    #expect(first.startMinute == 840 && first.endMinute == 900)
    #expect(layout.first(where: { $0.id == c.id })?.laneCount == 1)
}
@Test func chainedOverlapsAndMidnightClipping() {
    var items = (0..<3).map { Item(title: "\($0)") }
    for i in items.indices { items[i].schedule = .timed(date(25, 14, i * 20)); items[i].duration = 30 }
    let layout = CalendarLayout.placements(items: items, day: date(), calendar: calendar)
    #expect(layout.allSatisfy { $0.laneCount == 2 })
    var overnight = Item(title: "Ночь"); overnight.schedule = .timed(date(24, 23, 30)); overnight.duration = 120
    let clipped = CalendarLayout.placements(items: [overnight], day: date(), calendar: calendar)
    #expect(clipped.first?.startMinute == 0 && clipped.first?.endMinute == 90)
}
@Test func databaseRoundTripBackupAndRestore() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let db = try Database(url: root.appendingPathComponent("main.sqlite"))
    var snapshot = Snapshot(); var item = Item(title: "Без даты, но на 45 минут"); item.duration = 45
    snapshot.items = [item]
    try db.save(snapshot)
    #expect(try db.load() == snapshot)
    let backup = root.appendingPathComponent("backup.sqlite")
    try db.backup(to: backup)
    #expect(try Database(url: backup).load() == snapshot)
    let exported = root.appendingPathComponent("data.json")
    try Database.export(snapshot, to: exported)
    #expect(try Database.readExport(exported) == snapshot)
    var invalid = snapshot; invalid.items[0].duration = -1
    #expect(throws: (any Error).self) { try db.save(invalid) }
    #expect(try db.load() == snapshot)
}
@Test func tagCyclesRejectedAndRepeatsKeepLocalClock() throws {
    var a = Tag(name: "A"), b = Tag(name: "B"); a.parentID = b.id; b.parentID = a.id
    var snapshot = Snapshot(); snapshot.tags = [a,b]
    #expect(throws: (any Error).self) { try snapshot.validated() }
    var item = Item(title: "Будни"); item.schedule = .timed(date(23,14)); item.recurrence = .weekdays
    let next = try #require(Dates.nextOccurrence(item, calendar: calendar))
    #expect(next.schedule == .timed(date(26,14)))
    #expect(next.id != item.id)
}

@Test func highlightRangesMatchAcceptedOriginalInput() throws {
    let project = Project(name: "Мои дела")
    let tag = Tag(name: "идеи")
    let input = "👩🏽‍💻 Эскиз /\"Мои дела\" сегодня в 16:30 на 45 минут важно #идеи"
    let parsed = QuickParser.parse(input, projects: [project], tags: [tag])
    #expect(parsed.title == "👩🏽‍💻 Эскиз")
    #expect(parsed.priority == 1 && parsed.duration == 45)
    #expect(parsed.tokens.map(\.kind) == [.project, .date, .time, .duration, .priority, .tag])
    for token in parsed.tokens {
        #expect((input as NSString).substring(with: token.range) == token.value)
    }
    #expect(parsed.tokens.map(\.value) == ["/\"Мои дела\"", "сегодня", "в 16:30", "на 45 минут", "важно", "#идеи"])
}

@Test func unknownOrInvalidInputIsNotHighlighted() {
    let input = "Отправить https://example.com #нет /нет 31.02.2026 !7 25:90"
    let parsed = QuickParser.parse(input, projects: [], tags: [])
    #expect(parsed.tokens.isEmpty)
    #expect(parsed.title == input)
    let priority = QuickParser.parse("Задача важно !3", projects: [], tags: [])
    #expect(priority.priority == 3)
    #expect(priority.tokens.map(\.value) == ["!3"])
    #expect(priority.title == "Задача важно")
}

@Test func stickyFoldStatePersistsAndOlderNotesStillDecode() throws {
    var snapshot = Snapshot()
    var note = Item(title: "Заметка", kind: .note)
    note.body = "Этот текст должен сохраниться"
    note.stickyCollapsed = true; note.stickyExpandedHeight = 420; note.stickyFrame = [180, 600, 330, 36]
    snapshot.items = [note]
    let encoded = try JSONEncoder().encode(snapshot)
    let decoded = try JSONDecoder().decode(Snapshot.self, from: encoded).validated()
    #expect(decoded.items.first?.stickyCollapsed == true)
    #expect(decoded.items.first?.stickyExpandedHeight == 420 && decoded.items.first?.body == note.body)
    var legacy = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    var items = try #require(legacy["items"] as? [[String: Any]])
    items[0].removeValue(forKey: "stickyCollapsed"); items[0].removeValue(forKey: "stickyExpandedHeight")
    legacy["items"] = items
    let old = try JSONDecoder().decode(Snapshot.self, from: JSONSerialization.data(withJSONObject: legacy)).validated()
    #expect(old.items.first?.stickyCollapsed == nil && old.items.first?.body == note.body)
}

@Test func naturalRelativeTimesAndDurations() {
    let cases: [(String, Int)] = [("через час",60), ("через полчаса",30), ("через пол часа",30), ("пол часа",30), ("полчаса",30), ("через 10 минут",10), ("через минуту",1), ("через два часа",120), ("через полтора часа",90), ("через 2ч",120)]
    for (phrase, minutes) in cases {
        let input = "Позвонить " + phrase
        let p = QuickParser.parse(input, projects: [], tags: [], now: date())
        #expect(p.title == "Позвонить")
        #expect(p.schedule == .timed(calendar.date(byAdding: .minute, value: minutes, to: date())!))
        #expect(p.tokens.count == 1 && p.tokens.first?.kind == .time)
        #expect(p.tokens.first?.value == phrase)
    }
    for (phrase, minutes) in [("на полчаса",30), ("на пол часа",30), ("на час",60), ("на полтора часа",90), ("на две минуты",2)] {
        let p = QuickParser.parse("Работа " + phrase, projects: [], tags: [], now: date())
        #expect(p.title == "Работа" && p.duration == minutes && p.hasExplicitDuration)
        #expect(p.schedule == .unscheduled && p.tokens.first?.kind == .duration)
    }
    let combined = QuickParser.parse("Работа через полчаса на час", projects: [], tags: [], now: date())
    #expect(combined.schedule == .timed(date(25,12,30)) && combined.duration == 60)
}

@Test func relativeCalendarUnitsUseCalendarAndExplicitClock() {
    let cases: [(String, Calendar.Component, Int)] = [("через день",.day,1), ("через сутки",.day,1), ("через неделю",.weekOfYear,1), ("через 2 недели",.weekOfYear,2), ("через месяц",.month,1), ("через три месяца",.month,3), ("через год",.year,1), ("через 2 года",.year,2)]
    for (phrase, unit, count) in cases {
        let p = QuickParser.parse("Проверить " + phrase, projects: [], tags: [], now: date())
        let expected = calendar.startOfDay(for: calendar.date(byAdding: unit, value: count, to: date())!)
        #expect(p.title == "Проверить" && p.schedule == .day(expected))
        #expect(p.tokens.first?.kind == .date)
    }
    let january = calendar.date(from: DateComponents(year: 2028, month: 1, day: 31, hour: 12))!
    let february = calendar.date(from: DateComponents(year: 2028, month: 2, day: 29, hour: 9, minute: 15))!
    let p = QuickParser.parse("Проверить через месяц в 09:15", projects: [], tags: [], now: january)
    #expect(p.schedule == .timed(february) && p.title == "Проверить")
    let crossing = QuickParser.parse("Позвонить через час", projects: [], tags: [], now: date(25,23,30))
    #expect(crossing.schedule == .timed(date(26,0,30)))
}

@Test func invalidRelativeAmountsPreserveInput() {
    for phrase in ["через 0 часов", "через -2 месяца", "через 10001 минут", "через полтора месяца", "на 99999999999999999999 часов"] {
        let input = "Задача " + phrase
        let p = QuickParser.parse(input, projects: [], tags: [], now: date())
        #expect(p.title == input && p.schedule == .unscheduled && p.tokens.isEmpty)
    }
}

@Test func multipleRemindersRespectDefaultsOverridesAndAllDayClocks() throws {
    var snapshot = Snapshot()
    snapshot.preferences.defaultTimedReminderOffsets = [0,10,60]
    snapshot.preferences.defaultAllDayReminders = [AllDayReminder(daysBefore: 1, minuteOfDay: 18*60), AllDayReminder(minuteOfDay: 9*60), AllDayReminder(minuteOfDay: 18*60)]
    var timed = Item(title: "Созвон"); timed.schedule = .timed(date(26,14))
    var allDay = Item(title: "Документы"); allDay.schedule = .day(date(27,0))
    snapshot.items = [timed, allDay]
    let plans = NotificationPlan.events(snapshot: snapshot, now: date())
    #expect(plans.count == 6 && Set(plans.map(\.identifier)).count == 6)
    #expect(plans.contains { $0.itemID == allDay.id && $0.fire == date(26,18) })
    #expect(plans.contains { $0.itemID == allDay.id && $0.fire == date(27,9) })
    #expect(plans.contains { $0.itemID == allDay.id && $0.fire == date(27,18) })
    snapshot.items[0].timedReminderOffsets = []
    #expect(NotificationPlan.events(snapshot: snapshot, now: date()).count == 3)
    snapshot.items[0].timedReminderOffsets = [5,5]
    #expect(NotificationPlan.events(snapshot: snapshot, now: date()).filter { $0.itemID == timed.id }.count == 1)
    snapshot.items[0].completed = true; snapshot.items[1].deleted = true
    #expect(NotificationPlan.events(snapshot: snapshot, now: date()).isEmpty)
    let restored = try JSONDecoder().decode(Snapshot.self, from: JSONEncoder().encode(snapshot)).validated()
    #expect(restored == snapshot)
}

@Test func legacyRemindersAndInvalidNewSettings() throws {
    var preferences = Preferences(); preferences.defaultTimedReminderOffsets = [10]
    var item = Item(title: "Старая запись"); item.reminderMinutes = 30
    #expect(NotificationPlan.timedOffsets(item: item, preferences: preferences) == [30])
    item.timedReminderOffsets = []
    #expect(NotificationPlan.timedOffsets(item: item, preferences: preferences).isEmpty)
    var snapshot = Snapshot(); snapshot.items = [item]
    snapshot.preferences.defaultAllDayReminders = [AllDayReminder(minuteOfDay: 1500)]
    #expect(throws: (any Error).self) { try snapshot.validated() }
}
