import AppKit
import SwiftUI
import TaktCore

extension AppState {
    func isProjectedOccurrence(_ item: Item) -> Bool {
        item.recurrenceSourceID != nil && !data.items.contains { $0.id == item.id }
    }

    func recurringMoveLabel(for item: Item) -> String? {
        guard item.recurrence != .none else { return nil }
        if item.recurrenceSourceID != nil || item.repeatParentID != nil || item.externalRecurrence == true {
            return "Этот повтор"
        }
        return "Сдвиг серии"
    }
    var compactTaskList: Bool {
        data.workspaceOptions?.compactTaskLists.contains(scopeKey) == true
    }

    func toggleCompactTaskList() {
        let key = scopeKey
        change(undo: false, notifyServices: false) { snapshot in
            var options = snapshot.workspaceOptions ?? LocalWorkspaceOptions()
            if options.compactTaskLists.remove(key) == nil { options.compactTaskLists.insert(key) }
            snapshot.workspaceOptions = options
        }
    }

    var savedQueueFilters: [SavedQueueFilter] { data.workspaceOptions?.queueFilters ?? [] }

    func saveQueueFilter(named input: String) -> Bool {
        let name = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        let existing = savedQueueFilters.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
        let filter = SavedQueueFilter(id: existing?.id ?? UUID(), name: name, inboxOnly: queueInboxOnly,
            projectID: queueInboxOnly ? nil : queueProjectID, tagID: queueTagID, priority: queuePriority,
            dateFilter: queueDateFilter, search: queueSearch, sorting: queueSorting.rawValue)
        change(undo: false, notifyServices: false) { snapshot in
            var options = snapshot.workspaceOptions ?? LocalWorkspaceOptions()
            if let index = options.queueFilters.firstIndex(where: { $0.id == filter.id }) { options.queueFilters[index] = filter }
            else { options.queueFilters.append(filter) }
            snapshot.workspaceOptions = options
        }
        return savedQueueFilters.contains(filter)
    }

    func isQueueFilterAvailable(_ filter: SavedQueueFilter) -> Bool {
        (filter.projectID.map { id in activeProjects.contains { $0.id == id && $0.kind == .task } } ?? true)
            && (filter.tagID.map { id in data.tags.contains { $0.id == id } } ?? true)
    }

    func matchesQueueFilter(_ filter: SavedQueueFilter) -> Bool {
        filter.inboxOnly == queueInboxOnly && filter.projectID == (queueInboxOnly ? nil : queueProjectID)
            && filter.tagID == queueTagID && filter.priority == queuePriority && filter.dateFilter == queueDateFilter
            && filter.search == queueSearch && filter.sorting == queueSorting.rawValue
    }

    func applyQueueFilter(_ filter: SavedQueueFilter) {
        guard isQueueFilterAvailable(filter) else { return }
        queueInboxOnly = filter.inboxOnly
        queueProjectID = filter.inboxOnly ? nil : filter.projectID
        queueTagID = filter.tagID
        queuePriority = filter.priority
        queueDateFilter = filter.dateFilter
        queueSearch = filter.search
        queueSorting = Sorting(rawValue: filter.sorting) ?? .manual
    }

    func removeQueueFilter(_ id: UUID) {
        change(undo: false, notifyServices: false) { $0.workspaceOptions?.queueFilters.removeAll { $0.id == id } }
    }

    func recordFocusCompletion(_ completion: FocusCompletion) {
        guard item(completion.taskID)?.kind == .task,
              data.workspaceOptions?.completedFocus.contains(completion) != true else { return }
        change(undo: false, notifyServices: false) { snapshot in
            var options = snapshot.workspaceOptions ?? LocalWorkspaceOptions()
            options.completedFocus.append(completion)
            snapshot.workspaceOptions = options
        }
    }

    func focusedMinutes(for id: UUID) -> Int {
        let sessions = data.workspaceOptions?.completedFocus ?? []
        return sessions.count(where: { $0.taskID == id }) * Pomodoro.focusMinutes
    }

    func taskTable(_ items: [Item]) -> String {
        let date = DateFormatter()
        date.locale = Locale(identifier: "ru_RU")
        date.timeZone = calendar.timeZone
        date.dateFormat = "dd.MM.yyyy"
        let tagNames = Dictionary(uniqueKeysWithValues: data.tags.map { ($0.id, $0.name) })
        var seen = Set<UUID>()
        var rows = [["Название", "Проект", "Этап", "Дата", "Начало", "Конец", "План, мин", "Фокус, мин", "Приоритет", "Теги", "Статус"]]
        for item in items where item.kind == .task && seen.insert(item.id).inserted {
            let start = item.schedule.date
            let status = item.deleted ? "В корзине" : item.completed ? "Завершена" : item.wontDoAt != nil ? "Не буду выполнять" : "Открыта"
            rows.append([item.title, projectName(item.projectID), item.projectID == nil ? "" : item.section,
                start.map(date.string(from:)) ?? "", item.schedule.isTimed ? start.map(time) ?? "" : "",
                item.end.map(time) ?? "", String(item.duration), String(focusedMinutes(for: item.id)),
                Self.priorityTitle(item.priority), item.tagIDs.compactMap { tagNames[$0] }.joined(separator: ", "), status])
        }
        return rows.map { $0.map(Self.tableCell).joined(separator: "\t") }.joined(separator: "\n")
    }

