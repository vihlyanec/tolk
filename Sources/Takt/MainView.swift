import SwiftUI
import TaktCore

// THESIS: A familiar, dense Mac workspace for capturing tasks and planning time.
// OWN-WORLD: TickTick-like rails, SF type, thin dividers, blue accent, translucent events.
// STORY: Capture, organize, drag into a week, complete in place. Notes remain independent.
// FIRST VIEWPORT: grouped task list + projects/tags; calendar opens seven-day grid + planning queue.
// FORM: User-pinned conventional task manager; approved list and calendar overlap study.
// FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, and DESIGN.md
struct MainView: View {
    @Bindable var state: AppState
    var body: some View {
        VStack(spacing: 0) {
            if let error = state.errorMessage {
                HStack { Image(systemName: "exclamationmark.triangle"); Text(error).textSelection(.enabled); Spacer(); IconButton(symbol: "xmark", help: "Скрыть сообщение") { state.errorMessage = nil } }
                    .font(.system(size: 12)).padding(.horizontal, 12).padding(.vertical, 5).background(Color.red.opacity(0.16))
            }
            HStack(spacing: 0) {
                rail
                if state.sidebarVisible && state.area == .tasks { Sidebar(state: state).frame(width: 252); Divider() }
                Group {
                    if state.area == .calendar { CalendarView(state: state) }
                    else if state.area == .notes { NotesWorkspace(state: state) }
                    else { TaskListView(state: state) }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .font(.system(size: 13)).tint(Palette.accent).background(Palette.canvas)
        .preferredColorScheme(state.data.preferences.theme == "dark" ? .dark : state.data.preferences.theme == "light" ? .light : nil)
        .sheet(item: $state.sheet) { CreationSheet(state: state, kind: $0) }
        .onChange(of: state.area) { _, area in
            state.calendarEditingID = nil; state.endDrag(); state.search = ""
            if area == .calendar { state.scope = .all; state.search = "" }
        }
    }
    private var rail: some View {
        VStack(spacing: 16) {
            BrandMark().frame(width: 36, height: 36).padding(.top, 12).padding(.bottom, 10)
            ForEach(Area.allCases, id: \.self) { area in
                let symbol = area == .tasks ? "checklist" : area == .calendar ? "calendar" : "square.and.pencil"
                let title = area == .tasks ? "Задачи" : area == .calendar ? "Календарь" : "Заметки"
                IconButton(symbol: symbol, help: title, tint: state.area == area ? Palette.accent : .secondary) {
                    state.area = area; state.scope = .all; state.selectedID = nil
                }.frame(width: 38, height: 38).background(state.area == area ? Palette.accent.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 8))
            }
            Spacer()
            if state.area != .calendar { IconButton(symbol: "sidebar.left", help: state.area == .notes ? "Показать/скрыть заметки" : "Показать/скрыть проекты") { state.sidebarVisible.toggle() } }
            IconButton(symbol: "gearshape", help: "Настройки") { state.showSettings() }.padding(.bottom, 16)
        }.frame(width: 52).background(Color.primary.opacity(0.025)).overlay(alignment: .trailing) { Rectangle().fill(Palette.line).frame(width: 1) }
    }
}

struct Sidebar: View {
    @Bindable var state: AppState
    @ViewState private var projectDropTarget: UUID?
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) { Image(systemName: "magnifyingglass").foregroundStyle(.secondary); TextField("Поиск задач и заметок", text: $state.search).textFieldStyle(.plain) }
                .padding(8).background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 6)).padding(.bottom, 16)
            nav("Все", symbol: "square.stack.3d.up", scope: .all)
            nav("Входящие", symbol: "tray", scope: .inbox)
            if state.area != .notes {
                nav("Сегодня", symbol: "sun.max", scope: .today)
                nav("Следующие 7 дней", symbol: "calendar.badge.plus", scope: .week)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    sectionHeading("Проекты") { state.sheet = .project(nil) }.padding(.top, 22)
                    ForEach(Array(Set(state.activeProjects.map(\.folder))).sorted(), id: \.self) { folder in
                        if !folder.isEmpty { HStack { Text(folder); Spacer(); countBadge(state.folderTaskCount(folder)) }.font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.top, 10).padding(.horizontal, 8) }
                        ForEach(state.activeProjects.filter { $0.folder == folder }) { project in
                            Button {
                                state.scope = .project(project.id); state.selectedID = nil
                                if project.kind == .note { state.area = .notes }
                                else if state.area == .notes { state.area = .tasks }
                            } label: {
                                HStack(spacing: 9) {
                                    Image(systemName: project.kind == .note ? "note.text" : "circle.fill").foregroundStyle(Color(hex: project.color)).font(.system(size: project.kind == .note ? 13 : 9)).frame(width: 16)
                                    Text(project.name).lineLimit(1).layoutPriority(1); Spacer(minLength: 8); countBadge(state.taskCount(in: .project(project.id)))
                                }.padding(.horizontal, 8).frame(height: 32).contentShape(Rectangle())
                            }.buttonStyle(.plain).background(projectDropTarget == project.id ? Palette.accent.opacity(0.26) : state.scope == .project(project.id) ? Palette.accent.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 5))
                                .onDrag { NSItemProvider(object: ("takt-project:" + project.id.uuidString) as NSString) }
                                .dropDestination(for: String.self, action: { strings, _ in
                                    guard let raw = strings.first else { return false }
                                    projectDropTarget = nil
                                    return state.acceptProjectDrop(raw, on: project.id)
                                }, isTargeted: { target in projectDropTarget = target ? project.id : nil })
                                .overlay(alignment: .top) { if projectDropTarget == project.id { Rectangle().fill(Palette.accent).frame(height: 2) } }
                                .contextMenu {
                                    Button("Переместить выше") { shiftProject(project, by: -1) }.disabled(projectPeers(project).first?.id == project.id)
                                    Button("Переместить ниже") { shiftProject(project, by: 1) }.disabled(projectPeers(project).last?.id == project.id)
                                    Divider()
                                    Button("Изменить проект") { state.sheet = .project(project.id) }
                                    Button("Добавить раздел") { state.sheet = .section(project.id) }
                                    Button("Архивировать") { state.change { s in if let i = s.projects.firstIndex(where: { $0.id == project.id }) { s.projects[i].archived = true } }; state.scope = .all }
                                }
                        }
                    }
                    sectionHeading("Теги") { state.sheet = .tag(nil) }.padding(.top, 22)
                    tagTree(parent: nil, level: 0)
                    if state.data.tags.isEmpty { Text("Создайте первый тег через +").font(.system(size: 11)).foregroundStyle(.secondary).padding(8) }
                }
            }
            Divider().padding(.vertical, 8)
            nav("Завершённые", symbol: "checkmark.circle", scope: .completed)
            nav("Корзина", symbol: "trash", scope: .trash)
            Text(state.isDemo ? "Демо · вымышленные данные" : "Толк · локально на Mac").font(.system(size: 10)).foregroundStyle(.secondary).padding(.top, 10).padding(.leading, 8)
        }.padding(12).background(Palette.sidebar)
    }
    private func countBadge(_ count: Int) -> some View { Text("\(count)").font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary).fixedSize().frame(minWidth: 18, alignment: .trailing) }
    private func projectPeers(_ project: Project) -> [Project] { state.activeProjects.filter { $0.folder == project.folder } }
    private func shiftProject(_ project: Project, by delta: Int) {
        let peers = projectPeers(project)
        guard let i = peers.firstIndex(where: { $0.id == project.id }), peers.indices.contains(i + delta) else { return }
        if delta < 0 { state.moveProject(project.id, before: peers[i + delta].id) }
        else { state.moveProject(peers[i + delta].id, before: project.id) }
    }
    private func nav(_ title: String, symbol: String, scope: Scope) -> some View {
        Button { state.scope = scope; state.selectedID = nil } label: {
            HStack(spacing: 9) { Image(systemName: symbol).frame(width: 17); Text(title).lineLimit(1).layoutPriority(1); Spacer(minLength: 8); countBadge(state.taskCount(in: scope)) }
                .padding(.horizontal, 8).frame(height: 33).contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(state.scope == scope ? Palette.accent : .primary)
            .background(state.scope == scope ? Palette.accent.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 5))
    }
    private func sectionHeading(_ name: String, action: @escaping () -> Void) -> some View {
        HStack { Text(name).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary); Spacer(); IconButton(symbol: "plus", help: "Добавить: \(name)", action: action) }.padding(.leading, 8)
    }
    private func tagTree(parent: UUID?, level: Int) -> AnyView {
        AnyView(ForEach(state.data.tags.filter { $0.parentID == parent }) { tag in
            VStack(alignment: .leading, spacing: 0) {
                Button { state.scope = .tag(tag.id); state.selectedID = nil } label: {
                    HStack(spacing: 8) { Image(systemName: "number").foregroundStyle(Color(hex: tag.color)); Text(tag.name).lineLimit(1).layoutPriority(1); Spacer(minLength: 8); countBadge(state.taskCount(in: .tag(tag.id))) }
                        .padding(.leading, CGFloat(8 + level * 12)).padding(.trailing, 8).frame(height: 30).contentShape(Rectangle())
                }.buttonStyle(.plain).background(state.scope == .tag(tag.id) ? Palette.accent.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 5))
                    .contextMenu { Button("Изменить тег") { state.sheet = .tag(tag.id) }; Divider(); Button("Удалить тег", role: .destructive) { state.deleteTag(tag.id) } }
                tagTree(parent: tag.id, level: level + 1)
            }
        })
    }
}

