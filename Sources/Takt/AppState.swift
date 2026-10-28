import Foundation
import Observation
import TaktCore

enum Area: String, CaseIterable { case tasks, calendar, notes }
enum Scope: Hashable { case all, inbox, today, week, completed, trash, project(UUID), tag(UUID) }
enum Grouping: String, CaseIterable { case date = "Дата", project = "Проект", section = "Раздел", priority = "Приоритет", tag = "Тег", none = "Без группировки" }
enum Sorting: String, CaseIterable { case manual = "Вручную", date = "Время", priority = "Приоритет", title = "Название", duration = "Длительность" }
struct TaskGroup: Identifiable { let id: String; var items: [Item] }

@Observable final class AppState {
    var data: Snapshot
    var area: Area = .tasks
    var scope: Scope = .all
    var selectedID: UUID?
    var calendarEditingID: UUID?
    var draggingID: UUID?
    var dragOffsetMinutes = 0
    var dragSessionID = UUID()
    var search = ""
    var anchor = Date()
    var calendarMode = "Неделя"
    var queueInboxOnly = false
    var queueSorting: Sorting = .manual
    var queueProjectID: UUID?
    var queueTagID: UUID?
    var queuePriority: Int?
    var queueDateFilter = "Без времени"
    var queueSearch = ""
    var appUpdater: AppUpdater?
    var syncCoordinator: SyncCoordinator?
    var externalEventID: UUID?
    var errorMessage: String?
    var notice: String?
    var inspectorVisible = true
    var sidebarVisible = true
    var sheet: CreationKind?
    @ObservationIgnored var showQuick: (Date?) -> Void = { _ in }
    @ObservationIgnored var showRangeQuick: (Date, Int) -> Void = { _, _ in }
    @ObservationIgnored var showSticky: (UUID?) -> Void = { _ in }
    @ObservationIgnored var showSettings: () -> Void = {}
    @ObservationIgnored var didSave: () -> Void = {}
    @ObservationIgnored var onTaskCompleted: (Preferences) -> Void = { _ in }
    @ObservationIgnored private let database: Database?
    @ObservationIgnored private let memoryOnly: Bool
    @ObservationIgnored private var past: [SnapshotEdit] = []
    @ObservationIgnored private var future: [SnapshotEdit] = []
    @ObservationIgnored private var backupDay = ""
    @ObservationIgnored private var pendingQuickDraft: QuickCaptureDraft?
    @ObservationIgnored private var quickDraftSaveTask: Task<Void, Never>?
    let dataURL: URL