    func copyTaskTable(_ items: [Item]) {
        let table = taskTable(items)
        let clipboard = NSPasteboard.general
        let entry = NSPasteboardItem()
        entry.setString(table, forType: .tabularText)
        entry.setString(table, forType: .string)
        clipboard.clearContents()
        if clipboard.writeObjects([entry]) { tableCopyReceipt = UUID() }
        else { errorMessage = "Не удалось скопировать таблицу" }
    }

    private static func tableCell(_ value: String) -> String {
        let line = value.components(separatedBy: .newlines.union(CharacterSet(charactersIn: "\t"))).joined(separator: " ")
        let formula = line.drop(while: \.isWhitespace).first.map { "=+-@".contains($0) } ?? false
        return formula ? "'" + line : line
    }

    func moveTask(_ id: UUID, toDay date: Date) {
        guard let task = item(id), task.isActiveTask else { return }
        let day = calendar.startOfDay(for: date)
        let slot = task.schedule.date.flatMap { start -> Date? in
            guard task.schedule.isTimed else { return nil }
            let time = calendar.dateComponents([.hour, .minute, .second], from: start)
            return calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: time.second ?? 0, of: day)
        }
        update(id) { $0.schedule = slot.map(Schedule.timed) ?? .day(day) }
    }

    @discardableResult
    func moveTask(_ id: UUID, toSection section: String, in projectID: UUID) -> Bool {
        guard let task = item(id), task.kind == .task, !task.deleted,
              activeProjects.contains(where: { $0.id == projectID && $0.kind == .task && $0.sections.contains(section) }) else { return false }
        update(id) { $0.projectID = projectID; $0.section = section }
        endDrag()
        return item(id).map { $0.projectID == projectID && $0.section == section } == true
    }

    func openLinkedTask(_ id: UUID) {
        guard let task = item(id), task.kind == .task else { errorMessage = "Связанная задача недоступна"; return }
        area = .tasks
        scope = task.deleted ? .trash : task.completed ? .completed : task.wontDoAt != nil ? .wontDo : task.projectID.map(Scope.project) ?? .inbox
        search = ""
        select(id)
        showMainForTaskLink()
    }

    func showTaskActions(_ id: UUID) {
        guard let task = item(id), task.kind == .task, !task.deleted else { return }
        calendarEditingID = nil
        taskActionsID = id
    }

    @discardableResult
    func createTaskFromNoteLine(noteID: UUID, sourceLine: String, occurrence: Int, title: String, completed: Bool, suffix: String = "") -> UUID? {
        guard let note = data.items.first(where: { $0.id == noteID && $0.kind == .note && !$0.deleted }),
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, occurrence >= 0 else { return nil }
        let sourceKey = Self.noteLineKey(sourceLine)
        var matches = 0
        var target: Range<String.Index>?
        var start = note.body.startIndex
        while start < note.body.endIndex {
            let end = note.body[start...].firstIndex(where: \.isNewline) ?? note.body.endIndex
            if Self.noteLineKey(String(note.body[start..<end])) == sourceKey {
                if matches == occurrence { target = start..<end; break }
                matches += 1
            }
            if end == note.body.endIndex { break }
            start = note.body.index(after: end)
        }
        guard let target else { errorMessage = "Не удалось найти эту строку. Поставьте курсор в строку заметки и повторите."; return nil }
        var task = Item(title: title)
        task.completed = completed
        if completed { task.completedAt = Date() }
        task.tagIDs = data.tags.filter { tag in Hashtags.names(in: title).contains { $0.localizedCaseInsensitiveCompare(tag.name) == .orderedSame } }.map(\.id)
        let label = title.replacingOccurrences(of: "[", with: "(").replacingOccurrences(of: "]", with: ")")
        let original = String(note.body[target])
        let prefix = original.range(of: #"^\s*(?:[-*+] |\d+[.)] )?"#, options: .regularExpression).map { String(original[$0]) } ?? ""
        let link = "\(prefix)[\(label)](tolk-task://item/\(task.id.uuidString.lowercased()))\(suffix)"
        var updated = note.body
        updated.replaceSubrange(target, with: link)
        change { snapshot in
            guard let index = snapshot.items.firstIndex(where: { $0.id == noteID && $0.body == note.body }) else { return }
            snapshot.items[index].body = updated
            snapshot.items[index].modified = Date()
            snapshot.items.append(task)
        }
        return data.items.contains(where: { $0.id == task.id }) ? task.id : nil
    }

    private static func noteLineKey(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: #"^(?:[-*+]|\d+[.)])\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^\[X\]"#, with: "[x]", options: .regularExpression)
    }
}

struct ProjectedOccurrenceOutline: ViewModifier {
    let state: AppState
    let item: Item
    let radius: CGFloat

