import SwiftUI
import TaktCore

struct TaskCreationDraft {
    var item = Item(title: "")
    var literals: [QuickLiteralToken] = []

    mutating func recognize(projects: [Project], tags: [Tag], now: Date = Date(), calendar: Calendar = Dates.calendar(), finishing: Bool = true) {
        let raw = item.title
        let literalRanges = QuickLiteralToken.ranges(literals, in: raw)
        let detected = QuickParser.parse(raw, projects: projects, tags: tags, now: now, calendar: calendar, literalRanges: literalRanges, consumeRedundantCommands: true)
        // Keep date phrases together while typing: «12 дек » may still gain a year or time.
        let pendingDates = detected.tokens.filter { $0.kind == .date || $0.kind == .time }.map(\.range)
        let parsed = finishing ? detected : QuickParser.parse(raw, projects: projects, tags: tags, now: now, calendar: calendar, literalRanges: literalRanges + pendingDates, consumeRedundantCommands: true)
        guard !parsed.tokens.isEmpty else { return }
        if parsed.tokens.contains(where: { $0.kind == .project }) {
            item.projectID = parsed.projectID
            item.section = projects.first { $0.id == parsed.projectID }?.sections.first ?? "Без раздела"
        }
        for id in parsed.tagIDs where !item.tagIDs.contains(id) { item.tagIDs.append(id) }
        if parsed.tokens.contains(where: { $0.kind == .priority }) { item.priority = parsed.priority }
        if parsed.hasExplicitDuration { item.duration = parsed.duration }
        if parsed.tokens.contains(where: { $0.kind == .date || $0.kind == .time }) { item.schedule = parsed.schedule }
        let title = parsed.title + (raw.last?.isWhitespace == true && !parsed.title.isEmpty ? " " : "")
        literals = QuickLiteralToken.rebased(literals, from: raw, to: title)
        item.title = title
    }
}

struct TaskCreationForm: View {
    @Bindable var state: AppState
    let dismiss: () -> Void
    let height: CGFloat
    @ViewState private var draft: TaskCreationDraft
    @ViewState private var newCheck = ""
    @ViewState private var dateOpen = false
    @ViewState private var titleFocus: UUID?
    @ViewState private var descriptionFocus: UUID?
    @ViewState private var error: String?
    @ViewState private var saved = false
    @Environment(\.colorScheme) private var colorScheme