    init(demo: Bool = false, storageURL: URL? = nil) {
        memoryOnly = demo
        let syncTest = Bundle.main.bundleIdentifier == "local.takt.synctest" || ProcessInfo.processInfo.arguments.contains("--sync-test")
        let supportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Takt", isDirectory: true).appendingPathComponent("takt.sqlite")
        dataURL = storageURL ?? (syncTest ? URL(fileURLWithPath: ProcessInfo.processInfo.environment["TOLK_SYNC_TEST_DATA"] ?? "/private/tmp/tolk-sync-isolated/takt.sqlite") : supportURL)
        if demo { database = nil; data = Self.demo(); return }
        do {
            let db = try Database(url: dataURL); var snapshot = try db.load()
            if snapshot.preferences.calendarUXVersion != 2 {
                if snapshot.preferences.hourHeight == 64 { snapshot.preferences.hourHeight = 96 }
                snapshot.preferences.calendarUXVersion = 2
            }
            data = snapshot; database = db
        }
        catch { data = Snapshot(); database = nil; errorMessage = "Данные не открыты: \(error.localizedDescription). Запись заблокирована. База: \(dataURL.path)" }
    }
    var calendar: Calendar { Dates.calendar(zone: data.preferences.timeZone) }
    var isDemo: Bool { memoryOnly }
    var isSyncTest: Bool { Bundle.main.bundleIdentifier == "local.takt.synctest" || ProcessInfo.processInfo.arguments.contains("--sync-test") }
    var selected: Item? { data.items.first { $0.id == selectedID } }
    var draggingItem: Item? { draggingID.flatMap(item) }
    func beginDrag(_ item: Item, offset: Int = 0) -> NSItemProvider {
        draggingID = item.id; dragOffsetMinutes = offset; dragSessionID = UUID()
        return NSItemProvider(object: item.id.uuidString as NSString)
    }
    func endDrag() { draggingID = nil; dragOffsetMinutes = 0; dragSessionID = UUID() }
    func select(_ id: UUID) {
        selectedID = id; inspectorVisible = true
        if item(id)?.kind == .note { area = .notes }
    }
    func filterByTag(_ id: UUID) { if area == .calendar { area = .tasks }; scope = .tag(id); search = ""; selectedID = nil }
    func commitHashtags(_ id: UUID) {
        guard let item = item(id), !item.deleted else { return }
        let names = Hashtags.names(in: item.title + "\n" + item.body)
        change { snapshot in
            guard let index = snapshot.items.firstIndex(where: { $0.id == id }) else { return }
            for name in names {
                let tag: Tag
                if let existing = snapshot.tags.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) { tag = existing }
                else { tag = Tag(name: name, color: ProjectTagPalette.nextColor(in: snapshot)); snapshot.tags.append(tag) }
                if !snapshot.items[index].tagIDs.contains(tag.id) { snapshot.items[index].tagIDs.append(tag.id) }
            }
        }
    }
    func selectCalendar(_ id: UUID) { selectedID = id; calendarEditingID = id }
    var activeProjects: [Project] { data.projects.filter { !$0.archived } }
    var scopeKey: String { "\(area.rawValue)-\(String(describing: scope))" }
    var grouping: Grouping {
        get { Grouping(rawValue: data.preferences.grouping[scopeKey] ?? "") ?? (project == nil ? .date : .section) }
        set { change { $0.preferences.grouping[scopeKey] = newValue.rawValue } }
    }
    var sorting: Sorting {
        get { Sorting(rawValue: data.preferences.sorting[scopeKey] ?? "") ?? .manual }
        set { change { $0.preferences.sorting[scopeKey] = newValue.rawValue } }
    }
    var project: Project? { if case .project(let id) = scope { data.projects.first { $0.id == id } } else { nil } }
    var title: String {
        switch scope {
        case .all: area == .notes ? "Заметки" : "Все задачи"
        case .inbox: "Входящие"; case .today: "Сегодня"; case .week: "Следующие 7 дней"
        case .completed: "Завершённые"; case .trash: "Корзина"
        case .project(let id): data.projects.first { $0.id == id }?.name ?? "Проект"
        case .tag(let id): "#" + (data.tags.first { $0.id == id }?.name ?? "Тег")
        }
    }
    func change(undo: Bool = true, notifyServices: Bool = true, _ mutate: (inout Snapshot) -> Void) {
        guard database != nil || memoryOnly else { return }
        let previous = data
        var next = previous; mutate(&next)
        if undo { SyncEngine.enqueueChanges(in: &next) }
        guard next != previous else { return }
        do {
            _ = try next.validated()
            if let database {
                let day = Date().formatted(.iso8601.year().month().day().dateSeparator(.dash))
                if backupDay != day {
                    let folder = dataURL.deletingLastPathComponent().appendingPathComponent("Backups")
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    let target = folder.appendingPathComponent("\(day).sqlite")
                    if !FileManager.default.fileExists(atPath: target.path) { try database.backup(to: target) }
                    backupDay = day
                }
                try database.save(next)
            }
            if undo { past.append(SnapshotEdit(before: previous, after: next)); if past.count > 80 { past.removeFirst() }; future.removeAll() }
            data = next
            if notifyServices { didSave() }
        } catch { errorMessage = "Не сохранено: \(error.localizedDescription). Изменение не применено." }
    }
    func queueQuickDraft(_ draft: QuickCaptureDraft) {
        // Keystrokes stay in the editor's local state. Do not invalidate the main
        // calendar/list or encode, validate and fsync the entire snapshot here.
        pendingQuickDraft = draft
        quickDraftSaveTask?.cancel()
        quickDraftSaveTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            guard !Task.isCancelled else { return }
            self?.flushQuickDraft()
        }
    }
    func flushQuickDraft() {
        quickDraftSaveTask?.cancel(); quickDraftSaveTask = nil
        guard let draft = pendingQuickDraft else { return }
        pendingQuickDraft = nil
        // A draft does not change tasks, reminders, shortcuts or the sync outbox.
        change(undo: false, notifyServices: false) { draft.apply(to: &$0.preferences) }
    }
    func clearQuickDraft() {
        quickDraftSaveTask?.cancel(); quickDraftSaveTask = nil; pendingQuickDraft = nil
        change(undo: false, notifyServices: false) { QuickCaptureDraft().apply(to: &$0.preferences) }
    }
    func update(_ id: UUID, _ action: (inout Item) -> Void) {
        let projected = item(id)
        change { snapshot in
            if !snapshot.items.contains(where: { $0.id == id }), let projected { snapshot.items.append(projected) }
            guard let index = snapshot.items.firstIndex(where: { $0.id == id }) else { return }
            let previous = snapshot.items[index]
            action(&snapshot.items[index]); snapshot.items[index].modified = Date()
            if previous.title != snapshot.items[index].title || previous.body != snapshot.items[index].body {
                let text = snapshot.items[index].title + "\n" + snapshot.items[index].body
                let names = Hashtags.names(in: text)
                let finished = Hashtags.names(in: snapshot.items[index].title, terminatedOnly: true) + Hashtags.names(in: snapshot.items[index].body, terminatedOnly: true)
                for name in names {
                    var tag = snapshot.tags.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
                    if tag == nil && finished.contains(name) {
                        let created = Tag(name: name, color: ProjectTagPalette.nextColor(in: snapshot)); snapshot.tags.append(created); tag = created
                    }
                    if let tag, !snapshot.items[index].tagIDs.contains(tag.id) { snapshot.items[index].tagIDs.append(tag.id) }
                }
            }
        }
    }
    func add(_ item: Item) { change { $0.items.append(item) }; selectedID = item.id }
    func createSection(_ name: String, in projectID: UUID) -> String? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "Введите название этапа" }
        guard let project = data.projects.first(where: { $0.id == projectID && !$0.archived }) else { return "Проект недоступен" }
        guard !project.sections.contains(where: { $0.localizedCaseInsensitiveCompare(name) == .orderedSame }) else { return "Этап с таким названием уже есть" }
        change { snapshot in
            if let index = snapshot.projects.firstIndex(where: { $0.id == projectID }) { snapshot.projects[index].sections.append(name) }
        }
        return data.projects.first(where: { $0.id == projectID })?.sections.contains(name) == true ? nil : "Не удалось сохранить этап"
    }
    @discardableResult func capture(_ parsed: ParsedTask, body: String = "", initialDate: Date? = nil) -> UUID? {
        guard !parsed.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        var item = parsed.item(); item.body = body
        if item.projectID == nil, let project, project.kind == .task { item.projectID = project.id }
        if case .tag(let id) = scope, !item.tagIDs.contains(id) { item.tagIDs.append(id) }
        if item.schedule == .unscheduled {
            if let initialDate { item.schedule = .timed(initialDate) }
            else if area == .tasks && (scope == .today || scope == .week) { item.schedule = .day(calendar.startOfDay(for: Date())) }
        }
        change { snapshot in
            for name in Hashtags.names(in: body) {
                var tag = snapshot.tags.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
                if tag == nil { let created = Tag(name: name, color: ProjectTagPalette.nextColor(in: snapshot)); snapshot.tags.append(created); tag = created }
                if let tag, !item.tagIDs.contains(tag.id) { item.tagIDs.append(tag.id) }
            }
            snapshot.items.append(item)
        }
        selectedID = item.id
        guard data.items.contains(where: { $0.id == item.id }) else { return nil }
        if scope == .completed || scope == .trash { scope = .inbox }
        return item.id
    }
    func complete(_ id: UUID) {
        guard let item = item(id), item.kind == .task, !item.deleted else { return }
        change { snapshot in
            if !snapshot.items.contains(where: { $0.id == id }) { snapshot.items.append(item) }
            guard let index = snapshot.items.firstIndex(where: { $0.id == id }) else { return }
            snapshot.items[index].completed.toggle()
            snapshot.items[index].modified = Date()
            if !item.completed, let next = RecurringCalendar.next(item, in: snapshot.items, calendar: calendar),
               !snapshot.items.contains(where: { $0.id == next.id || ($0.recurrenceSourceID == next.recurrenceSourceID && ($0.recurrenceOriginalDate ?? $0.schedule.date) == next.recurrenceOriginalDate) || $0.repeatParentID == id }) {
                snapshot.items.append(next)
            }
        }
        if !item.completed, data.items.first(where: { $0.id == id })?.completed == true {
            onTaskCompleted(data.preferences)
        }
    }
    func schedule(_ id: UUID, at date: Date) { update(id) { $0.schedule = .timed(date) } }
    func unschedule(_ id: UUID, clearDay: Bool = false) {
        update(id) { item in item.schedule = clearDay ? .unscheduled : item.schedule.date.map { .day(calendar.startOfDay(for: $0)) } ?? .unscheduled }
    }
    @discardableResult func returnToQueue(_ id: UUID) -> Bool {
        guard let value = item(id), value.kind == .task, !value.deleted, !value.completed else { endDrag(); return false }
        // Dropping into the undated view explicitly clears both date and clock.
        unschedule(id, clearDay: queueDateFilter == "Без даты")
        endDrag(); if calendarEditingID == id { calendarEditingID = nil }
        guard let saved = data.items.first(where: { $0.id == id }), !saved.schedule.isTimed else { return false }
        if !queue.contains(where: { $0.id == id }) {
            queueInboxOnly = false; resetQueueFilters()
        }
        return true
    }
    func delete(_ id: UUID) { update(id) { $0.deleted = true; $0.stickyOpen = false }; if selectedID == id { selectedID = nil } }
    func setTimeZone(_ identifier: String) {
        guard TimeZone(identifier: identifier) != nil else { return }
        let old = calendar, updated = Dates.calendar(zone: identifier)
        change { snapshot in
            for i in snapshot.items.indices {
                if case .day(let date) = snapshot.items[i].schedule,
                   let preserved = updated.date(from: old.dateComponents([.year,.month,.day], from: date)) { snapshot.items[i].schedule = .day(preserved) }
            }
            snapshot.preferences.timeZone = identifier
        }
    }
    func deleteTag(_ id: UUID) {
        guard let tag = data.tags.first(where: { $0.id == id }) else { return }
        change { snapshot in
            snapshot.tags.removeAll { $0.id == id }
            for i in snapshot.tags.indices where snapshot.tags[i].parentID == id { snapshot.tags[i].parentID = tag.parentID }
            for i in snapshot.items.indices { snapshot.items[i].tagIDs.removeAll { $0 == id } }
        }
        if scope == .tag(id) { scope = .all }
    }
    @discardableResult func acceptProjectDrop(_ payload: String, on projectID: UUID, after: Bool = false) -> Bool {
        guard let destination = activeProjects.first(where: { $0.id == projectID }) else { return false }
        if payload.hasPrefix("takt-project:") {
            guard let id = UUID(uuidString: String(payload.dropFirst(13))), id != projectID,
                  activeProjects.contains(where: { $0.id == id }) else { return false }
            moveProject(id, before: projectID, after: after); return true
        }
        guard let id = UUID(uuidString: payload), let source = item(id), !source.deleted,
              source.kind == destination.kind else { return false }
        if source.projectID != destination.id {
            update(id) { value in
                value.projectID = destination.id
                value.section = destination.sections.first ?? "Без раздела"
            }
        }
        endDrag()
        return data.items.first(where: { $0.id == id })?.projectID == destination.id
    }
    func moveProject(_ id: UUID, before target: UUID, after: Bool = false) {
        guard id != target else { return }
        change { snapshot in
            guard let from = snapshot.projects.firstIndex(where: { $0.id == id }),
                  let destination = snapshot.projects.first(where: { $0.id == target }) else { return }
            var project = snapshot.projects.remove(at: from)
            project.folder = destination.folder
            let to = snapshot.projects.firstIndex(where: { $0.id == target }) ?? snapshot.projects.count
            snapshot.projects.insert(project, at: min(snapshot.projects.count, to + (after ? 1 : 0)))
        }
    }
    @discardableResult func createNote() -> UUID {
        var item = Item(title: "", kind: .note)
        if case .tag(let id) = scope { item.tagIDs = [id] }
        if let project, project.kind == .note { item.projectID = project.id }
        add(item); return item.id
    }
    func move(_ id: UUID, before target: UUID) {
        guard id != target else { return }
        change { s in
            guard let from = s.items.firstIndex(where: { $0.id == id }),
                  let destination = s.items.first(where: { $0.id == target }) else { return }
            var value = s.items.remove(at: from)
            value.projectID = destination.projectID; value.section = destination.section
            let index = s.items.firstIndex(where: { $0.id == target }) ?? s.items.count
            s.items.insert(value, at: index)
        }
    }
    func undo() {
        guard let edit = past.last else { return }
        do {
            var previous = preservingStickyLayout(in: try edit.restoring(in: data))
            SyncEngine.enqueueChanges(in: &previous)
            let inverse = SnapshotEdit(before: data, after: previous)
            try database?.save(previous); future.append(inverse); data = previous; past.removeLast(); didSave()
        } catch { errorMessage = error.localizedDescription }
    }
    func redo() {
        guard let edit = future.last else { return }
        do {
            var next = preservingStickyLayout(in: try edit.restoring(in: data))
            SyncEngine.enqueueChanges(in: &next)
            let inverse = SnapshotEdit(before: data, after: next)
            try database?.save(next); past.append(inverse); data = next; future.removeLast(); didSave()
        } catch { errorMessage = error.localizedDescription }
    }
    func restore(_ snapshot: Snapshot) {
        quickDraftSaveTask?.cancel(); quickDraftSaveTask = nil; pendingQuickDraft = nil
        syncCoordinator?.disconnectApple(); syncCoordinator?.disconnectTickTick()
        change(undo: false) { $0 = snapshot }; past.removeAll(); future.removeAll()
    }
    // Content undo must not change the size or position of floating windows.
    private func preservingStickyLayout(in snapshot: Snapshot) -> Snapshot {
        var restored = snapshot
        let current = Dictionary(uniqueKeysWithValues: data.items.map { ($0.id, $0) })
        for index in restored.items.indices {
            guard let item = current[restored.items[index].id] else { continue }
            restored.items[index].stickyFrame = item.stickyFrame
            restored.items[index].stickyCollapsed = item.stickyCollapsed
            restored.items[index].stickyExpandedHeight = item.stickyExpandedHeight
        }
        return restored
    }
    func tagFamily(_ id: UUID) -> Set<UUID> {
        var result: Set<UUID> = [id]
        for tag in data.tags where tag.parentID == id { result.formUnion(tagFamily(tag.id)) }
        return result
    }
    func item(_ id: UUID) -> Item? { data.items.first { $0.id == id } ?? calendarItems.first { $0.id == id } }
    var externalEvents: [ExternalEvent] {
        guard isDemo || syncCoordinator?.appleVisible == true else { return [] }
        let available = Set(data.appleCalendar?.calendars.map(\.id) ?? [])
        return (data.appleCalendar?.events ?? []).filter { available.contains($0.calendarID) }.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.notes.localizedCaseInsensitiveContains(search) }
    }
    var calendarItems: [Item] {
        let start = calendar.dateInterval(of: calendarMode == "Месяц" ? .month : .weekOfYear, for: anchor)?.start ?? calendar.startOfDay(for: anchor)
        let lower = calendar.date(byAdding: .day, value: -7, to: start) ?? start
        let upper = calendar.date(byAdding: .day, value: calendarMode == "Месяц" ? 42 : 8, to: start) ?? start
        return RecurringCalendar.occurrences(items: data.items, from: lower, to: upper, calendar: calendar).filter {
            $0.kind == .task && !$0.deleted && matchesQuery($0, search)
        }.filter { item in !data.projects.contains { $0.id == item.projectID && $0.archived } }
    }
    var visibleItems: [Item] { items(in: scope, searchText: search) }
    func notes(deleted: Bool = false) -> [Item] {
        data.items.filter { item in
            guard item.kind == .note, item.deleted == deleted, matchesQuery(item, search) else { return false }
            if case .tag(let id) = scope { return !tagIDs(for: item).isDisjoint(with: tagFamily(id)) }
            if case .project(let id) = scope { return item.projectID == id }
            return true
        }.sorted { $0.modified > $1.modified }
    }
    func taskCount(in scope: Scope) -> Int { items(in: scope, searchText: "", activeOnly: true).count }
    func folderTaskCount(_ folder: String) -> Int { activeProjects.filter { $0.folder == folder && $0.kind == .task }.reduce(0) { $0 + taskCount(in: .project($1.id)) } }
    func isOverdue(_ item: Item) -> Bool { !item.completed && (item.schedule.date.map { $0 < calendar.startOfDay(for: Date()) } ?? false) }
    var overdueTasks: [Item] { items(in: .all, searchText: "", activeOnly: true).filter(isOverdue) }
    func postponeOverdueToToday() {
        let ids = Set(overdueTasks.map(\.id)), today = calendar.startOfDay(for: Date())
        change { snapshot in
            for i in snapshot.items.indices where ids.contains(snapshot.items[i].id) {
                let item = snapshot.items[i]
                if item.schedule.isTimed, let date = item.schedule.date {
                    let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
                    snapshot.items[i].schedule = .timed(calendar.date(bySettingHour: parts.hour ?? 9, minute: parts.minute ?? 0, second: parts.second ?? 0, of: today) ?? today)
                } else { snapshot.items[i].schedule = .day(today) }
                snapshot.items[i].modified = Date()
            }
        }
    }
    private func items(in scope: Scope, searchText: String, activeOnly: Bool = false) -> [Item] {
        func matchesSearch(_ item: Item) -> Bool { matchesQuery(item, searchText) }
        return data.items.filter { item in
            if scope == .trash { return item.deleted && matchesSearch(item) }
            guard !item.deleted else { return false }
            switch scope {
            case .tag: break // A tag belongs to notes as well as tasks.
            case .project(let id):
                guard item.kind == (data.projects.first { $0.id == id }?.kind ?? .task) else { return false }
            default: guard item.kind == (area == .notes ? .note : .task) else { return false }
            }
            if scope == .completed { return item.completed && matchesSearch(item) }
            if item.completed && (activeOnly || !data.preferences.showCompleted) { return false }
            if let id = item.projectID, data.projects.first(where: { $0.id == id })?.archived == true { return false }
            let matches: Bool
            switch scope {
            case .all, .completed, .trash: matches = true
            case .inbox: matches = item.projectID == nil
            case .project(let id): matches = item.projectID == id
            case .tag(let id): matches = !tagIDs(for: item).isDisjoint(with: tagFamily(id))
            case .today: matches = isOverdue(item) || (item.schedule.date.map { calendar.isDateInToday($0) } ?? false)
            case .week:
                let start = calendar.startOfDay(for: Date())
                let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
                matches = item.schedule.date.map { $0 >= start && $0 < end } ?? false
            }
            return matches && matchesSearch(item)
        }
    }
    /// Older notes can contain a valid hashtag without a stored tagID. Resolve it
    /// without rewriting the user's database or requiring an edit to the note.
    func tagIDs(for item: Item) -> Set<UUID> {
        let names = Set(Hashtags.names(in: item.title + "\n" + item.body).map { $0.lowercased() })
        return Set(item.tagIDs).union(data.tags.filter { names.contains($0.name.lowercased()) }.map(\.id))
    }
    func matchesQuery(_ item: Item, _ query: String) -> Bool {
        if query.trimmingCharacters(in: .whitespacesAndNewlines) == "#" { return !tagIDs(for: item).isEmpty }
        let terms = Hashtags.searchTerms(in: query)
        for name in terms.tags {
            let exact = data.tags.filter { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
            let matches = exact.isEmpty ? data.tags.filter { $0.name.localizedCaseInsensitiveContains(name) } : exact
            let ids = matches.reduce(into: Set<UUID>()) { $0.formUnion(tagFamily($1.id)) }
            if tagIDs(for: item).isDisjoint(with: ids) { return false }
        }
        return terms.text.isEmpty || (item.title + " " + item.body + " " + item.tagIDs.compactMap { id in data.tags.first { $0.id == id }?.name }.joined(separator: " ")).localizedCaseInsensitiveContains(terms.text)
    }
    var queue: [Item] {
        let values = items(in: .all, searchText: queueSearch, activeOnly: true).filter { item in
            guard !item.schedule.isTimed, !queueInboxOnly || item.projectID == nil,
                  queueProjectID == nil || item.projectID == queueProjectID,
                  queueTagID == nil || !tagIDs(for: item).isDisjoint(with: tagFamily(queueTagID!)),
                  queuePriority == nil || item.priority == queuePriority else { return false }
            switch queueDateFilter {
            case "Без даты": return item.schedule.date == nil
            case "С датой": return item.schedule.date != nil
            case "Просрочено": return isOverdue(item)
            default: return true
            }
        }
        return sorted(values, by: queueSorting)
    }
    var queueHasFilters: Bool { queueProjectID != nil || queueTagID != nil || queuePriority != nil || queueDateFilter != "Без времени" || !queueSearch.isEmpty }
    func resetQueueFilters() { queueProjectID = nil; queueTagID = nil; queuePriority = nil; queueDateFilter = "Без времени"; queueSearch = "" }
    func projectName(_ id: UUID?) -> String { data.projects.first { $0.id == id }?.name ?? "Входящие" }
    func color(_ item: Item) -> String { data.projects.first { $0.id == item.projectID }?.color ?? "598BFF" }
    func sorted(_ items: [Item], by order: Sorting? = nil) -> [Item] {
        items.sorted { a, b in
            switch order ?? sorting {
            case .manual: return data.items.firstIndex(where: { $0.id == a.id })! < data.items.firstIndex(where: { $0.id == b.id })!
            case .date: return (a.schedule.date ?? .distantFuture) < (b.schedule.date ?? .distantFuture)
            case .priority: return (a.priority == 0 ? 4 : a.priority) < (b.priority == 0 ? 4 : b.priority)
            case .title: return a.title.localizedStandardCompare(b.title) == .orderedAscending
            case .duration: return a.duration < b.duration
            }
        }
    }
    var groups: [TaskGroup] {
        let items = sorted(visibleItems)
        guard scope == .today else { return grouped(items) }
        let overdue = items.filter(isOverdue)
        return (overdue.isEmpty ? [] : [TaskGroup(id: "Просрочено", items: overdue)]) + grouped(items.filter { !isOverdue($0) })
    }
    private func grouped(_ items: [Item]) -> [TaskGroup] {
        if grouping == .none { return [TaskGroup(id: "Все", items: items)] }
        if grouping == .date {
            let today = calendar.startOfDay(for: Date()), tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
            return ["Просрочено", "Сегодня", "Завтра", "Позже", "Без даты"].compactMap { name in
                let values = items.filter { item in
                    guard let d = item.schedule.date else { return name == "Без даты" }
                    if d < today { return name == "Просрочено" }
                    if calendar.isDate(d, inSameDayAs: today) { return name == "Сегодня" }
                    if calendar.isDate(d, inSameDayAs: tomorrow) { return name == "Завтра" }
                    return name == "Позже"
                }
                return values.isEmpty ? nil : TaskGroup(id: name, items: values)
            }
        }
        let keys: [String]
        switch grouping {
        case .project: keys = ["Входящие"] + activeProjects.filter { project in items.contains { $0.projectID == project.id } }.map(\.name)
        case .section: keys = project?.sections ?? Array(Set(items.map(\.section))).sorted()
        case .priority: keys = ["Высокий", "Средний", "Низкий", "Без приоритета"]
        case .tag: keys = data.tags.map { "#" + $0.name } + ["Без тегов"]
        default: keys = []
        }
        return keys.compactMap { key in
            let group = items.filter { item in
                switch grouping {
                case .project: return projectName(item.projectID) == key
                case .section: return item.section == key
                case .priority: return Self.priorityTitle(item.priority) == key
                case .tag: return tagIDs(for: item).isEmpty ? key == "Без тегов" : tagIDs(for: item).contains { id in data.tags.first { $0.id == id }.map { "#" + $0.name == key } ?? false }
                default: return true
                }
            }
            return group.isEmpty ? nil : TaskGroup(id: key, items: group)
        }
    }
    static func priorityTitle(_ priority: Int) -> String { [0:"Без приоритета",1:"Высокий",2:"Средний",3:"Низкий"][priority] ?? "Без приоритета" }
    func time(_ date: Date) -> String { let f = DateFormatter(); f.timeZone = calendar.timeZone; f.dateFormat = "HH:mm"; return f.string(from: date) }
    func dayLabel(_ date: Date) -> String { let f = DateFormatter(); f.locale = Locale(identifier: "ru_RU"); f.timeZone = calendar.timeZone; f.dateFormat = "d MMM"; return f.string(from: date) }
    func durationLabel(_ minutes: Int) -> String { minutes % 60 == 0 ? "\(minutes / 60) ч" : "\(minutes) мин" }

    private static func demo() -> Snapshot {
        var s = Snapshot()
        let work = Project(name: "Работа", color: "598BFF"), personal = Project(name: "Личное", color: "5BC9A2")
        s.projects = [work, personal, Project(name: "Заметки", color: "AD94E8", kind: .note)]
        s.tags = [Tag(name: "документы"), Tag(name: "идеи", color: "E6A467")]
        let c = Dates.calendar(), day = c.startOfDay(for: Date())
        for (title, offset, hour, duration, project) in [
            ("План недели", -2, 9, 60, work.id), ("Подготовить отчёт", 0, 14, 60, work.id),
            ("Созвон по проекту", 0, 14, 60, personal.id), ("Прогулка", 0, 18, 45, personal.id)
        ] {
            var item = Item(title: title, projectID: project); item.duration = duration
            item.schedule = .timed(c.date(bySettingHour: hour, minute: 0, second: 0, of: c.date(byAdding: .day, value: offset, to: day)!)!)
            s.items.append(item)
        }
        for (title, minutes) in [("Набросать идеи",30), ("Обновить портфолио",90), ("Записаться к врачу",15)] {
            var item = Item(title: title, projectID: work.id); item.duration = minutes; item.tagIDs = [s.tags[1].id]; s.items.append(item)
        }
        var note = Item(title: "Идеи для проекта", kind: .note, projectID: s.projects[2].id)
        note.body = "## Следующий шаг\nСобрать первые наброски.\n\n- Обсудить структуру\n- Выбрать главное"; s.items.append(note)
        return s
    }
}

enum CreationKind: Identifiable {
    case project(UUID?), tag(UUID?), section(UUID)
    var id: String { String(describing: self) }
}
