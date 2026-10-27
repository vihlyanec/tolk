import Foundation

public struct TickTickPending: Codable, Equatable, Sendable {
    public var task: TickTickTask
    public var localFields: SyncFields
    public var creating: Bool
    public var attempted = false
    public init(task: TickTickTask, localFields: SyncFields, creating: Bool) {
        self.task = task; self.localFields = localFields; self.creating = creating
    }
}
public struct TickTickConflict: Codable, Equatable, Sendable {
    public var remote: TickTickTask
    public var fields: Set<String>
    public init(remote: TickTickTask, fields: Set<String>) { self.remote = remote; self.fields = fields }
}
public struct ExternalCalendar: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var sourceID: String
    public var name: String
    public var account: String
    public var color: String
    public init(id: String, sourceID: String, name: String, account: String, color: String) {
        self.id = id; self.sourceID = sourceID; self.name = name; self.account = account; self.color = color
    }
}
public struct ExternalEvent: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var calendarID: String
    public var sourceID: String
    public var eventID: String
    public var externalID: String?
    public var occurrence: Date
    public var title: String
    public var notes: String
    public var location: String
    public var url: URL?
    public var start: Date
    public var end: Date
    public var allDay: Bool
    public var timeZone: String
    public var tentative: Bool
    public init(calendarID: String, sourceID: String, eventID: String, externalID: String? = nil,
                occurrence: Date? = nil, title: String, notes: String = "", location: String = "", url: URL? = nil,
                start: Date, end: Date, allDay: Bool = false, timeZone: String = "UTC", tentative: Bool = false) {
        self.calendarID = calendarID; self.sourceID = sourceID; self.eventID = eventID; self.externalID = externalID
        self.occurrence = occurrence ?? start; self.title = title; self.notes = notes; self.location = location; self.url = url
        self.start = start; self.end = end; self.allDay = allDay; self.timeZone = timeZone; self.tentative = tentative
        // Calendar-scoped EventKit ID avoids collapsing separately imported/shared copies.
        let namespace = RecurringCalendar.identifier(source: UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1)), date: .distantPast)
        self.id = SyncIdentity.uuid(namespace: namespace, key: sourceID + ":" + calendarID + ":" + eventID + ":" + String((occurrence ?? start).timeIntervalSince1970))
    }
    public func interval(in calendar: Calendar) -> DateInterval {
        guard allDay else { return DateInterval(start: start, end: max(start, end)) }
        let source = Dates.calendar(zone: timeZone)
        func translate(_ date: Date) -> Date { calendar.date(from: source.dateComponents([.year, .month, .day], from: date)) ?? date }
        // Some subscribed calendars use an inclusive 23:59:59 end instead of
        // the next midnight. Round that boundary up in the source calendar;
        // flooring both endpoints would make a one-day event disappear.
        let endDay = source.startOfDay(for: end)
        let exclusiveEnd = end > endDay ? (source.date(byAdding: .day, value: 1, to: endDay) ?? end) : endDay
        let lower = translate(start), upper = translate(exclusiveEnd)
        return DateInterval(start: lower, end: max(lower, upper))
    }
    public func intersects(day: Date, calendar: Calendar) -> Bool {
        let range = interval(in: calendar), lower = calendar.startOfDay(for: day)
        let upper = calendar.date(byAdding: .day, value: 1, to: lower) ?? lower
        return range.start < upper && range.end > lower
    }
}
public enum SyncIdentity {
    public static func uuid(namespace: UUID, key: String) -> UUID {
        // Reuse the project's SHA-based UUID construction with a key-derived namespace.
        let bytes = Data((namespace.uuidString + ":" + key).utf8)
        return digestUUID(bytes)
    }
}
import CryptoKit
private func digestUUID(_ data: Data) -> UUID {
    var b = Array(SHA256.hash(data: data).prefix(16)); b[6] = (b[6] & 15) | 80; b[8] = (b[8] & 63) | 128
    return UUID(uuid: (b[0],b[1],b[2],b[3],b[4],b[5],b[6],b[7],b[8],b[9],b[10],b[11],b[12],b[13],b[14],b[15]))
}
public struct AppleCalendarWindow: Codable, Equatable, Sendable {
    public var start: Date
    public var end: Date
    public var fetchedAt: Date
    public var events: [ExternalEvent]
    public init(start: Date, end: Date, events: [ExternalEvent], fetchedAt: Date = Date()) {
        self.start = start; self.end = end; self.events = events; self.fetchedAt = fetchedAt
    }
}
public struct AppleCalendarState: Codable, Equatable, Sendable {
    public var generation = UUID()
    public var calendars: [ExternalCalendar] = []
    public var selected: Set<String> = []
    public var windows: [AppleCalendarWindow] = []
    public init() {}
    public mutating func replace(_ window: AppleCalendarWindow) {
        windows.removeAll { $0.start == window.start && $0.end == window.end }
        windows.append(window)
        windows.sort { $0.fetchedAt > $1.fetchedAt }
        windows = Array(windows.prefix(24))
    }
    public var events: [ExternalEvent] {
        var seen: Set<UUID> = []
        let ordered = windows.sorted { $0.fetchedAt > $1.fetchedAt }
        return ordered.enumerated().flatMap { index, window in
            window.events.filter { event in
                guard selected.contains(event.calendarID), !seen.contains(event.id) else { return false }
                let superseded = ordered.prefix(index).contains { newer in
                    event.start < newer.end && event.end > newer.start && !newer.events.contains { $0.id == event.id }
                }
                guard !superseded else { return false }
                seen.insert(event.id); return true
            }
        }
    }
}

