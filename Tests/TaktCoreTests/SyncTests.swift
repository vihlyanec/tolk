import Foundation
import Testing
@testable import TaktCore

private func remote(_ id: String = "task1", title: String = "Из телефона", project: String = "inbox") -> TickTickTask {
    TickTickTask(["id": .string(id), "projectId": .string(project), "title": .string(title), "status": .number(0), "priority": .number(5)])
}
private func connected() -> Snapshot {
    var s = Snapshot(); s.tickTick = TickTickSyncState(connectionID: UUID())
    SyncEngine.ingest(projects: [], tasks: [remote()], inboxIDs: ["inbox"], into: &s)
    return s
}
@Test func syncOldSnapshotAndExportDoNotRestoreConnections() throws {
    let s = Snapshot(), encoder = JSONEncoder(), decoder = JSONDecoder()
    var raw = try decoder.decode(SyncFields.self, from: encoder.encode(s)); raw["tickTick"] = nil; raw["appleCalendar"] = nil
    let old = try decoder.decode(Snapshot.self, from: encoder.encode(raw)).validated()
    #expect(old.tickTick == nil && old.appleCalendar == nil)
    var linked = connected(); linked.appleCalendar = AppleCalendarState()
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
    defer { try? FileManager.default.removeItem(at: url) }
    try Database.export(linked, to: url)
    let imported = try Database.readExport(url)
    #expect(imported.tickTick == nil && imported.appleCalendar == nil)
    #expect(imported.items.count == linked.items.count && imported.items[0].externalRecurrence == nil)
}
@Test func syncInboxUndatedAndPriorityRoundTripWithoutDuplicates() throws {
    var s = connected()
    #expect(s.items.count == 1 && s.items[0].schedule == .unscheduled && s.items[0].priority == 1)
    SyncEngine.ingest(projects: [], tasks: [remote()], inboxIDs: ["inbox"], into: &s)
    #expect(s.items.count == 1 && s.tickTick?.outbox.isEmpty == true)
    s.items[0].title = "Правка с Mac"; SyncEngine.enqueueChanges(in: &s)
    let key = s.items[0].id.uuidString
    let pending = try #require(s.tickTick?.outbox[key])
    #expect(pending.task.title == "Правка с Mac" && !pending.creating)
    // A later local edit must survive acknowledgement of the prior one.
    s.items[0].body = "Ещё одна правка"
    SyncEngine.confirm(key: key, sent: pending, remote: pending.task, in: &s)
    #expect(s.tickTick?.outbox[key]?.task.raw["content"] == .string("Ещё одна правка"))
}
@Test func syncMergesIndependentChangesButStopsConflictingEdits() throws {
    var s = connected(); s.items[0].title = "Mac"
    var r = remote(); r.raw["priority"] = .number(1); r.raw["futureProperty"] = .object(["keep": .bool(true)])
    SyncEngine.ingest(projects: [], tasks: [r], inboxIDs: ["inbox"], into: &s)
    #expect(s.items[0].title == "Mac" && s.items[0].priority == 3)
    let key = s.items[0].id.uuidString
    #expect(s.tickTick?.outbox[key]?.task.raw["futureProperty"] == r.raw["futureProperty"])
    r.raw["title"] = .string("Phone")
    SyncEngine.ingest(projects: [], tasks: [r], inboxIDs: ["inbox"], into: &s)
    #expect(s.tickTick?.conflicts[key]?.fields.contains("title") == true)
    SyncEngine.resolve(key: key, useLocal: false, in: &s)
    #expect(s.items[0].title == "Phone" && s.tickTick?.conflicts.isEmpty == true)
}
@Test func syncCreatesOnlyOptedInNewTasksAndNeverImplicitlyDeletes() throws {
    var s = connected(); var local = Item(title: "Локальная")
    local.created = Date().addingTimeInterval(1); s.items.append(local); SyncEngine.enqueueChanges(in: &s)
    #expect(s.tickTick?.outbox.isEmpty == true)
    s.tickTick?.options.sendNewTasks = true; SyncEngine.enqueueChanges(in: &s)
    let key = local.id.uuidString, pending = try #require(s.tickTick?.outbox[key])
    #expect(pending.creating)
    s.tickTick?.outbox[key]?.attempted = true
    s.items[1].title = "Изменено пока ждём"
    SyncEngine.enqueueChanges(in: &s)
    #expect(s.tickTick?.outbox[key]?.attempted == true)
    var server = pending.task; server.raw["etag"] = .string("confirmed")
    SyncEngine.ingest(projects: [], tasks: [remote(), server], inboxIDs: ["inbox"], into: &s)
    #expect(s.items.count == 2 && s.items[1].title == "Изменено пока ждём")
    #expect(s.tickTick?.outbox[key]?.creating == false)
    s.items[0].deleted = true; SyncEngine.enqueueChanges(in: &s)
    #expect(s.tickTick?.outbox[s.items[0].id.uuidString] == nil)
}
@Test func syncNoMissingTasksAreDeletedAndServerOwnsRecurrence() throws {
    var s = connected(); let original = s.items[0]
    SyncEngine.ingest(projects: [], tasks: [], inboxIDs: ["inbox"], into: &s)
    #expect(s.items[0] == original)
    s.items[0].recurrence = .daily; s.items[0].schedule = .timed(Date())
    #expect(RecurringCalendar.next(s.items[0], in: s.items, calendar: Dates.calendar()) == nil)
    let occurrences = RecurringCalendar.occurrences(items: s.items, from: Date().addingTimeInterval(-3600), to: Date().addingTimeInterval(864000), calendar: Dates.calendar())
    #expect(occurrences.count == 1)
}
@Test func syncUndoPreservesIncomingFieldsRecordsAndMetadata() throws {
    let before = connected(); var after = before; after.items[0].title = "Моя правка"
    var current = after; current.items[0].body = "Входящее изменение"
    current.items.append(Item(title: "Новая удалённая задача")); current.tickTick?.lastSuccess = Date()
    current.appleCalendar = AppleCalendarState()
    let restored = try SnapshotEdit(before: before, after: after).restoring(in: current)
    #expect(restored.items[0].title == before.items[0].title && restored.items[0].body == "Входящее изменение")
    #expect(restored.items.count == 2 && restored.tickTick == current.tickTick && restored.appleCalendar == current.appleCalendar)
}
@Test func appleAllDayKeepsCivilDatesAndExclusiveEndAcrossZones() throws {
    let source = Dates.calendar(zone: "America/New_York"), target = Dates.calendar(zone: "Asia/Tokyo")
    let start = source.date(from: DateComponents(year: 2026, month: 11, day: 1))!
    let end = source.date(byAdding: .day, value: 2, to: start)!
    let event = ExternalEvent(calendarID: "a", sourceID: "iCloud", eventID: "1", title: "Поездка", start: start, end: end, allDay: true, timeZone: "America/New_York")
    let day = target.date(from: DateComponents(year: 2026, month: 11, day: 1))!
    #expect(event.intersects(day: day, calendar: target))
    #expect(event.intersects(day: target.date(byAdding: .day, value: 1, to: day)!, calendar: target))
    #expect(!event.intersects(day: target.date(byAdding: .day, value: 2, to: day)!, calendar: target))
}
@Test func appleOccurrenceIdentitySurvivesMoveAndSeparatesSources() {
    let now = Date()
    let a = ExternalEvent(calendarID: "a", sourceID: "iCloud", eventID: "series", externalID: "same", occurrence: now, title: "A", start: now, end: now.addingTimeInterval(3600))
    let moved = ExternalEvent(calendarID: "a", sourceID: "iCloud", eventID: "series", externalID: "same", occurrence: now, title: "Moved", start: now.addingTimeInterval(86400), end: now.addingTimeInterval(90000))
    let b = ExternalEvent(calendarID: "b", sourceID: "iCloud", eventID: "series", externalID: "same", occurrence: now, title: "B", start: now, end: now.addingTimeInterval(3600))
    #expect(a.id == moved.id && a.id != b.id)
}
@Test func appleCachesCompleteWindowsIncludingEmptyAndBoundsMemory() {
    var cache = AppleCalendarState(); cache.selected = ["a"]
    let now = Date(), event = ExternalEvent(calendarID: "a", sourceID: "s", eventID: "1", title: "Тест", start: now, end: now.addingTimeInterval(3600))
    cache.replace(AppleCalendarWindow(start: now, end: now.addingTimeInterval(10000), events: [event]))
    #expect(cache.events.count == 1)
    cache.replace(AppleCalendarWindow(start: now, end: now.addingTimeInterval(10000), events: []))
    #expect(cache.events.isEmpty && cache.windows.count == 1)
    for i in 1...30 { cache.replace(AppleCalendarWindow(start: now.addingTimeInterval(Double(i)), end: now.addingTimeInterval(Double(i + 1)), events: [])) }
    #expect(cache.windows.count == 24)
}
@Test func appleAndTasksUseJointOverlapLanes() {
    let c = Dates.calendar(), day = c.startOfDay(for: Date()), start = day.addingTimeInterval(36000)
    var task = Item(title: "Работа"); task.schedule = .timed(start); task.duration = 60
    let event = ExternalEvent(calendarID: "a", sourceID: "s", eventID: "1", title: "Встреча", start: start, end: start.addingTimeInterval(1800))
    let lanes = CalendarLayout.placements(items: [task], day: day, calendar: c, external: [event])
    #expect(lanes.count == 2 && lanes.allSatisfy { $0.laneCount == 2 })
}
@Test func appleDeletedSpanningEventDoesNotSurviveInOlderOverlappingCache() {
    var cache = AppleCalendarState(); cache.selected = ["a"]
    let now = Date(), event = ExternalEvent(calendarID: "a", sourceID: "s", eventID: "1", title: "Длинная встреча", start: now, end: now.addingTimeInterval(10000))
    cache.replace(AppleCalendarWindow(start: now, end: now.addingTimeInterval(5000), events: [event], fetchedAt: now))
    cache.replace(AppleCalendarWindow(start: now.addingTimeInterval(5000), end: now.addingTimeInterval(15000), events: [], fetchedAt: now.addingTimeInterval(1)))
    #expect(cache.events.isEmpty)
}
@Test func tickTickReminderParsingSupportsDocumentedDurationsWithoutOverflow() {
    #expect(TickTickCodec.triggerMinutes("TRIGGER:-PT15M") == -15)
    #expect(TickTickCodec.triggerMinutes("TRIGGER:P0DT9H0M0S") == 540)
    #expect(TickTickCodec.triggerMinutes("TRIGGER:-P1DT15H0M0S") == -2340)
    #expect(TickTickCodec.triggerMinutes("TRIGGER:PT0S") == 0)
    #expect(TickTickCodec.triggerMinutes("TRIGGER:PT45S") == nil)
    #expect(TickTickCodec.triggerMinutes("TRIGGER:-P999999999999999999999999D") == nil)
}
@Test func lostCompletionAcknowledgementDoesNotLoseUndoIntent() throws {
    var s = connected(); let key = s.items[0].id.uuidString
    s.items[0].completed = true; SyncEngine.enqueueChanges(in: &s)
    let sent = try #require(s.tickTick?.outbox[key]); s.tickTick?.outbox[key]?.attempted = true
    // Undo happens while the server is handling completion.
    s.items[0].completed = false; SyncEngine.enqueueChanges(in: &s)
    SyncEngine.ingest(projects: [], tasks: [sent.task], inboxIDs: ["inbox"], into: &s)
    #expect(!s.items[0].completed)
    #expect(s.tickTick?.outbox[key]?.task.completed == false)
}

