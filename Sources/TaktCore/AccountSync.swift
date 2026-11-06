import Foundation

public struct AccountRecord: Codable, Equatable, Sendable {
    public var id: String
    public var kind: String
    public var version: Int
    public var data: SyncFields
    public var key: String { kind + ":" + id.lowercased() }
    public init(id: String, kind: String, version: Int = 0, data: SyncFields = [:]) { self.id = id.lowercased(); self.kind = kind; self.version = version; self.data = data }
}
public struct AccountOperation: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID().uuidString.lowercased()
    public var entityID: String
    public var kind: String
    public var base: Int
    public var patch: SyncFields
    public var expected: SyncFields
    public var key: String { kind + ":" + entityID.lowercased() }
    public init(record: AccountRecord, patch: SyncFields, expected: SyncFields) {
        entityID = record.id.lowercased(); kind = record.kind; base = record.version; self.patch = patch; self.expected = expected
    }
}
public struct AccountConflict: Codable, Equatable, Identifiable, Sendable {
    public var operation: AccountOperation
    public var fields: [String]
    public var remote: AccountRecord
    public var id: String { operation.id }
}
public struct AccountSyncState: Codable, Equatable, Sendable {
    public var origin = "https://tolk.103-102-229-153.sslip.io"
    public var accountID: String
    public var name: String
    public var deviceID = UUID()
    public var connectionID = UUID()
    public var recovering: Bool?
    public var epoch: String?
    public var cursor = 0
    public var records: [String: AccountRecord] = [:]
    public var pending: [AccountOperation] = []
    public var conflicts: [AccountConflict] = []
    public var lastSuccess: Date?
    public init(accountID: String, name: String) { self.accountID = accountID.lowercased(); self.name = name }
}
public struct AccountResult: Codable, Sendable {
    public var id: String
    public var accepted: Bool
    public var record: AccountRecord
    public var fields: [String]?
}
public struct AccountResponse: Codable, Sendable {
    public var results: [AccountResult]
    public var changes: [AccountRecord]
    public var cursor: Int
    public var more: Bool
    public var epoch: String
}

