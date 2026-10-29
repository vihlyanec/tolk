import Foundation

public enum ItemKind: String, Codable, Sendable { case task, note }
public enum Recurrence: String, Codable, CaseIterable, Sendable {
    case none, daily, weekdays, weekly, monthly, intervalDays
    public var title: String { switch self {
        case .intervalDays: "Через X дней"; case .none: "Не повторять"; case .daily: "Каждый день"; case .weekdays: "По будням"
        case .weekly: "Каждую неделю"; case .monthly: "Каждый месяц"
    } }
}
public enum Schedule: Codable, Equatable, Sendable {
    case unscheduled, day(Date), timed(Date)
    public var date: Date? { switch self { case .unscheduled: nil; case .day(let d), .timed(let d): d } }
    public var isTimed: Bool { if case .timed = self { true } else { false } }
}
public struct Project: Identifiable, Codable, Equatable, Sendable {
    public var id = UUID()
    public var name: String
    public var color: String
    public var kind: ItemKind
    public var folder = ""
    public var sections = ["Без раздела"]
    public var archived = false
    public var kanban = false
    public init(name: String, color: String = "598BFF", kind: ItemKind = .task) {
        self.name = name; self.color = color; self.kind = kind
    }
}
public struct Tag: Identifiable, Codable, Equatable, Sendable {
    public var id = UUID()
    public var name: String
    public var color: String
    public var parentID: UUID?
    public init(name: String, color: String = "AD94E8", parentID: UUID? = nil) {
        self.name = name; self.color = color; self.parentID = parentID
    }
}
public struct CheckItem: Identifiable, Codable, Equatable, Sendable {
    public var id = UUID()
    public var title: String
    public var done = false
    public var tickTickID: String?
    public init(title: String) { self.title = title }
}
public struct Item: Identifiable, Codable, Equatable, Sendable {
    public var id = UUID()
    public var kind: ItemKind
    public var title: String
    public var body = ""
    public var projectID: UUID?
    public var section = "Без раздела"
    public var tagIDs: [UUID] = []
    public var priority = 0
    public var schedule: Schedule = .unscheduled
    public var duration = 30
    public var completed = false
    public var deleted = false
    public var created = Date()
    public var modified = Date()
    public var checklist: [CheckItem] = []
    public var recurrence: Recurrence = .none
    public var repeatEveryDays: Int?
    public var recurrenceSourceID: UUID?
    /// Exclusive end of a local recurrence series.
    public var recurrenceEndDate: Date?
    public var recurrenceOriginalDate: Date?
    public var repeatParentID: UUID?
    public var externalRecurrence: Bool?
    public var reminderMinutes: Int?
    public var timedReminderOffsets: [Int]?
    public var allDayReminders: [AllDayReminder]?
    public var stickyOpen = false
    public var stickyPinned = true
    public var stickyColor = "AD94E8"
    public var stickyFrame: [Double]?
    public var stickyCollapsed: Bool?
    public var stickyExpandedHeight: Double?
    public init(title: String, kind: ItemKind = .task, projectID: UUID? = nil) {
        self.title = title; self.kind = kind; self.projectID = projectID
    }
    public var recurrenceLabel: String { recurrence == .intervalDays ? "Через \(repeatEveryDays ?? 3) дн." : recurrence.title }
    public var end: Date? { schedule.isTimed ? schedule.date?.addingTimeInterval(Double(duration) * 60) : nil }
}
public struct Preferences: Codable, Equatable, Sendable {
    public var theme = "dark"
    public var timeZone = "Europe/Moscow"
    public var startHour = 7
    public var endHour = 23
    public var hourHeight = 96.0
    public var calendarUXVersion: Int? = 2
    public var showCompleted = false
    public var shiftedShortcuts = false
    public var completionSoundEnabled: Bool?
    public var completionHapticsEnabled: Bool?
    public var quickDraft = ""
    public var quickDraftBody: String?
    public var quickDraftDescriptionExpanded: Bool?
    public var quickDraftLiterals: [QuickLiteralToken]?
    public var defaultTimedReminderOffsets: [Int]?
    public var defaultAllDayReminders: [AllDayReminder]?
    public var grouping: [String: String] = [:]
    public var sorting: [String: String] = [:]
    public init() {}
}
public struct Snapshot: Codable, Equatable, Sendable {
    public var tickTick: TickTickSyncState?
    public var appleCalendar: AppleCalendarState?
    public var version = 1
    public var projects: [Project] = []
    public var tags: [Tag] = []
    public var items: [Item] = []
    public var preferences = Preferences()
    public init() {}
    public func validated() throws -> Self {
        guard version == 1 else { throw TaktError.invalid("Неподдерживаемая версия данных: \(version)") }
        guard Set(projects.map(\.id)).count == projects.count,
              Set(tags.map(\.id)).count == tags.count,
              Set(items.map(\.id)).count == items.count else { throw TaktError.invalid("Повторяющиеся идентификаторы") }
        let projectIDs = Set(projects.map(\.id)), tagIDs = Set(tags.map(\.id))
        for item in items {
            guard (1...10080).contains(item.duration), item.repeatEveryDays.map({ (1...3650).contains($0) }) ?? true, (0...3).contains(item.priority),
                  item.projectID.map({ projectIDs.contains($0) }) ?? true,
                  Set(item.tagIDs).isSubset(of: tagIDs) else { throw TaktError.invalid("Повреждены свойства или связи записи") }
        }
        func validReminders(_ offsets: [Int]?, _ allDay: [AllDayReminder]?) -> Bool {
            (offsets ?? []).allSatisfy { (0...525600).contains($0) } && Set((allDay ?? []).map(\.id)).count == (allDay ?? []).count && (allDay ?? []).allSatisfy { (0...365).contains($0.daysBefore) && (0..<1440).contains($0.minuteOfDay) }
        }
        guard validReminders(preferences.defaultTimedReminderOffsets, preferences.defaultAllDayReminders),
              items.allSatisfy({ validReminders($0.timedReminderOffsets, $0.allDayReminders) && ($0.reminderMinutes.map { (0...525600).contains($0) } ?? true) }) else { throw TaktError.invalid("Некорректные настройки напоминаний") }
        for tag in tags {
            var seen: Set<UUID> = [tag.id], parent = tag.parentID
            while let id = parent {
                guard !seen.contains(id), let next = tags.first(where: { $0.id == id }) else {
                    throw TaktError.invalid("Недопустимая вложенность тегов")
                }
                seen.insert(id); parent = next.parentID
            }
        }
        if let sync = tickTick {
            guard [3, 5].contains(sync.options.intervalMinutes),
                  sync.links.keys.allSatisfy({ UUID(uuidString: $0) != nil }),
                  sync.outbox.keys.allSatisfy({ sync.links[$0] != nil }) else { throw TaktError.invalid("Повреждены связи синхронизации TickTick") }
        }
        if let apple = appleCalendar {
            guard apple.windows.count <= 24, apple.windows.allSatisfy({ window in
                window.end > window.start && window.events.allSatisfy { $0.end > $0.start && TimeZone(identifier: $0.timeZone) != nil }
            }) else { throw TaktError.invalid("Повреждён кеш Apple Календаря") }
        }
        guard TimeZone(identifier: preferences.timeZone) != nil,
              (0...23).contains(preferences.startHour),
              preferences.endHour > preferences.startHour, preferences.endHour <= 24,
              (36...180).contains(preferences.hourHeight) else { throw TaktError.invalid("Некорректные настройки календаря") }
        return self
    }
}
public enum TaktError: LocalizedError {
    case invalid(String), storage(String)
    public var errorDescription: String? { switch self { case .invalid(let s), .storage(let s): s } }
}
public enum Dates {
    public static func calendar(zone: String = "Europe/Moscow") -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "ru_RU")
        c.timeZone = TimeZone(identifier: zone) ?? .current
        c.firstWeekday = 2
        return c
    }
    public static func nextOccurrence(_ item: Item, calendar: Calendar) -> Item? {
        guard item.recurrence != .none, let date = item.schedule.date else { return nil }
        let next: Date?
        switch item.recurrence {
        case .none: return nil
        case .intervalDays: next = calendar.date(byAdding: .day, value: max(1, min(3650, item.repeatEveryDays ?? 3)), to: date)
        case .daily: next = calendar.date(byAdding: .day, value: 1, to: date)
        case .weekly: next = calendar.date(byAdding: .day, value: 7, to: date)
        case .monthly: next = calendar.date(byAdding: .month, value: 1, to: date)
        case .weekdays:
            var d = date
            repeat { guard let n = calendar.date(byAdding: .day, value: 1, to: d) else { return nil }; d = n }
            while [1, 7].contains(calendar.component(.weekday, from: d))
            next = d
        }
        guard let next else { return nil }
        var result = item
        result.id = UUID(); result.created = Date(); result.modified = Date()
        result.schedule = item.schedule.isTimed ? .timed(next) : .day(next)
        result.completed = false; result.stickyOpen = false; result.stickyFrame = nil
        result.repeatParentID = item.id
        result.checklist = result.checklist.map { CheckItem(title: $0.title) }
        return result
    }
}