    func body(content: Content) -> some View {
        if state.isProjectedOccurrence(item) {
            content.overlay {
                RoundedRectangle(cornerRadius: radius)
                    .stroke(Color(hex: state.color(item)).opacity(0.75), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    .allowsHitTesting(false)
            }.help("Будущий повтор. Перенос изменит только этот повтор.").accessibilityHint("Будущий повтор")
        } else { content }
    }
}

struct TaskActionPalette: View {
    let state: AppState
    let taskID: UUID
    @ViewState private var query = ""
    @ViewState private var selected = 0
    @FocusState private var searchFocused: Bool
    @Environment(\.workspaceHeight) private var workspaceHeight

    private struct Action {
        let title: String
        let icon: String
        let run: () -> Void
    }

    private var actions: [Action] {
        guard let task = state.item(taskID), !task.deleted, task.kind == .task else { return [] }
        var options: [Action] = []
        if task.isActiveTask {
            let today = state.calendar.startOfDay(for: Date())
            let presets = [("Перенести на сегодня", 0), ("Перенести на завтра", 1), ("Перенести через неделю", 7)]
            for (title, offset) in presets {
                guard let day = state.calendar.date(byAdding: .day, value: offset, to: today) else { continue }
                options.append(Action(title: title, icon: "calendar") { state.moveTask(taskID, toDay: day) })
            }
            options.append(Action(title: "Начать фокус", icon: "timer") { state.startFocus(task) })
            if task.schedule.isTimed {
                options.append(Action(title: "Снять время", icon: "clock") { state.unschedule(taskID) })
            }
            if task.schedule.date != nil {
                options.append(Action(title: "Убрать дату и время", icon: "calendar.badge.minus") { state.unschedule(taskID, clearDay: true) })
            }
            options.append(Action(title: "Завершить задачу", icon: "checkmark.circle") { state.complete(taskID) })
            for project in state.activeProjects where project.kind == .task && project.id != task.projectID {
                guard let section = project.sections.first else { continue }
                options.append(Action(title: "Перенести в проект «\(project.name)»", icon: "folder") {
                    state.moveTask(taskID, toSection: section, in: project.id)
                })
            }
        } else {
            options.append(Action(title: "Вернуть в работу", icon: "arrow.uturn.backward") {
                if task.wontDoAt != nil { state.toggleWontDo(taskID) } else { state.complete(taskID) }
            })
        }
        let words = query.split(whereSeparator: \.isWhitespace)
        return options.filter { option in words.allSatisfy { option.title.localizedCaseInsensitiveContains($0) } }
    }

    var body: some View {
        let matches = actions
        ZStack(alignment: .top) {
            Color.black.opacity(0.18).contentShape(Rectangle()).onTapGesture(perform: dismiss).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Действие для задачи", text: $query)
                        .textFieldStyle(.plain).font(.system(size: 15)).focused($searchFocused)
                        .onChange(of: query) { _, _ in selected = 0 }
                        .onSubmit { if matches.indices.contains(selected) { perform(matches[selected]) } }
                    IconButton(symbol: "xmark", help: "Закрыть быстрые действия", action: dismiss)
                }.padding(.horizontal, 14).padding(.vertical, 9)
                Text(state.item(taskID)?.title ?? "").font(.system(size: 11)).foregroundStyle(.secondary)
                    .lineLimit(1).padding(.horizontal, 16).padding(.bottom, 9)
                Divider()
                if matches.isEmpty {
                    Text("Нет подходящих действий").foregroundStyle(.secondary).padding(16)
                } else {
                    ScrollViewReader { scroll in
                        ScrollView {
                            VStack(spacing: 1) {
                                ForEach(Array(matches.enumerated()), id: \.offset) { index, action in
                                    Button { perform(action) } label: {
                                        HStack(spacing: 9) {
                                            Image(systemName: action.icon).foregroundStyle(.secondary).frame(width: 18)
                                            Text(action.title).lineLimit(1)
                                            Spacer()
                                            if index == selected { Image(systemName: "return").foregroundStyle(.secondary) }
                                        }.padding(.horizontal, 9).frame(height: 32).contentShape(Rectangle())
                                    }.buttonStyle(.plain).id(index)
                                        .background(index == selected ? Palette.accent.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 5))
                                }
                            }.padding(6)
                        }.frame(height: min(CGFloat(matches.count * 33 + 12), max(100, min(252, (workspaceHeight ?? 440) - 166))))
                            .onChange(of: selected) { _, row in scroll.scrollTo(row) }
                    }
                }
            }.frame(width: 398)
                .background(Palette.sidebar, in: RoundedRectangle(cornerRadius: 10))
                .overlay { RoundedRectangle(cornerRadius: 10).stroke(Palette.line) }
                .shadow(color: .black.opacity(0.22), radius: 16, y: 6)
                .padding(.top, 42)
        }.onAppear { searchFocused = true }
            .onExitCommand(perform: dismiss)
            .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                guard !matches.isEmpty else { return .ignored }
                let direction = press.key == .downArrow ? 1 : -1
                selected = (selected + direction + matches.count) % matches.count
                return .handled
            }
    }

    private func dismiss() { state.taskActionsID = nil }
    private func perform(_ action: Action) { dismiss(); action.run() }
}
