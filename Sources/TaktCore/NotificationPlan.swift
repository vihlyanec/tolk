import Foundation

public struct AllDayReminder: Identifiable, Codable, Equatable, Sendable {
    public var id = UUID()
    public var daysBefore: Int
    public var minuteOfDay: Int
    public init(daysBefore: Int = 0, minuteOfDay: Int = 540) { self.daysBefore = daysBefore; self.minuteOfDay = minuteOfDay }
}
public struct PlannedReminder: Equatable, Sendable {
    public var identifier: String
    public var itemID: UUID
    public var title: String
    public var fire: Date
}
public enum NotificationPlan {
    public static func timedOffsets(item: Item, preferences: Preferences) -> [Int] {
        item.timedReminderOffsets ?? item.reminderMinutes.map { [$0] } ?? preferences.defaultTimedReminderOffsets ?? []
    }
    public static func allDayRules(item: Item, preferences: Preferences) -> [AllDayReminder] {
        item.allDayReminders ?? preferences.defaultAllDayReminders ?? []
    }
    public static func events(snapshot: Snapshot, now: Date = Date()) -> [PlannedReminder] {
        let calendar = Dates.calendar(zone: snapshot.preferences.timeZone)
        var result: [PlannedReminder] = []
        for item in snapshot.items where item.kind == .task && !item.completed && !item.deleted {
            guard let start = item.schedule.date else { continue }
            var dates: [Date] = []
            if item.schedule.isTimed {
                dates = timedOffsets(item: item, preferences: snapshot.preferences).map { start.addingTimeInterval(-Double($0) * 60) }
            } else {
                dates = allDayRules(item: item, preferences: snapshot.preferences).compactMap { rule in
                    guard let day = calendar.date(byAdding: .day, value: -rule.daysBefore, to: start) else { return nil }
                    return calendar.date(bySettingHour: rule.minuteOfDay / 60, minute: rule.minuteOfDay % 60, second: 0, of: day)
                }
            }
            // One banner per task and minute, even if equivalent rules carry different seconds.
            var minutes = Set<Int>()
            for fire in Set(dates).sorted() where fire > now && minutes.insert(Int(fire.timeIntervalSince1970 / 60)).inserted {
                result.append(PlannedReminder(identifier: "task-\(item.id.uuidString)-\(Int(fire.timeIntervalSince1970))", itemID: item.id, title: item.title, fire: fire))
            }
        }
        return result.sorted { $0.fire < $1.fire }.prefix(50).map { $0 }
    }
}