public enum AccountCodec {
    private static let optionalItem = ["repeatEveryDays","recurrenceSourceID","recurrenceEndDate","recurrenceOriginalDate","repeatParentID","externalRecurrence","reminderMinutes","timedReminderOffsets","allDayReminders","stickyFrame","stickyCollapsed","stickyExpandedHeight"]
    private static func fields<T: Encodable>(_ value: T) throws -> SyncFields { try JSONDecoder().decode(SyncFields.self, from: JSONEncoder().encode(value)) }
    private static func decode<T: Decodable>(_ type: T.Type, _ data: SyncFields) throws -> T { try JSONDecoder().decode(type, from: JSONEncoder().encode(data)) }
    public static func records(_ snapshot: Snapshot, accountID: String) throws -> [AccountRecord] {
        var records: [AccountRecord] = []
        for (order, project) in snapshot.projects.enumerated() {
            if project.archived && snapshot.accountSync?.records["project:" + project.id.uuidString.lowercased()]?.data["deleted"]?.bool == true { continue }
            var data = try fields(project); data["id"] = nil; data["order"] = .number(Double(order)); data["title"] = data.removeValue(forKey: "name")
            data["itemKind"] = data.removeValue(forKey: "kind"); data["deleted"] = .bool(false)
            records.append(AccountRecord(id: project.id.uuidString, kind: "project", data: data))
        }
        func depth(_ tag: Tag) -> Int {
            var result = 0, parent = tag.parentID, seen: Set<UUID> = [tag.id]
            while let id = parent, seen.insert(id).inserted { result += 1; parent = snapshot.tags.first { $0.id == id }?.parentID }
            return result
        }
        for (order, tag) in snapshot.tags.enumerated().sorted(by: { depth($0.element) < depth($1.element) }) {
            var data = try fields(tag); data["id"] = nil; data["order"] = .number(Double(order)); data["title"] = data.removeValue(forKey: "name")
            data["parentID"] = data["parentID"] ?? .null; data["deleted"] = .bool(false)
            records.append(AccountRecord(id: tag.id.uuidString, kind: "tag", data: data))
        }
        let calendar = Dates.calendar(zone: snapshot.preferences.timeZone)
        for (order, item) in snapshot.items.enumerated() {
            var data = try fields(item); data["id"] = nil; data["order"] = .number(Double(order)); data["itemKind"] = data.removeValue(forKey: "kind")
            data["tagIDs"] = .array(item.tagIDs.map { .string($0.uuidString.lowercased()) })
            data["projectID"] = item.projectID.map { .string($0.uuidString.lowercased()) } ?? .string("")
            for key in optionalItem where data[key] == nil { data[key] = .null }
            switch item.schedule {
            case .unscheduled: data["schedule"] = .object(["kind":.string("none")])
            case .day(let day):
                let c = calendar.dateComponents([.year,.month,.day], from: day)
                data["schedule"] = .object(["kind":.string("day"),"day":.string(String(format:"%04d-%02d-%02d",c.year!,c.month!,c.day!))])
            case .timed(let date): data["schedule"] = .object(["kind":.string("timed"),"instant":.number(date.timeIntervalSince1970)])
            }
            records.append(AccountRecord(id: item.id.uuidString, kind: "task", data: data))
        }
        var preferences = try fields(snapshot.preferences)
        // Drafts and shortcuts are preserved in the account too. Integration credentials,
        // in-flight TickTick operations and machine-specific EventKit identifiers stay local.
        for key in ["completionSoundEnabled","completionHapticsEnabled","quickDraftBody","quickDraftDescriptionExpanded","quickDraftLiterals","defaultTimedReminderOffsets","defaultAllDayReminders"] where preferences[key] == nil { preferences[key] = .null }
        var connections: SyncFields = [:]
        if let tick = snapshot.tickTick {
            connections["tickTick"] = .object(["configured":.bool(true),"owner":snapshot.accountSync.map { .string($0.deviceID.uuidString.lowercased()) } ?? .string(""),
                "options":.object(try fields(tick.options)),"includeInbox":.bool(tick.includeInbox),
                "selectedProjects":tick.selectedProjects.map { .array($0.sorted().map(SyncJSON.string)) } ?? .null])
        }
        if let apple = snapshot.appleCalendar {
            connections["appleCalendar"] = .object(["configured":.bool(true),"owner":snapshot.accountSync.map { .string($0.deviceID.uuidString.lowercased()) } ?? .string(""),
                "selected":.array(apple.selected.sorted().map(SyncJSON.string)),"calendars":.array(try apple.calendars.map { .object(try fields($0)) })])
            for event in apple.events where apple.selected.contains(event.calendarID) {
                var data = try fields(event)
                data["owner"] = snapshot.accountSync.map { .string($0.deviceID.uuidString.lowercased()) } ?? .string("")
                data["id"] = nil; data["start"] = .number(event.start.timeIntervalSince1970); data["end"] = .number(event.end.timeIntervalSince1970)
                data["deleted"] = .bool(false)
                if event.allDay {
                    let zone = Dates.calendar(zone:event.timeZone), parts = zone.dateComponents([.year,.month,.day],from:event.start)
                    data["day"] = .string(String(format:"%04d-%02d-%02d",parts.year!,parts.month!,parts.day!))
                }
                records.append(AccountRecord(id:event.id.uuidString,kind:"event",data:data))
            }
        }
        let savedConnections = snapshot.accountSync?.records["settings:" + accountID.lowercased()]?.data["integrations"]?.object ?? [:]
        let device = snapshot.accountSync?.deviceID.uuidString.lowercased()
        for (provider,value) in savedConnections where value.object?["owner"]?.string != device { connections[provider] = value }
        if !connections.isEmpty || savedConnections.values.contains(where: { $0.object?["owner"]?.string == device }) { preferences["integrations"] = .object(connections) }
        records.append(AccountRecord(id: accountID, kind: "settings", data: preferences))
        let priority = ["project":0,"tag":1,"settings":2,"task":3,"event":4]
        return records.enumerated().sorted { left,right in
            let a = priority[left.element.kind] ?? 5, b = priority[right.element.kind] ?? 5
            return a == b ? left.offset < right.offset : a < b
        }.map(\.element)
    }
    public static func apply(_ records: [AccountRecord], to snapshot: inout Snapshot) throws {
        var next = snapshot
        try applyValidated(records,to:&next)
        snapshot = next
    }
    private static func applyValidated(_ records: [AccountRecord], to snapshot: inout Snapshot) throws {
        let original = snapshot
        for record in records where record.kind == "settings" {
            let merged = try fields(snapshot.preferences).merging(record.data) { _, remote in remote }
            snapshot.preferences = try decode(Preferences.self, merged)
            if let connections = record.data["integrations"]?.object, let device = snapshot.accountSync?.deviceID.uuidString.lowercased() {
                if let tick = connections["tickTick"]?.object, tick["owner"]?.string == device, snapshot.tickTick != nil {
                    if let options = tick["options"]?.object { snapshot.tickTick?.options = try decode(TickTickOptions.self,options) }
                    if let inbox = tick["includeInbox"]?.bool { snapshot.tickTick?.includeInbox = inbox }
                    if let selected = tick["selectedProjects"]?.array { snapshot.tickTick?.selectedProjects = Set(selected.compactMap(\.string)) }
                }
                if let apple = connections["appleCalendar"]?.object, apple["owner"]?.string == device,
                   let selected = apple["selected"]?.array, let existing = snapshot.appleCalendar {
                    let desired = Set(selected.compactMap(\.string))
                    if desired != existing.selected { snapshot.appleCalendar?.selected = desired; snapshot.appleCalendar?.generation = UUID(); snapshot.appleCalendar?.windows = [] }
                }
            }
        }
        let calendar = Dates.calendar(zone: snapshot.preferences.timeZone)
        for record in records where record.kind == "project" {
            guard let id = UUID(uuidString: record.id) else { throw TaktError.invalid("Некорректный проект аккаунта") }
            if record.data["deleted"]?.bool == true { snapshot.projects.removeAll { $0.id == id }; continue }
            var data = try fields(snapshot.projects.first { $0.id == id } ?? Project(name: "Проект"))
            data.merge(record.data) { _, remote in remote }; data["id"] = .string(id.uuidString)
            data["name"] = data["title"]; data["kind"] = data["itemKind"] ?? .string("task")
            let value = try decode(Project.self, data)
            if let index = snapshot.projects.firstIndex(where: { $0.id == id }) { snapshot.projects[index] = value } else { snapshot.projects.append(value) }
        }
        for record in records where record.kind == "tag" {
            guard let id = UUID(uuidString: record.id) else { throw TaktError.invalid("Некорректная метка аккаунта") }
            if record.data["deleted"]?.bool == true { snapshot.tags.removeAll { $0.id == id }; continue }
            var data = try fields(snapshot.tags.first { $0.id == id } ?? Tag(name: "Метка"))
            data.merge(record.data) { _, remote in remote }; data["id"] = .string(id.uuidString); data["name"] = data["title"]
            let value = try decode(Tag.self, data)
            if let index = snapshot.tags.firstIndex(where: { $0.id == id }) { snapshot.tags[index] = value } else { snapshot.tags.append(value) }
        }
        for record in records where record.kind == "task" {
            guard let id = UUID(uuidString: record.id) else { throw TaktError.invalid("Некорректная запись аккаунта") }
            var data = try fields(snapshot.items.first { $0.id == id } ?? Item(title: "Задача"))
            data.merge(record.data) { _, remote in remote }; data["id"] = .string(id.uuidString)
            data["kind"] = data["itemKind"] ?? .string("task")
            if data["projectID"]?.string == "" { data["projectID"] = .null }
            data["schedule"] = nil
            var value = try decode(Item.self, data.merging(["schedule":.object(["unscheduled":.object([:])])]) { _, new in new })
            let schedule = record.data["schedule"]?.object
            if schedule?["kind"]?.string == "timed", case .number(let instant) = schedule?["instant"] {
                value.schedule = .timed(Date(timeIntervalSince1970: instant))
            } else if let day = schedule?["day"]?.string ?? record.data["date"]?.string, !day.isEmpty {
                let parts = day.split(separator:"-").compactMap { Int($0) }
                guard parts.count == 3, let date = calendar.date(from:DateComponents(year:parts[0],month:parts[1],day:parts[2])) else { throw TaktError.invalid("Некорректная дата аккаунта") }
                if schedule == nil, let time = record.data["time"]?.string, !time.isEmpty {
                    let clock = time.split(separator:":").compactMap { Int($0) }
                    guard clock.count == 2, let timed = calendar.date(bySettingHour:clock[0],minute:clock[1],second:0,of:date) else { throw TaktError.invalid("Некорректное время аккаунта") }
                    value.schedule = .timed(timed)
                } else { value.schedule = .day(date) }
            } else { value.schedule = .unscheduled }
            if let index = snapshot.items.firstIndex(where: { $0.id == id }) { snapshot.items[index] = value } else { snapshot.items.append(value) }
        }
        let deletedTags = Set(records.filter { $0.kind == "tag" && $0.data["deleted"]?.bool == true }.compactMap { UUID(uuidString:$0.id) })
        for i in snapshot.items.indices { snapshot.items[i].tagIDs.removeAll { deletedTags.contains($0) } }
        for i in snapshot.tags.indices { if let parent = snapshot.tags[i].parentID, deletedTags.contains(parent) { snapshot.tags[i].parentID = nil } }
        for record in records where record.kind == "project" && record.data["deleted"]?.bool == true {
            guard let id = UUID(uuidString:record.id), snapshot.items.contains(where: { $0.projectID == id }) else { continue }
            var project = original.projects.first { $0.id == id } ?? Project(name:record.data["title"]?.string ?? "Архивный проект")
            project.id = id; project.archived = true
            if !snapshot.projects.contains(where: { $0.id == id }) { snapshot.projects.append(project) }
        }
        let ranks = Dictionary(uniqueKeysWithValues:records.map { ($0.key,$0.data["order"]?.int ?? Int.max) })
        func rank(_ kind: String, _ id: UUID) -> Int { ranks[kind + ":" + id.uuidString.lowercased()] ?? Int.max }
        snapshot.projects.sort { rank("project",$0.id) == rank("project",$1.id) ? $0.id.uuidString < $1.id.uuidString : rank("project",$0.id) < rank("project",$1.id) }
        snapshot.tags.sort { rank("tag",$0.id) == rank("tag",$1.id) ? $0.id.uuidString < $1.id.uuidString : rank("tag",$0.id) < rank("tag",$1.id) }
        snapshot.items.sort { rank("task",$0.id) == rank("task",$1.id) ? $0.id.uuidString < $1.id.uuidString : rank("task",$0.id) < rank("task",$1.id) }
        do { _ = try snapshot.validated() }
        catch { snapshot = original; throw error }
    }
}