struct TaskListView: View {
    @Bindable var state: AppState
    @ViewState private var collapsed: Set<String> = []
    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    Text(state.title).font(.system(size: 23, weight: .semibold)).lineLimit(1)
                    Spacer()
                    if let project = state.project {
                        Picker("Вид", selection: Binding(get: { project.kanban }, set: { value in state.change { s in if let i = s.projects.firstIndex(where: { $0.id == project.id }) { s.projects[i].kanban = value } } })) {
                            Text("Список").tag(false); Text("Канбан").tag(true)
                        }.pickerStyle(.segmented).labelsHidden().frame(width: 160)
                    }
                    Button { state.area == .notes ? state.showSticky(nil) : state.showQuick(nil) } label: { Label(state.area == .notes ? "Заметка" : "Задача", systemImage: "plus") }.buttonStyle(.borderedProminent)
                    if let id = state.selectedID, state.selected?.deleted == false { IconButton(symbol: "trash", help: "Удалить выбранную задачу") { state.delete(id) } }
                    IconButton(symbol: "sidebar.right", help: "Показать/скрыть детали") { state.inspectorVisible.toggle() }
                }.padding(22)
                HStack(spacing: 8) {
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            Picker("Группировать", selection: Binding(get: { state.grouping }, set: { state.grouping = $0 })) { ForEach(Grouping.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.frame(width: 220)
                            Picker("Сортировать", selection: Binding(get: { state.sorting }, set: { state.sorting = $0 })) { ForEach(Sorting.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.frame(width: 205)
                        }.fixedSize(horizontal: true, vertical: false)
                        HStack {
                            Menu { ForEach(Grouping.allCases, id: \.self) { value in Button(value.rawValue) { state.grouping = value } } } label: { Label(state.grouping.rawValue, systemImage: "rectangle.3.group") }.help("Группировать")
                            Menu { ForEach(Sorting.allCases, id: \.self) { value in Button(value.rawValue) { state.sorting = value } } } label: { Label(state.sorting.rawValue, systemImage: "arrow.up.arrow.down") }.help("Сортировать")
                        }
                    }
                    Spacer(minLength: 4)
                    Text("\(state.visibleItems.count)").foregroundStyle(.secondary)
                }.padding(.horizontal, 22).padding(.bottom, 14)
                if state.area != .notes && state.scope != .trash && state.scope != .completed { InlineQuickEntry(state: state) }
                Divider()
                if state.visibleItems.isEmpty {
                    EmptyState(symbol: state.area == .notes ? "note.text" : "checkmark.circle", title: "Пока пусто", detail: state.search.isEmpty ? "Добавьте первую запись. Проекты и теги можно создать слева." : "По этому запросу ничего не найдено.")
                } else if state.project?.kanban == true { kanban }
                else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(state.groups) { group in
                                if state.grouping != .none || (state.scope == .today && group.id == "Просрочено") {
                                    HStack {
                                    Button {
                                        if collapsed.contains(group.id) { collapsed.remove(group.id) } else { collapsed.insert(group.id) }
                                    } label: {
                                        HStack(spacing: 8) { Image(systemName: collapsed.contains(group.id) ? "chevron.right" : "chevron.down").font(.system(size: 10)); Text(group.id).fontWeight(.semibold); Text("\(group.items.count)").foregroundStyle(.secondary); Spacer() }.contentShape(Rectangle())
                                    }.buttonStyle(.plain)
                                    if state.scope == .today && group.id == "Просрочено" {
                                        Button("Отложить") { state.postponeOverdueToToday() }.buttonStyle(.bordered).controlSize(.small).help("Перенести все просроченные задачи на сегодня, сохранив время")
                                    }
                                    }.padding(.top, 22).padding(.bottom, 12)
                                }
                                if !collapsed.contains(group.id) { ForEach(group.items) { item in TaskRow(state: state, item: item) } }
                            }
                        }.padding(.horizontal, 20).padding(.bottom, 24)
                    }
                }
            }.frame(minWidth: 340, maxWidth: .infinity)
            if state.inspectorVisible, let id = state.selectedID {
                ItemInspector(state: state, id: id).frame(minWidth: 285, idealWidth: 330, maxWidth: 420)
            }
        }
    }
    private var kanban: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(state.project?.sections ?? ["Без раздела"], id: \.self) { section in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack { Text(section).fontWeight(.semibold); Spacer(); Text("\(state.visibleItems.filter { $0.section == section }.count)").foregroundStyle(.secondary) }.padding(.bottom, 6)
                        ForEach(state.sorted(state.visibleItems.filter { $0.section == section })) { item in
                            TaskRow(state: state, item: item).padding(6).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
                        }
                        Spacer(minLength: 200)
                    }.padding(12).frame(width: 265).background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 7))
                        .dropDestination(for: String.self) { ids, _ in
                            guard let raw = ids.first, let id = UUID(uuidString: raw), state.data.items.contains(where: { $0.id == id }) else { return false }
                            state.update(id) { $0.section = section; $0.projectID = state.project?.id }; return true
                        }
                }
            }.padding(20)
        }
    }
}