    init(state: AppState, draft: TaskCreationDraft = TaskCreationDraft(), height: CGFloat? = nil, dismiss: @escaping () -> Void) {
        self.state = state; self.dismiss = dismiss; _draft = State(initialValue: draft)
        self.height = height ?? min(680, max(360, (NSScreen.main?.visibleFrame.height ?? 780) - 100))
    }
    private var parsed: ParsedTask {
        QuickParser.parse(draft.item.title, projects: state.activeProjects, tags: state.data.tags, calendar: state.calendar,
                          literalRanges: QuickLiteralToken.ranges(draft.literals, in: draft.item.title), consumeRedundantCommands: true)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Новая задача").font(.system(size: 20, weight: .semibold)).padding(22)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SmartCaptureInput(text: $draft.item.title, literals: $draft.literals, parsed: parsed,
                                      projects: state.activeProjects, tags: state.data.tags, placeholder: "Название задачи",
                                      autoFocus: true, focusRequest: titleFocus, singleLine: true, calendar: state.calendar, tabMovesFocus: true,
                                      onFocus: { if !$0 { recognize() } }, expandDescription: { descriptionFocus = UUID() }, submit: save)
                        .frame(height: 38)
                        .onChange(of: draft.item.title) { _, text in if text.last?.isWhitespace == true { recognize(finishing: false) } }
                    Text("Название понимает !1, завтра, /проект и #тег. Распознанные команды переносятся в поля формы.")
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let warning = parsed.warnings.first { Text(warning).font(.system(size: 11)).foregroundStyle(.secondary) }
                    row("Проект") { projectPicker }
                    if let project = state.activeProjects.first(where: { $0.id == draft.item.projectID }), project.sections.count > 1 {
                        row("Раздел") {
                            InspectorDropdown(symbol: "rectangle.split.3x1", title: draft.item.section, options: project.sections.map { section in
                                InspectorMenuOption(title: section, selected: section == draft.item.section, action: { draft.item.section = section })
                            })
                        }
                    }
                    row("Дата") {
                        Button { dateOpen = true } label: {
                            InspectorPill(symbol: "calendar", title: draft.item.schedule.date.map { state.dayLabel($0) + (draft.item.schedule.isTimed ? ", " + state.time($0) : "") } ?? "Без даты", tint: draft.item.schedule.date == nil ? .secondary : Palette.accent)
                        }.buttonStyle(.plain).accessibilityLabel("Дата и время задачи")
                            .popover(isPresented: $dateOpen) { TaskDatePopover(schedule: $draft.item.schedule, calendar: state.calendar) { dateOpen = false } }
                    }
                    row("Длительность") { DurationControl(minutes: $draft.item.duration) }
                    row("Приоритет") {
                        InspectorDropdown(symbol: draft.item.priority == 0 ? "flag" : "flag.fill", title: AppState.priorityTitle(draft.item.priority), tint: Color(nsColor: SemanticTint.priority(draft.item.priority, dark: colorScheme == .dark)), options: [0,1,2,3].map { value in
                            InspectorMenuOption(title: AppState.priorityTitle(value), symbol: "flag", selected: value == draft.item.priority, action: { draft.item.priority = value })
                        }).accessibilityLabel("Приоритет: " + AppState.priorityTitle(draft.item.priority))
                    }
                    row("Повтор") {
                        InspectorDropdown(symbol: "repeat", title: draft.item.recurrence.title, options: Recurrence.allCases.map { value in
                            InspectorMenuOption(title: value.title, selected: value == draft.item.recurrence, action: {
                                draft.item.recurrence = value
                                if value == .intervalDays && draft.item.repeatEveryDays == nil { draft.item.repeatEveryDays = 3 }
                            })
                        })
                    }
                    if draft.item.recurrence == .intervalDays {
                        row("") { Stepper("Каждые \(draft.item.repeatEveryDays ?? 3) дн.", value: Binding(get: { draft.item.repeatEveryDays ?? 3 }, set: { draft.item.repeatEveryDays = $0 }), in: 1...3650) }
                    }
                    row("Теги") {
                        MetadataFlow {
                            ForEach(draft.item.tagIDs, id: \.self) { id in
                                if let tag = state.data.tags.first(where: { $0.id == id }) {
                                    Button { draft.item.tagIDs.removeAll { $0 == id } } label: { TagCapsule(tag: tag) }
                                        .buttonStyle(.plain).help("Убрать тег #" + tag.name)
                                } else {
                                    Button("Убрать удалённый тег") { draft.item.tagIDs.removeAll { $0 == id } }
                                        .font(.system(size: 11))
                                }
                            }
                            InspectorDropdown(symbol: "plus", title: "Выбрать", options: state.data.tags.map { tag in
                                InspectorMenuOption(title: tag.name, symbol: "number", selected: draft.item.tagIDs.contains(tag.id), action: {
                                    if draft.item.tagIDs.contains(tag.id) { draft.item.tagIDs.removeAll { $0 == tag.id } }
                                    else { draft.item.tagIDs.append(tag.id) }
                                })
                            }).disabled(state.data.tags.isEmpty).accessibilityLabel("Теги задачи")
                        }
                    }
                    Divider()
                    Text("Описание").fontWeight(.medium)
                    MarkdownEditor(text: $draft.item.body, tags: state.data.tags, placeholder: "Описание задачи", focusRequest: descriptionFocus, submit: save)
                        .frame(height: 100).background(Palette.canvas, in: RoundedRectangle(cornerRadius: 6))
                    Text("Чек-лист").fontWeight(.medium)
                    ForEach($draft.item.checklist) { $check in
                        HStack {
                            TextField("Пункт", text: $check.title).textFieldStyle(.plain)
                            IconButton(symbol: "minus", help: "Убрать пункт") { draft.item.checklist.removeAll { $0.id == check.id } }
                        }
                    }
                    TextField("Добавить пункт", text: $newCheck).textFieldStyle(.roundedBorder).onSubmit(addCheck)
                    reminders
                }.padding(22)
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                if let error { Text(error).font(.system(size: 12)).foregroundStyle(.red).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
                HStack {
                    Button("Отмена", action: dismiss).keyboardShortcut(.cancelAction)
                    Spacer()
                    Text("⌘↵ — добавить").font(.system(size: 11)).foregroundStyle(.secondary)
                    Button("Добавить", action: save).buttonStyle(.borderedProminent).keyboardShortcut(.return, modifiers: .command)
                        .disabled(parsed.title.isEmpty || saved)
                }
            }.padding(18)
        }.frame(width: 600, height: height).font(.system(size: 13)).background(Palette.sidebar)
            .preferredColorScheme(state.data.preferences.theme == "light" ? .light : state.data.preferences.theme == "dark" ? .dark : nil)
    }
    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title).foregroundStyle(.secondary).frame(width: 90, alignment: .leading).padding(.top, 5)
            content().frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private var projectPicker: some View {
        InspectorDropdown(symbol: draft.item.projectID == nil ? "tray" : "folder", title: state.projectName(draft.item.projectID), options:
            [InspectorMenuOption(title: "Входящие", selected: draft.item.projectID == nil, action: { draft.item.projectID = nil; draft.item.section = "Без раздела" })] +
            state.activeProjects.filter { $0.kind == .task }.map { project in
                InspectorMenuOption(title: project.name, selected: draft.item.projectID == project.id, action: { draft.item.projectID = project.id; draft.item.section = project.sections.first ?? "Без раздела" })
            }).accessibilityLabel("Проект задачи")
    }
    @ViewBuilder private var reminders: some View {
        Divider()
        Text("Напоминания").fontWeight(.medium)
        if draft.item.schedule.date != nil {
            Toggle("Как в настройках по умолчанию", isOn: Binding(get: {
                draft.item.schedule.isTimed ? draft.item.timedReminderOffsets == nil : draft.item.allDayReminders == nil
            }, set: { defaults in
                if draft.item.schedule.isTimed { draft.item.timedReminderOffsets = defaults ? nil : NotificationPlan.timedOffsets(item: draft.item, preferences: state.data.preferences) }
                else { draft.item.allDayReminders = defaults ? nil : NotificationPlan.allDayRules(item: draft.item, preferences: state.data.preferences) }
            })).toggleStyle(.checkbox)
            if draft.item.schedule.isTimed {
                TimedReminderEditor(values: Binding(get: { NotificationPlan.timedOffsets(item: draft.item, preferences: state.data.preferences) }, set: { draft.item.timedReminderOffsets = $0 }))
            } else {
                AllDayReminderEditor(values: Binding(get: { NotificationPlan.allDayRules(item: draft.item, preferences: state.data.preferences) }, set: { draft.item.allDayReminders = $0 }), calendar: state.calendar)
            }
        } else { Text("Выберите дату, чтобы настроить напоминания.").foregroundStyle(.secondary).font(.system(size: 11)) }
    }
    private func recognize(finishing: Bool = true) { draft.recognize(projects: state.activeProjects, tags: state.data.tags, calendar: state.calendar, finishing: finishing) }
    private func addCheck() {
        let title = newCheck.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { draft.item.checklist.append(CheckItem(title: title)); newCheck = "" }
    }
    private func save() {
        guard !saved else { return }
        error = nil
        recognize(); addCheck()
        guard !draft.item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { titleFocus = UUID(); return }
        guard state.capture(draft.item) != nil else { error = state.errorMessage ?? "Не удалось добавить задачу. Попробуйте ещё раз."; return }
        saved = true; dismiss()
    }
}