@Test func appleInclusiveAllDayEndAppearsOnTheRightDayWithoutLeakingIntoTomorrow() {
    let source = Dates.calendar(zone: "Europe/Moscow"), target = Dates.calendar(zone: "America/Los_Angeles")
    let start = source.date(from: DateComponents(year: 2026, month: 10, day: 28))!
    let next = source.date(byAdding: .day, value: 1, to: start)!
    let event = ExternalEvent(calendarID: "subscribed", sourceID: "source", eventID: "inclusive", title: "Весь день", start: start, end: next.addingTimeInterval(-1), allDay: true, timeZone: source.timeZone.identifier)
    let targetDay = target.date(from: DateComponents(year: 2026, month: 10, day: 28))!
    #expect(event.intersects(day: targetDay, calendar: target))
    #expect(!event.intersects(day: target.date(byAdding: .day, value: -1, to: targetDay)!, calendar: target))
    #expect(!event.intersects(day: target.date(byAdding: .day, value: 1, to: targetDay)!, calendar: target))
    #expect(event.interval(in: target).start == targetDay)
}
@Test func appleInclusiveMultidayEndRoundsByCalendarDaysAcrossDST() {
    let c = Dates.calendar(zone: "America/New_York")
    let start = c.date(from: DateComponents(year: 2026, month: 10, day: 31))!
    let exclusive = c.date(byAdding: .day, value: 3, to: start)!
    for end in [exclusive, exclusive.addingTimeInterval(-1)] {
        let event = ExternalEvent(calendarID: "a", sourceID: "s", eventID: "dst", title: "Дни", start: start, end: end, allDay: true, timeZone: c.timeZone.identifier)
        #expect(event.interval(in: c).end == exclusive)
        #expect(event.intersects(day: c.date(byAdding: .day, value: 2, to: start)!, calendar: c))
        #expect(!event.intersects(day: exclusive, calendar: c))
    }
}