struct TaskRow: View {
    @Bindable var state: AppState
    private let seed: Item
    init(state: AppState, item: Item) { self.state = state; self.seed = item }
    // Observe the live record at the row boundary, rather than retain a group snapshot.
    var item: Item { state.data.items.first { $0.id == seed.id } ?? seed }
    private var reminderCount: Int {
        guard item.schedule.date != nil else { return 0 }
        return item.schedule.isTimed ? NotificationPlan.timedOffsets(item: item, preferences: state.data.preferences).count : NotificationPlan.allDayRules(item: item, preferences: state.data.preferences).count
    }
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            if item.kind == .task { CompleteButton(item: item) { state.complete(item.id) } }
            else { Image(systemName: "note.text").foregroundStyle(.secondary).frame(width: 23) }
            VStack(alignment: .leading, spacing: 5) {
                Text(item.title.isEmpty ? "Без названия" : item.title).strikethrough(item.completed).lineLimit(2)
                Metadata(state: state, item: item)
                if !item.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(item.body.split(whereSeparator: \.isNewline).first.map(String.init) ?? "")
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                if !item.checklist.isEmpty || item.recurrence != .none || reminderCount > 0 {
                    MetadataFlow(spacing: 10) {
                        if !item.checklist.isEmpty { Label("\(item.checklist.filter(\.done).count)/\(item.checklist.count)", systemImage: "checklist").help("Выполнено пунктов чек-листа") }
                        if item.recurrence != .none { Label(item.recurrenceLabel, systemImage: "repeat") }
                        if reminderCount > 0 { Label("Уведомления: \(reminderCount)", systemImage: "bell") }
                    }.font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 5) {
            if let date = item.schedule.date {
                Text(state.dayLabel(date)).font(.system(size: 10)).foregroundStyle(.secondary)
                if item.schedule.isTimed { Text(state.time(date) + (item.end.map { "–" + state.time($0) } ?? "")).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.accent) }
            }
            if item.kind == .task { Label(state.durationLabel(item.duration), systemImage: "clock").font(.system(size: 10)).foregroundStyle(.secondary) }
            }.fixedSize(horizontal: true, vertical: false)
        }.padding(.horizontal, 9).padding(.vertical, 12).contentShape(Rectangle())
            .background(state.selectedID == item.id ? Palette.accent.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 5))
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.line).frame(height: 0.5) }
            .onTapGesture { state.select(item.id) }
            .draggable(item.id.uuidString)
            .dropDestination(for: String.self) { strings, _ in
                guard state.sorting == .manual, let id = strings.first.flatMap(UUID.init(uuidString:)),
                      let source = state.data.items.first(where: { $0.id == id }), source.kind == item.kind else { return false }
                state.move(id, before: item.id); return true
            }
            .contextMenu { ItemContextMenu(state: state, item: item) }
    }
}

struct ItemContextMenu: View {
    let state: AppState
    let item: Item
    var body: some View {
        if item.deleted { Button("Восстановить") { state.update(item.id) { $0.deleted = false } } }
        else {
            Button("Открыть стикер") { state.showSticky(item.id) }
            Button("Дублировать") { var copy = item; copy.id = UUID(); copy.recurrenceSourceID = nil; copy.recurrenceOriginalDate = nil; copy.repeatParentID = nil; copy.completed = false; copy.stickyOpen = false; copy.title += " — копия"; state.add(copy) }
            if item.kind == .task {
                Button("Снять время, сохранить дату") { state.unschedule(item.id) }
                Button("Убрать дату и время") { state.unschedule(item.id, clearDay: true) }
            }
            Divider()
            Button(item.kind == .note ? "Удалить заметку" : "Удалить задачу", role: .destructive) { state.delete(item.id) }
        }
    }
}
