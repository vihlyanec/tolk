import SwiftUI
import TaktCore
import UniformTypeIdentifiers

// THESIS: A familiar, dense Mac workspace for capturing tasks and planning time.
// OWN-WORLD: TickTick-like rails, SF type, thin dividers, blue accent, translucent events.
// STORY: Capture, organize, drag into a week, complete in place. Notes remain independent.
// FIRST VIEWPORT: grouped task list + projects/tags; calendar opens seven-day grid + planning queue.
// FORM: User-pinned conventional task manager; approved list and calendar overlap study.
// FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, and DESIGN.md
struct MainView: View {
    @Bindable var state: AppState
    var body: some View {
        GeometryReader { viewport in
            workspace(compact: viewport.size.width < 900)
                .frame(width: viewport.size.width, height: viewport.size.height, alignment: .topLeading)
                .environment(\.workspaceHeight, viewport.size.height)
                .sheet(item: $state.sheet) { kind in
                    CreationSheet(state: state, kind: kind, maximumHeight: WorkspaceGeometry.presentationHeight(560, in: viewport.size.height))
                }
                .sheet(isPresented: $state.taskCreationPresented) {
                    TaskCreationForm(state: state, width: min(600, viewport.size.width), height: WorkspaceGeometry.presentationHeight(680, in: viewport.size.height)) { state.taskCreationPresented = false }
                }
        }
        .font(.system(size: 13)).tint(Palette.accent).background(Palette.canvas)
        .preferredColorScheme(state.data.preferences.theme == "dark" ? .dark : state.data.preferences.theme == "light" ? .light : nil)
        .alert("Удалить повторяющуюся задачу?", isPresented: Binding(get: { state.pendingRecurringDeletion != nil }, set: { if !$0 { state.pendingRecurringDeletion = nil } }), presenting: state.pendingRecurringDeletion) { _ in
            Button("Удалить только эту задачу", role: .destructive) { state.confirmRecurringDeletion(following: false) }
            Button("Удалить всю цепочку", role: .destructive) { state.confirmRecurringDeletion(following: true) }
            Button("Отмена", role: .cancel) { state.pendingRecurringDeletion = nil }
        } message: { item in
            Text("«\(item.title)»: можно удалить только этот повтор или его и все последующие. Предыдущие задачи сохранятся.")
        }
        .alert("Переключить задачу фокуса?", isPresented: Binding(get: { state.pendingFocusTask != nil }, set: { if !$0 { state.pendingFocusTask = nil } })) {
            Button("Начать новый сеанс") { if let item = state.pendingFocusTask { state.pomodoro.start(item); state.area = .focus }; state.pendingFocusTask = nil }
            Button("Отмена", role: .cancel) { state.pendingFocusTask = nil }
        } message: { Text("Текущий сеанс завершится. Новый начнётся с 25 минут.") }
        .modifier(ProjectDeletionPrompt(state: state))
        .onChange(of: state.area) { _, area in
            state.calendarEditingID = nil; state.endDrag(); state.search = ""
            if area == .calendar { state.scope = .all; state.search = "" }
        }
    }
    private func workspace(compact: Bool) -> some View {
        VStack(spacing: 0) {
            if state.area != .focus && state.pomodoro.session != nil { PomodoroBar(state: state); Divider() }
            if let error = state.errorMessage {
                HStack { Image(systemName: "exclamationmark.triangle"); Text(error).textSelection(.enabled); Spacer(); IconButton(symbol: "xmark", help: "Скрыть сообщение") { state.errorMessage = nil } }
                    .font(.system(size: 12)).padding(.horizontal, 12).padding(.vertical, 5).background(Color.red.opacity(0.16))
            }
            HStack(alignment: .top, spacing: 0) {
                rail
                if state.sidebarVisible && state.area == .tasks { Sidebar(state: state, compact: compact).frame(width: compact ? 200 : 252); Divider() }
                Group {
                    if state.area == .focus { PomodoroWorkspace(state: state) }
                    else if state.area == .analytics { TaskAnalyticsView(state: state) }
                    else if state.area == .calendar { CalendarView(state: state) }
                    else if state.area == .notes { NotesWorkspace(state: state) }
                    else { TaskListView(state: state) }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    private var rail: some View {
        VStack(spacing: 16) {
            BrandMark().frame(width: 36, height: 36).padding(.top, 12).padding(.bottom, 10)
            ForEach(Area.allCases, id: \.self) { area in
                let (symbol, title) = switch area {
                case .tasks: ("checklist", "Задачи")
                case .calendar: ("calendar", "Календарь")
                case .focus: ("timer", "Помодоро")
                case .notes: ("square.and.pencil", "Заметки")
                case .analytics: ("chart.bar.xaxis", "Аналитика")
                }
                IconButton(symbol: symbol, help: title, tint: state.area == area ? Palette.accent : .secondary) {
                    state.area = area; state.scope = .all; state.selectedID = nil
                }.frame(width: 38, height: 38).background(state.area == area ? Palette.accent.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 8))
            }
            Spacer()
            if state.area == .tasks || state.area == .notes { IconButton(symbol: "sidebar.left", help: state.area == .notes ? "Показать/скрыть заметки" : "Показать/скрыть проекты") { state.sidebarVisible.toggle() } }
            IconButton(symbol: "gearshape", help: "Настройки") { state.showSettings() }.padding(.bottom, 16)
        }.frame(width: 52).background(Color.primary.opacity(0.025)).overlay(alignment: .trailing) { Rectangle().fill(Palette.line).frame(width: 1) }
    }
}

struct Sidebar: View {
    @Bindable var state: AppState
    var compact = false
    @Environment(\.workspaceHeight) private var workspaceHeight
    @AppStorage("sidebarProjectsExpanded") private var projectsExpanded = true
    @AppStorage("sidebarTagsExpanded") private var tagsExpanded = true
    @ViewState private var projectDropTarget: UUID?
    @ViewState private var projectDropAfter = false
    private var short: Bool { (workspaceHeight ?? .infinity) < 520 }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) { Image(systemName: "magnifyingglass").foregroundStyle(.secondary); TextField(compact ? "Поиск" : "Поиск задач и заметок", text: $state.search).textFieldStyle(.plain).accessibilityLabel("Поиск задач и заметок") }
                .padding(8).background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 6)).padding(.bottom, short ? 6 : 16)
            nav("Все", symbol: "square.stack.3d.up", scope: .all)
            nav("Входящие", symbol: "tray", scope: .inbox)
            if state.area != .notes {
                nav("Сегодня", symbol: "sun.max", scope: .today)
                nav("Следующие 7 дней", symbol: "calendar.badge.plus", scope: .week)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    sectionHeading("Проекты", expanded: $projectsExpanded) { state.sheet = .project(nil) }.padding(.top, short ? 10 : 22)
                    if projectsExpanded {
                    ForEach(Array(Set(state.activeProjects.map(\.folder))).sorted(), id: \.self) { folder in
                        if !folder.isEmpty { HStack { Text(folder); Spacer(); countBadge(state.folderTaskCount(folder)) }.font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.top, 10).padding(.horizontal, 8) }
                        ForEach(state.activeProjects.filter { $0.folder == folder }) { project in
                            HStack(spacing: 9) {
                                Image(systemName: project.kind == .note ? "note.text" : "circle.fill").foregroundStyle(Color(hex: project.color)).font(.system(size: project.kind == .note ? 13 : 9)).frame(width: 16)
                                Text(project.name).lineLimit(1).layoutPriority(1); Spacer(minLength: 8); countBadge(state.taskCount(in: .project(project.id)))
                            }.padding(.horizontal, 8).frame(height: 32).contentShape(Rectangle())
                                .background(projectDropTarget == project.id ? Palette.accent.opacity(0.26) : state.scope == .project(project.id) ? Palette.accent.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 5))
                                .onTapGesture { openProject(project) }
                                .onDrag { NSItemProvider(object: ("takt-project:" + project.id.uuidString) as NSString) }
                                .onDrop(of: [.text], delegate: ProjectDropDelegate(state: state, projectID: project.id, target: $projectDropTarget, after: $projectDropAfter))
                                .overlay(alignment: projectDropAfter ? .bottom : .top) {
                                    if projectDropTarget == project.id { Rectangle().fill(Palette.accent).frame(height: 2).allowsHitTesting(false) }
                                }
                                .accessibilityElement(children: .combine).accessibilityAddTraits(.isButton)
                                .accessibilityAction { openProject(project) }
                                .focusable().focusEffectDisabled()
                                .onKeyPress(.return) { openProject(project); return .handled }
                                .contextMenu {
                                    Button("Переместить выше") { shiftProject(project, by: -1) }.disabled(projectPeers(project).first?.id == project.id)
                                    Button("Переместить ниже") { shiftProject(project, by: 1) }.disabled(projectPeers(project).last?.id == project.id)
                                    Divider()
                                    Button("Изменить проект") { state.sheet = .project(project.id) }
                                    Button("Добавить раздел") { state.sheet = .section(project.id) }
                                    Button("Удалить", role: .destructive) { state.projectDeletionInSettings = false; state.pendingProjectDeletion = project }
                                    Button("Архивировать") { state.change { s in if let i = s.projects.firstIndex(where: { $0.id == project.id }) { s.projects[i].archived = true } }; state.scope = .all }
                                }
                        }
                    }
                    }
                    sectionHeading("Теги", expanded: $tagsExpanded) { state.sheet = .tag(nil) }.padding(.top, short ? 10 : 22)
                    if tagsExpanded {
                        tagTree(parent: nil, level: 0)
                        if state.data.tags.isEmpty { Text("Создайте первый тег через +").font(.system(size: 11)).foregroundStyle(.secondary).padding(8) }
                    }
                }
            }
            Divider().padding(.vertical, short ? 4 : 8)
            nav("Завершённые", symbol: "checkmark.circle", scope: .completed)
            nav("Не буду выполнять", symbol: "minus.circle", scope: .wontDo)
            nav("Корзина", symbol: "trash", scope: .trash)
            Text(state.isDemo ? "Демо · вымышленные данные" : "Толк · локально на Mac").font(.system(size: 10)).foregroundStyle(.secondary).padding(.top, 10).padding(.leading, 8)
        }.padding(12).background(Palette.sidebar)
    }
    private func openProject(_ project: Project) {
        state.scope = .project(project.id); state.selectedID = nil
        state.area = project.kind == .note ? .notes : .tasks
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
            HStack(spacing: 8) {
                Image(systemName: symbol).frame(width: 17)
                Text(title).lineLimit(compact ? 2 : 1).frame(maxWidth: .infinity, alignment: .leading)
                countBadge(state.taskCount(in: scope))
            }.padding(.horizontal, 8).frame(height: short ? 30 : 33).contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(state.scope == scope ? Palette.accent : .primary)
            .background(state.scope == scope ? Palette.accent.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 5))
    }
    private func sectionHeading(_ name: String, expanded: Binding<Bool>, action: @escaping () -> Void) -> some View {
        HStack(spacing: 0) {
            Button { expanded.wrappedValue.toggle() } label: {
                HStack(spacing: 7) {
                    Image(systemName: expanded.wrappedValue ? "chevron.down" : "chevron.right").font(.system(size: 9, weight: .semibold)).frame(width: 10)
                    Text(name).font(.system(size: 12, weight: .semibold))
                    Spacer()
                }.frame(height: 30).contentShape(Rectangle())
            }.buttonStyle(.plain).foregroundStyle(.secondary)
                .accessibilityValue(expanded.wrappedValue ? "Развёрнуто" : "Свёрнуто")
            IconButton(symbol: "plus", help: "Добавить: \(name)") { expanded.wrappedValue = true; action() }
        }.padding(.leading, 8)
    }
    private func tagTree(parent: UUID?, level: Int) -> AnyView {
        AnyView(ForEach(state.data.tags.filter { $0.parentID == parent }) { tag in
            VStack(alignment: .leading, spacing: 0) {
                Button { state.filterByTag(tag.id) } label: {
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
        GeometryReader { viewport in
            let selectedID = state.inspectorVisible ? state.selectedID : nil
            if viewport.size.width >= 680 {
                HSplitView {
                    taskPane.frame(minWidth: 345)
                    if let selectedID {
                        ItemInspector(state: state, id: selectedID).frame(minWidth: 285, idealWidth: 330, maxWidth: 420)
                    }
                }
            } else {
                taskPane.overlay(alignment: .trailing) {
                    if let selectedID {
                        ItemInspector(state: state, id: selectedID)
                            .frame(width: min(330, viewport.size.width), height: viewport.size.height)
                            .background(Palette.canvas)
                            .overlay(alignment: .leading) { Rectangle().fill(Palette.line).frame(width: 1) }
                            .shadow(color: .black.opacity(0.18), radius: 10, x: -3)
                    }
                }
            }
        }
    }
    private var taskPane: some View {
        VStack(spacing: 0) {
            heading
            HStack(spacing: 8) {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        Picker("Группировать", selection: Binding(get: { state.grouping }, set: { state.grouping = $0 })) { ForEach(Grouping.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.frame(width: 220)
                        Picker("Сортировать", selection: Binding(get: { state.sorting }, set: { state.sorting = $0 })) { ForEach(Sorting.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.frame(width: 205)
                    }.fixedSize(horizontal: true, vertical: false)
                    listMenus(iconOnly: false).fixedSize(horizontal: true, vertical: false)
                    listMenus(iconOnly: true)
                }
                Spacer(minLength: 4)
                if let project = state.project, project.kanban {
                    Button { state.sheet = .section(project.id) } label: {
                        Label("Добавить этап", systemImage: "plus")
                    }.help("Создать этап в этом проекте").accessibilityIdentifier("kanban-add-stage")
                }
                if let project = state.project, project.kind == .task, project.sections.count > 1 {
                    Menu {
                        ForEach(project.sections, id: \.self) { section in
                            Menu(section) { sectionMoveActions(section, in: project) }
                        }
                    } label: { Image(systemName: "arrow.up.arrow.down") }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                        .help("Порядок этапов").accessibilityLabel("Порядок этапов")
                }
                Text("\(state.visibleItems.count)").foregroundStyle(.secondary)
            }.padding(.horizontal, 22).padding(.bottom, 14)
            if state.area != .notes && state.scope != .trash && state.scope != .completed && state.scope != .wontDo { InlineQuickEntry(state: state) }
            Divider()
            if state.project?.kanban == true { kanban }
            else if state.visibleItems.isEmpty {
                EmptyState(symbol: state.area == .notes ? "note.text" : "checkmark.circle", title: "Пока пусто", detail: state.scope == .wontDo ? "Здесь остаются задачи, которые вы решили не выполнять." : state.search.isEmpty ? "Добавьте первую запись. Проекты и теги можно создать слева." : "По этому запросу ничего не найдено.")
            } else {
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
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    private func listMenus(iconOnly: Bool) -> some View {
        HStack {
            Menu {
                ForEach(Grouping.allCases, id: \.self) { value in Button(value.rawValue) { state.grouping = value } }
            } label: {
                if iconOnly { Image(systemName: "rectangle.3.group") }
                else { Label(state.grouping.rawValue, systemImage: "rectangle.3.group") }
            }.help("Группировать").accessibilityLabel("Группировать: " + state.grouping.rawValue)
            Menu {
                ForEach(Sorting.allCases, id: \.self) { value in Button(value.rawValue) { state.sorting = value } }
            } label: {
                if iconOnly { Image(systemName: "arrow.up.arrow.down") }
                else { Label(state.sorting.rawValue, systemImage: "arrow.up.arrow.down") }
            }.help("Сортировать").accessibilityLabel("Сортировать: " + state.sorting.rawValue)
        }
    }
    private var heading: some View {
        HStack {
            Text(state.title).font(.system(size: 23, weight: .semibold)).lineLimit(1).frame(minWidth: 76, alignment: .leading)
            Spacer(minLength: 4)
            ViewThatFits(in: .horizontal) {
                headingActions(compact: false).fixedSize(horizontal: true, vertical: false)
                headingActions(compact: true)
            }
        }.padding(22)
    }
    private func headingActions(compact: Bool) -> some View {
        HStack {
            if let project = state.project {
                IconButton(symbol: "gearshape", help: "Настройки проекта и автоматизации") { state.sheet = .project(project.id) }
                let kanban = Binding(get: { project.kanban }, set: { value in
                    state.change { snapshot in
                        if let index = snapshot.projects.firstIndex(where: { $0.id == project.id }) { snapshot.projects[index].kanban = value }
                    }
                })
                let picker = Picker("Вид", selection: kanban) { Text("Список").tag(false); Text("Канбан").tag(true) }
                if compact {
                    Menu { picker } label: { Image(systemName: project.kanban ? "rectangle.split.3x1" : "list.bullet") }
                        .menuStyle(.borderlessButton).fixedSize().help("Вид проекта").accessibilityLabel("Вид проекта")
                } else {
                    picker.pickerStyle(.segmented).labelsHidden().frame(width: 160)
                }
            }
            if state.scope != .wontDo {
                let title = state.area == .notes ? "Заметка" : "Задача"
                Button {
                    if state.area == .notes { state.showSticky(nil) }
                    else { state.taskCreationPresented = true }
                } label: {
                    if compact { Image(systemName: "plus") }
                    else { Label(title, systemImage: "plus") }
                }.buttonStyle(.borderedProminent).accessibilityLabel(title).help(title)
            }
            if let id = state.selectedID, state.selected?.deleted == false {
                IconButton(symbol: "trash", help: "Удалить выбранную задачу") { state.delete(id) }
            }
            IconButton(symbol: "sidebar.right", help: "Показать/скрыть детали") { state.inspectorVisible.toggle() }
        }
    }
    @ViewBuilder private var kanban: some View {
        if let project = state.project {
            let prefix = "takt-section:" + project.id.uuidString + ":"
            let tasksBySection = Dictionary(grouping: state.visibleItems, by: \.section)
            GeometryReader { viewport in
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(project.sections, id: \.self) { section in
                            let tasks = tasksBySection[section, default: []]
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Image(systemName: "line.3.horizontal").foregroundStyle(.secondary).accessibilityHidden(true)
                                    Text(section).fontWeight(.semibold).lineLimit(1)
                                    Spacer()
                                    Text("\(tasks.count)").foregroundStyle(.secondary)
                                }.padding(.bottom, 6).contentShape(Rectangle())
                                    .draggable(prefix + section)
                                    .help("Перетащить этап")
                                    .contextMenu { sectionMoveActions(section, in: project) }
                                ScrollView(.vertical) {
                                    LazyVStack(spacing: 10) {
                                        ForEach(state.sorted(tasks)) { item in
                                            TaskRow(state: state, item: item).padding(6).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
                                        }
                                    }
                                }.frame(maxHeight: .infinity)
                            }
                            .padding(12)
                            .frame(width: 265, height: max(0, viewport.size.height - 40), alignment: .topLeading)
                            .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 7))
                            .contentShape(Rectangle())
                            .dropDestination(for: String.self) { values, _ in
                                guard let value = values.first, state.project?.id == project.id else { return false }
                                if value.hasPrefix(prefix) {
                                    return state.moveSection(String(value.dropFirst(prefix.count)), to: section, in: project.id)
                                }
                                guard let id = UUID(uuidString: value), state.data.items.contains(where: { $0.id == id }) else { return false }
                                state.update(id) { $0.section = section; $0.projectID = project.id }; return true
                            }
                        }
                    }.padding(20)
                }
            }
        }
    }
    @ViewBuilder private func sectionMoveActions(_ section: String, in project: Project) -> some View {
        if let index = project.sections.firstIndex(of: section) {
            Button("Переместить раньше", systemImage: "arrow.up") {
                if index > 0 { state.moveSection(section, to: project.sections[index - 1], in: project.id) }
            }.disabled(index == 0)
            Button("Переместить позже", systemImage: "arrow.down") {
                if index + 1 < project.sections.count { state.moveSection(section, to: project.sections[index + 1], in: project.id) }
            }.disabled(index + 1 == project.sections.count)
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
            if item.wontDoAt != nil { IconButton(symbol: "arrow.uturn.backward", help: "Вернуть в работу") { state.toggleWontDo(item.id) }.disabled(item.deleted) }
            else if item.kind == .task { CompleteButton(item: item) { state.complete(item.id) } }
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
            if item.isActiveTask { Button("Начать фокус") { state.startFocus(item) } }
            if item.kind == .task && !item.completed {
                Button(item.wontDoAt == nil ? "Не буду выполнять" : "Вернуть в работу") { state.toggleWontDo(item.id) }
            }
            Button("Открыть стикер") { state.showSticky(item.id) }
            if item.kind == .task { Button("Копировать событие") { state.copyCalendarItem(item) } }
            Button("Дублировать") {
                var copy = item
                copy.id = UUID(); copy.created = Date(); copy.modified = copy.created
                copy.recurrenceSourceID = nil; copy.recurrenceOriginalDate = nil; copy.recurrenceEndDate = nil; copy.repeatParentID = nil
                copy.completed = false; copy.completedAt = nil; copy.wontDoAt = nil; copy.taskActivity = nil; copy.sectionBeforeCompletion = nil
                copy.stickyOpen = false; copy.title += " — копия"; state.add(copy)
            }
            if item.kind == .task {
                Button("Снять время, сохранить дату") { state.unschedule(item.id) }
                Button("Убрать дату и время") { state.unschedule(item.id, clearDay: true) }
            }
            Divider()
            Button(item.kind == .note ? "Удалить заметку" : "Удалить задачу", role: .destructive) { state.delete(item.id) }
        }
    }
}

/// Native text drops accept both SwiftUI task drags and NSString project drags.
struct ProjectDropDelegate: DropDelegate {
    let state: AppState
    let projectID: UUID
    @Binding var target: UUID?
    @Binding var after: Bool
    func dropUpdated(info: DropInfo) -> DropProposal? {
        target = projectID; after = info.location.y >= 16
        return DropProposal(operation: .move)
    }
    func dropExited(info: DropInfo) { if target == projectID { target = nil } }
    func performDrop(info: DropInfo) -> Bool {
        let insertAfter = info.location.y >= 16
        target = nil
        guard let provider = info.itemProviders(for: [.text]).first(where: { $0.canLoadObject(ofClass: String.self) }) else { return false }
        _ = provider.loadObject(ofClass: String.self) { payload, _ in
            guard let payload else { return }
            Task { @MainActor in _ = state.acceptProjectDrop(payload, on: projectID, after: insertAfter) }
        }
        return true
    }
}

struct ProjectDeletionPrompt: ViewModifier {
    @Bindable var state: AppState
    var inSettings = false
    func body(content: Content) -> some View {
        content.alert("Удалить проект?", isPresented: Binding(
            get: { state.pendingProjectDeletion != nil && state.projectDeletionInSettings == inSettings },
            set: { if !$0 { state.pendingProjectDeletion = nil } }
        ), presenting: state.pendingProjectDeletion) { project in
            Button("Удалить", role: .destructive) {
                state.deleteProject(project.id); state.pendingProjectDeletion = nil
            }
            Button("Отмена", role: .cancel) { state.pendingProjectDeletion = nil }
        } message: { project in
            Text("Проект «\(project.name)» будет удалён. Его задачи и заметки сохранятся во «Входящих». Действие можно отменить через Правка → Отменить изменение записи.")
        }
    }
}