public enum AccountEngine {
    public static func enqueue(in snapshot: inout Snapshot) throws {
        guard var sync = snapshot.accountSync, sync.recovering != true else { return }
        var overlay = sync.records
        for op in sync.conflicts.map(\.operation) + sync.pending {
            var record = overlay[op.key] ?? AccountRecord(id:op.entityID,kind:op.kind)
            record.data.merge(op.patch) { _, local in local }; overlay[op.key] = record
        }
        let current = try AccountCodec.records(snapshot, accountID:sync.accountID)
        var live = Set<String>()
        for record in current {
            live.insert(record.key)
            let previous = overlay[record.key]
            let patch = record.data.filter { previous?.data[$0.key] != $0.value }
            guard !patch.isEmpty else { continue }
            var base = sync.records[record.key] ?? AccountRecord(id:record.id,kind:record.kind)
            base.version = sync.records[record.key]?.version ?? 0
            let expected = Dictionary(uniqueKeysWithValues:patch.keys.map { ($0,previous?.data[$0] ?? .null) })
            sync.pending.append(AccountOperation(record:base,patch:patch,expected:expected))
        }
        for record in overlay.values where ["project","tag","task","event"].contains(record.kind) && !live.contains(record.key) && record.data["deleted"]?.bool != true {
            if record.kind == "event", record.data["owner"]?.string != sync.deviceID.uuidString.lowercased() { continue }
            let base = sync.records[record.key] ?? record
            sync.pending.append(AccountOperation(record:base,patch:["deleted":.bool(true)],expected:["deleted":record.data["deleted"] ?? .null]))
        }
        snapshot.accountSync = sync
    }
    public static func requestOperations(_ state: AccountSyncState) -> [AccountOperation] {
        guard state.epoch != nil else { return [] }
        var seen = Set(state.conflicts.map { $0.operation.key }), bytes = 1000
        var result: [AccountOperation] = []
        for op in state.pending {
            guard !seen.contains(op.key) else { continue }
            let size = (try? JSONEncoder().encode(op).count) ?? 1000000
            if result.count >= 50 || (!result.isEmpty && bytes + size > 700000) { break }
            seen.insert(op.key); bytes += size; result.append(op)
        }
        return result
    }
    public static func receive(_ response: AccountResponse, sent: [AccountOperation], in snapshot: inout Snapshot) throws {
        var next = snapshot
        try receiveValidated(response,sent:sent,in:&next)
        snapshot = next
    }
    private static func receiveValidated(_ response: AccountResponse, sent: [AccountOperation], in snapshot: inout Snapshot) throws {
        guard var sync = snapshot.accountSync else { return }
        if let epoch = sync.epoch, epoch != response.epoch { throw TaktError.invalid("Сервер восстановлен. Локальная очередь сохранена. Переподключите аккаунт после проверки данных.") }
        guard response.cursor >= sync.cursor, !response.epoch.isEmpty, response.results.count == sent.count,
              Set(response.results.map(\.id)).count == response.results.count else { throw TaktError.invalid("Неполное подтверждение аккаунта. Очередь сохранена.") }
        for record in response.changes + response.results.map(\.record) {
            guard UUID(uuidString:record.id) != nil, record.version > 0, ["task","project","tag","settings","event"].contains(record.kind),
                  record.kind != "settings" || record.id.lowercased() == sync.accountID else { throw TaktError.invalid("Некорректная запись аккаунта") }
        }
        func apply(_ record: AccountRecord) {
            if (sync.records[record.key]?.version ?? -1) <= record.version { sync.records[record.key] = record }
        }
        for result in response.results {
            guard let operation = sent.first(where: { $0.id == result.id }) else { throw TaktError.invalid("Неизвестное подтверждение сервера") }
            guard result.record.key == operation.key else { throw TaktError.invalid("Подтверждение относится к другой записи. Очередь сохранена.") }
            if result.accepted {
                guard result.record.version > operation.base, operation.patch.allSatisfy({ result.record.data[$0.key] == $0.value }) else { throw TaktError.invalid("Сервер не подтвердил отправленные поля. Очередь сохранена.") }
            }
            apply(result.record)
            if !result.accepted { sync.conflicts.append(AccountConflict(operation:operation,fields:result.fields ?? [],remote:result.record)) }
            sync.pending.removeAll { $0.id == result.id }
        }
        response.changes.forEach(apply)
        sync.cursor = response.cursor; sync.epoch = response.epoch
        snapshot.accountSync = sync
        guard !response.more else { return } // References may arrive on the next page.
        if sync.recovering == true {
            var grouped: [String:AccountOperation] = [:]
            for op in sync.conflicts.map(\.operation) + sync.pending {
                if var previous = grouped[op.key] { previous.patch.merge(op.patch) { _, local in local }; grouped[op.key] = previous }
                else { grouped[op.key] = op }
            }
            sync.pending = []; sync.conflicts = grouped.values.compactMap { op in
                let remote = sync.records[op.key] ?? AccountRecord(id:op.entityID,kind:op.kind)
                var changed = op
                changed.patch = op.patch.filter { remote.data[$0.key] != $0.value }
                guard !changed.patch.isEmpty else { return nil }
                return AccountConflict(operation:changed,fields:changed.patch.keys.sorted(),remote:remote)
            }
            sync.recovering = false; snapshot.accountSync = sync
        }
        var effective = sync.records
        for op in sync.conflicts.map(\.operation) + sync.pending {
            var record = effective[op.key] ?? AccountRecord(id:op.entityID,kind:op.kind)
            record.data.merge(op.patch) { _, local in local }; effective[op.key] = record
        }
        try install(effective,in:&snapshot)
        // The Mac remains the single writer to its existing external integrations.
        SyncEngine.enqueueChanges(in:&snapshot)
        snapshot.accountSync?.lastSuccess = Date()
    }
    private static func install(_ effective: [String:AccountRecord], in snapshot: inout Snapshot) throws {
        func contains(_ kind: String, _ id: UUID) -> Bool { effective[kind + ":" + id.uuidString.lowercased()] != nil }
        snapshot.items.removeAll { !contains("task",$0.id) }
        snapshot.projects.removeAll { !contains("project",$0.id) }
        snapshot.tags.removeAll { !contains("tag",$0.id) }
        try AccountCodec.apply(Array(effective.values),to:&snapshot)
    }
    public static func recover(in snapshot: inout Snapshot) {
        guard var sync = snapshot.accountSync, let local = try? AccountCodec.records(snapshot,accountID:sync.accountID) else { return }
        sync.pending = local.map { AccountOperation(record:AccountRecord(id:$0.id,kind:$0.kind),patch:$0.data,expected:[:]) }
        sync.conflicts = []
        sync.records = [:]; sync.epoch = nil; sync.cursor = 0; sync.recovering = true
        snapshot.accountSync = sync
    }
    public static func resolve(_ id: String, useLocal: Bool, in snapshot: inout Snapshot) throws {
        var next = snapshot
        try resolveValidated(id,useLocal:useLocal,in:&next)
        snapshot = next
    }
    private static func resolveValidated(_ id: String, useLocal: Bool, in snapshot: inout Snapshot) throws {
        guard var sync = snapshot.accountSync, let conflict = sync.conflicts.first(where: { $0.id == id }) else { return }
        let dependent = sync.pending.filter { $0.key == conflict.operation.key }
        sync.pending.removeAll { $0.key == conflict.operation.key }
        sync.conflicts.removeAll { $0.id == id }
        if useLocal {
            var patch = conflict.operation.patch
            for op in dependent { patch.merge(op.patch) { _, local in local } }
            let remote = sync.records[conflict.remote.key] ?? conflict.remote
            sync.pending.append(AccountOperation(record:remote,patch:patch,expected:remote.data.filter { patch[$0.key] != nil }))
        }
        snapshot.accountSync = sync
        var effective = sync.records
        for op in sync.conflicts.map(\.operation) + sync.pending {
            var record = effective[op.key] ?? AccountRecord(id:op.entityID,kind:op.kind)
            record.data.merge(op.patch) { _, local in local }; effective[op.key] = record
        }
        try install(effective,in:&snapshot)
    }
}