/// Undo applies only fields changed by that user action, and only if they haven't
/// subsequently changed. Sync acknowledgements and incoming records survive it.
public struct SnapshotEdit: Sendable {
    public var before: Snapshot
    public var after: Snapshot
    public init(before: Snapshot, after: Snapshot) { self.before = before; self.after = after }
    public func restoring(in current: Snapshot) throws -> Snapshot {
        let encoder = JSONEncoder(), decoder = JSONDecoder()
        func object<T: Encodable>(_ value: T) throws -> SyncFields { try decoder.decode(SyncFields.self, from: encoder.encode(value)) }
        func reverseFields(_ before: SyncFields, _ after: SyncFields, _ current: SyncFields) -> SyncFields {
            var result = current
            for key in Set(before.keys).union(after.keys) where before[key] != after[key] && current[key] == after[key] { result[key] = before[key] }
            return result
        }
        func records<T: Codable & Identifiable & Equatable>(_ before: [T], _ after: [T], _ current: [T]) throws -> [T] where T.ID == UUID {
            let b = Dictionary(uniqueKeysWithValues: before.map { ($0.id, $0) }), a = Dictionary(uniqueKeysWithValues: after.map { ($0.id, $0) })
            var result = current
            for id in Set(b.keys).union(a.keys) where b[id] != a[id] {
                if let index = result.firstIndex(where: { $0.id == id }) {
                    if let old = b[id], let applied = a[id] {
                        result[index] = try decoder.decode(T.self, from: encoder.encode(reverseFields(try object(old), try object(applied), try object(result[index]))))
                    } else if b[id] == nil, result[index] == a[id] { result.remove(at: index) }
                } else if a[id] == nil, let old = b[id] { result.append(old) }
            }
            if current.map(\.id) == after.map(\.id) {
                let order = before.map(\.id)
                result.sort { (order.firstIndex(of: $0.id) ?? Int.max) < (order.firstIndex(of: $1.id) ?? Int.max) }
            }
            return result
        }
        var result = current
        result.items = try records(before.items, after.items, current.items)
        result.projects = try records(before.projects, after.projects, current.projects)
        result.tags = try records(before.tags, after.tags, current.tags)
        // Incoming records may now reference a tag/project created by the user action.
        let usedTags = Set(result.items.flatMap(\.tagIDs))
        for tag in current.tags where usedTags.contains(tag.id) && !result.tags.contains(where: { $0.id == tag.id }) { result.tags.append(tag) }
        let usedProjects = Set(result.items.compactMap(\.projectID))
        for project in current.projects where usedProjects.contains(project.id) && !result.projects.contains(where: { $0.id == project.id }) { result.projects.append(project) }
        result.preferences = try decoder.decode(Preferences.self, from: encoder.encode(reverseFields(try object(before.preferences), try object(after.preferences), try object(current.preferences))))
        return try result.validated()
    }
}
