import Foundation

public enum SyncJSON: Codable, Equatable, Sendable {
    case string(String), number(Double), bool(Bool), array([SyncJSON]), object([String: SyncJSON]), null
    public init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([SyncJSON].self) { self = .array(a) }
        else { self = .object(try c.decode([String: SyncJSON].self)) }
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    public var string: String? { if case .string(let s) = self { s } else { nil } }
    public var int: Int? { if case .number(let n) = self, n.isFinite, n >= Double(Int.min), n < Double(Int.max) { Int(n) } else { nil } }
    public var bool: Bool? { if case .bool(let b) = self { b } else { nil } }
    public var array: [SyncJSON]? { if case .array(let a) = self { a } else { nil } }
    public var object: [String: SyncJSON]? { if case .object(let o) = self { o } else { nil } }
}
public typealias SyncFields = [String: SyncJSON]

public struct TickTickOptions: Codable, Equatable, Sendable {
    public var enabled = false
    public var intervalMinutes = 5
    public var sendNewTasks = false
    public var sendExistingTasks = false
    public var sendDeletions = false
    public init() {}
}
public struct TickTickTask: Codable, Equatable, Sendable, Identifiable {
    public var raw: SyncFields
    public var id: String { raw["id"]?.string ?? "" }
    public var projectID: String { raw["projectId"]?.string ?? "inbox" }
    public var title: String { raw["title"]?.string ?? "Без названия" }
    public var completed: Bool { raw["status"]?.int == 2 }
    public var kind: String { raw["kind"]?.string ?? "TEXT" }
    public init(_ raw: SyncFields) { self.raw = raw }
    public init(from decoder: any Decoder) throws { raw = try SyncFields(from: decoder) }
    public func encode(to encoder: any Encoder) throws { try raw.encode(to: encoder) }
    public var fields: SyncFields {
        var result: SyncFields = ["title": .string(title), "content": .string(raw["content"]?.string ?? ""), "priority": .number(Double(raw["priority"]?.int ?? 0)), "status": .number(completed ? 2 : 0), "projectId": .string(projectID), "isAllDay": .bool(raw["isAllDay"]?.bool ?? false), "timeZone": .string(raw["timeZone"]?.string ?? "UTC"), "repeatFlag": .string(raw["repeatFlag"]?.string ?? "")]
        for key in ["startDate", "dueDate"] { result[key] = TickTickCodec.date(raw[key]?.string).map { .string(TickTickCodec.stamp($0)) } ?? .null }
        result["tags"] = .array((raw["tags"]?.array ?? []).compactMap(\.string).sorted().map(SyncJSON.string))
        result["reminders"] = .array((raw["reminders"]?.array ?? []).compactMap(\.string).sorted().map(SyncJSON.string))
        result["items"] = .array((raw["items"]?.array ?? []).compactMap(\.object).map { .object(["id": $0["id"] ?? .string(""), "title": $0["title"] ?? .string(""), "status": $0["status"] ?? .number(0)]) })
        return result
    }
}
public struct TickTickProject: Codable, Equatable, Sendable, Identifiable {
    public var raw: SyncFields
    public var id: String { raw["id"]?.string ?? "" }
    public var name: String { raw["name"]?.string ?? "TickTick" }
    public var color: String { raw["color"]?.string?.replacingOccurrences(of: "#", with: "") ?? "598BFF" }
    public var closed: Bool { raw["closed"]?.bool ?? false }
    public var isNote: Bool { raw["kind"]?.string == "NOTE" }
    public init(_ raw: SyncFields) { self.raw = raw }
    public init(from decoder: any Decoder) throws { raw = try SyncFields(from: decoder) }
    public func encode(to encoder: any Encoder) throws { try raw.encode(to: encoder) }
}
public struct TickTickLink: Codable, Equatable, Sendable {
    public var remote: TickTickTask
    public var local: SyncFields
    public var pendingCreate = false
    public var missing = false
    public var remoteDeleted = false
    public init(remote: TickTickTask, local: SyncFields, pendingCreate: Bool = false) { self.remote = remote; self.local = local; self.pendingCreate = pendingCreate }
}
public struct TickTickProjectLink: Codable, Equatable, Sendable {
    public var remote: TickTickProject
    public var localName: String
    public var localColor: String
    public init(remote: TickTickProject, local: Project) { self.remote = remote; localName = local.name; localColor = local.color }
}
public struct TickTickSyncState: Codable, Equatable, Sendable {
    public var connectionID: UUID
    public var connectedAt = Date()
    public var initialImportDone = false
    public var lastSuccess: Date?
    public var links: [String: TickTickLink] = [:]
    public var projects: [String: TickTickProjectLink] = [:]
    public var localOnly: Set<UUID> = []
    public var options = TickTickOptions()
    public var selectedProjects: Set<String>?
    public var includeInbox = true
    public var outbox: [String: TickTickPending] = [:]
    public var conflicts: [String: TickTickConflict] = [:]
    public init(connectionID: UUID) { self.connectionID = connectionID }
}
public struct TickTickMerge: Equatable, Sendable {
    public var changed: Set<String>
    public var conflicts: Set<String>
    public init(baseLocal: SyncFields, local: SyncFields, baseRemote: SyncFields, remote: SyncFields) {
        changed = Set(local.keys.filter { local[$0] != baseLocal[$0] })
        let remoteChanged = Set(remote.keys.filter { remote[$0] != baseRemote[$0] })
        conflicts = changed.intersection(remoteChanged).filter { local[$0] != remote[$0] }
        let dates: Set<String> = ["startDate", "dueDate", "isAllDay", "timeZone"]
        if !changed.isDisjoint(with: dates), !remoteChanged.isDisjoint(with: dates), dates.contains(where: { local[$0] != remote[$0] }) { conflicts.formUnion(dates) }
        if changed.contains("projectId"), !remoteChanged.isEmpty { conflicts.insert("projectId") }
        if remoteChanged.contains("projectId"), !changed.isEmpty { conflicts.insert("projectId") }
    }
}
public enum TickTickCodec {
    public static func date(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: value) { return d }
        f.formatOptions = [.withInternetDateTime]; if let d = f.date(from: value) { return d }
        let g = DateFormatter(); g.locale = Locale(identifier: "en_US_POSIX"); g.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        if let d = g.date(from: value) { return d }
        g.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"; return g.date(from: value)
    }
    public static func stamp(_ date: Date) -> String { let f = ISO8601DateFormatter(); return f.string(from: date) }
    public static func remoteID(_ uuid: UUID = UUID()) -> String { String(uuid.uuidString.replacingOccurrences(of: "-", with: "").prefix(24)).lowercased() }
    public static func rule(_ item: Item) -> String {
        switch item.recurrence {
        case .none: return ""
        case .daily: return "RRULE:FREQ=DAILY;INTERVAL=1"
        case .weekly: return "RRULE:FREQ=WEEKLY;INTERVAL=1"
        case .monthly: return "RRULE:FREQ=MONTHLY;INTERVAL=1"
        case .weekdays: return "RRULE:FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR"
        case .intervalDays: return "RRULE:FREQ=DAILY;INTERVAL=\(item.repeatEveryDays ?? 3)"
        }
    }
    public static func recurrence(_ rule: String) -> (Recurrence, Int?)? {
        if rule.isEmpty { return (.none, nil) }
        let clean = rule.uppercased().replacingOccurrences(of: "RRULE:", with: "")
        let pieces = clean.split(separator: ";").map { $0.split(separator: "=", maxSplits: 1).map(String.init) }
        var values: [String:String] = [:]; for piece in pieces where piece.count == 2 { values[piece[0]] = piece[1] }
        guard Set(values.keys).isSubset(of: ["FREQ", "INTERVAL", "BYDAY"]) else { return nil }
        let n = Int(values["INTERVAL"] ?? "1") ?? 0
        guard (1...3650).contains(n) else { return nil }
        if values["FREQ"] == "WEEKLY", n == 1, values["BYDAY"] == "MO,TU,WE,TH,FR" { return (.weekdays, nil) }
        guard values["BYDAY"] == nil else { return nil }
        switch values["FREQ"] {
        case "DAILY": return n == 1 ? (.daily, nil) : (.intervalDays, n)
        case "WEEKLY" where n == 1: return (.weekly, nil)
        case "MONTHLY" where n == 1: return (.monthly, nil)
        default: return nil
        }
    }
    public static func localFields(_ item: Item, in snapshot: Snapshot, remoteProjectID: String) -> SyncFields {
        let zone = snapshot.preferences.timeZone
        var result: SyncFields = ["title": .string(item.title), "content": .string(item.body), "priority": .number(Double([0:0, 1:5, 2:3, 3:1][item.priority] ?? 0)), "status": .number(item.completed ? 2 : 0), "projectId": .string(remoteProjectID), "timeZone": .string(zone), "isAllDay": .bool(item.schedule.date != nil && !item.schedule.isTimed), "repeatFlag": .string(rule(item))]
        if let d = item.schedule.date {
            result["startDate"] = .string(stamp(d)); result["dueDate"] = .string(stamp(item.schedule.isTimed ? d.addingTimeInterval(Double(item.duration) * 60) : d))
        } else { result["startDate"] = .null; result["dueDate"] = .null }
        result["tags"] = .array(item.tagIDs.compactMap { id in snapshot.tags.first { $0.id == id }?.name }.sorted().map(SyncJSON.string))
        result["items"] = .array(item.checklist.map { .object(["id": .string($0.tickTickID ?? remoteID($0.id)), "title": .string($0.title), "status": .number($0.done ? 1 : 0)]) })
        let reminders: [String]
        if item.schedule.isTimed {
            reminders = NotificationPlan.timedOffsets(item: item, preferences: snapshot.preferences).map { "TRIGGER:-PT\($0)M" }
        } else if item.schedule.date != nil {
            reminders = NotificationPlan.allDayRules(item: item, preferences: snapshot.preferences).map { rule in
                let minutes = rule.minuteOfDay - rule.daysBefore * 1440
                return minutes < 0 ? "TRIGGER:-PT\(-minutes)M" : "TRIGGER:P0DT\(minutes / 60)H\(minutes % 60)M0S"
            }
        } else { reminders = [] }
        result["reminders"] = .array(reminders.sorted().map(SyncJSON.string))
        return result
    }
    public static func applying(_ remote: TickTickTask, to item: Item, snapshot: inout Snapshot) -> Item {
        var value = item
        value.title = remote.title; value.body = remote.raw["content"]?.string ?? ""
        value.priority = [0:0, 5:1, 3:2, 1:3][remote.raw["priority"]?.int ?? 0] ?? 0
        value.completed = remote.completed
        let zone = remote.raw["timeZone"]?.string.flatMap(TimeZone.init(identifier:))?.identifier ?? snapshot.preferences.timeZone
        let remoteCalendar = Dates.calendar(zone: zone), localCalendar = Dates.calendar(zone: snapshot.preferences.timeZone)
        if let date = date(remote.raw["startDate"]?.string) ?? date(remote.raw["dueDate"]?.string) {
            if remote.raw["isAllDay"]?.bool == true {
                let parts = remoteCalendar.dateComponents([.year, .month, .day], from: date)
                value.schedule = .day(localCalendar.date(from: parts) ?? date)
            } else {
                value.schedule = .timed(date)
                if let end = Self.date(remote.raw["dueDate"]?.string), end > date { value.duration = max(1, min(10080, Int(end.timeIntervalSince(date) / 60))) }
            }
        } else { value.schedule = .unscheduled }
        if let (rule, days) = recurrence(remote.raw["repeatFlag"]?.string ?? "") { value.recurrence = rule; value.repeatEveryDays = days }
        else { value.recurrence = .none; value.repeatEveryDays = nil }
        value.tagIDs = (remote.raw["tags"]?.array ?? []).compactMap(\.string).map { name in
            if let tag = snapshot.tags.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) { return tag.id }
            let tag = Tag(name: name); snapshot.tags.append(tag); return tag.id
        }
        let oldChecks = value.checklist
        value.checklist = (remote.raw["items"]?.array ?? []).compactMap(\.object).map { raw in
            let id = raw["id"]?.string ?? ""
            var check = oldChecks.first { $0.tickTickID == id || remoteID($0.id) == id } ?? CheckItem(title: raw["title"]?.string ?? "")
            check.tickTickID = id; check.title = raw["title"]?.string ?? ""; check.done = raw["status"]?.int == 1; return check
        }
        // Only understood relative reminders are projected; the original server values remain in the link.
        let reminders = (remote.raw["reminders"]?.array ?? []).compactMap(\.string)
        value.timedReminderOffsets = []; value.allDayReminders = []; value.reminderMinutes = nil
        let minutes = reminders.compactMap(triggerMinutes)
        if value.schedule.isTimed {
            value.timedReminderOffsets = minutes.filter { (-525600...0).contains($0) }.map { -$0 }
        } else {
            value.allDayReminders = minutes.compactMap { total in
                guard (-525600..<1440).contains(total) else { return nil }
                let days = total >= 0 ? 0 : (-total + 1439) / 1440
                let minute = total + days * 1440
                guard days <= 365 else { return nil }
                return item.allDayReminders?.first { $0.daysBefore == days && $0.minuteOfDay == minute } ?? AllDayReminder(daysBefore: days, minuteOfDay: minute)
            }
        }
        value.externalRecurrence = true
        value.modified = Date(); return value
    }
    public static func triggerMinutes(_ trigger: String) -> Int? {
        guard trigger.count < 100, let regex = try? NSRegularExpression(pattern: #"^TRIGGER:(-)?P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$"#),
              let match = regex.firstMatch(in: trigger, range: NSRange(trigger.startIndex..., in: trigger)) else { return nil }
        func number(_ index: Int) -> Int? {
            guard let range = Range(match.range(at: index), in: trigger) else { return 0 }
            guard let value = Int(trigger[range]), value <= 1_000_000 else { return nil }; return value
        }
        guard let d = number(2), let h = number(3), let m = number(4), let s = number(5), s == 0 else { return nil }
        let total = d * 1440 + h * 60 + m
        return match.range(at: 1).location == NSNotFound ? total : -total
    }
    public static func patch(_ remote: TickTickTask, with fields: SyncFields, keys: Set<String>) -> TickTickTask {
        var result = remote
        for key in keys {
            if key == "items", let rows = fields[key]?.array {
                let originals = remote.raw["items"]?.array?.compactMap(\.object) ?? []
                result.raw[key] = .array(rows.compactMap(\.object).map { row in
                    var merged = originals.first { $0["id"] == row["id"] } ?? [:]
                    merged.merge(row) { _, new in new }; return .object(merged)
                })
            } else { result.raw[key] = fields[key] ?? .null }
        }
        return result
    }
}
