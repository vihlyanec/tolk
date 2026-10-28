import SwiftUI
import TaktCore

struct ItemInspector: View {
    @Bindable var state: AppState
    let id: UUID
    @ViewState private var newCheck = ""
    @ViewState private var preview = false
    @ViewState private var format: EditorAction?
    @ViewState private var remindersOpen = false
    @ViewState private var dateOpen = false
    @Environment(\.colorScheme) private var colorScheme
    private var item: Item? { state.item(id) }
    private func binding<T>(_ path: WritableKeyPath<Item, T>, fallback: T) -> Binding<T> {
        Binding(get: { item?[keyPath: path] ?? fallback }, set: { value in state.update(id) { $0[keyPath: path] = value } })
    }
    var body: some View {
        if let item {
            VStack(spacing: 0) {
                HStack {
                    if item.kind == .task { CompleteButton(item: item) { state.complete(id) } }
                    else { Image(systemName: "note.text").foregroundStyle(.secondary) }
                    Text(item.kind == .note ? "Заметка" : "Задача").foregroundStyle(.secondary)
                    Spacer()
                    IconButton(symbol: "pin", help: "Открыть стикер") { state.showSticky(id) }.disabled(item.deleted)
                    IconButton(symbol: "xmark", help: "Закрыть детали") { state.selectedID = nil; state.calendarEditingID = nil }
                }.padding(.horizontal, 16).padding(.top, 12)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        TagTitleInput(text: binding(\.title, fallback: ""), tags: state.data.tags, onCommit: { state.commitHashtags(id) })
                        VStack(alignment: .leading, spacing: 10) {
                            MetadataFlow {
                                projectMenu(item)
                                if let project = state.data.projects.first(where: { $0.id == item.projectID }), project.sections.count > 1 || item.section != "Без раздела" {
                                    InspectorDropdown(symbol: "rectangle.split.3x1", title: item.section, options: Array(Set(project.sections + [item.section])).sorted().map { section in
                                        InspectorMenuOption(title: section, selected: item.section == section, action: { state.update(id) { $0.section = section } })
                                    }).help("Раздел")
                                }
                            }
                            if item.kind == .task { scheduling(item) }
                            MetadataFlow {
                                if item.kind == .task && item.schedule.date != nil { reminderButton(item) }
                                ForEach(item.tagIDs, id: \.self) { tagID in if let tag = state.data.tags.first(where: { $0.id == tagID }) { TagCapsule(tag: tag) } }
                                InspectorDropdown(symbol: "plus", title: item.tagIDs.isEmpty ? "Тег" : "", options:
                                    state.data.tags.map { tag in InspectorMenuOption(title: tag.name, symbol: "number", selected: item.tagIDs.contains(tag.id), action: {
                                        state.update(id) { value in if value.tagIDs.contains(tag.id) { value.tagIDs.removeAll { $0 == tag.id } } else { value.tagIDs.append(tag.id) } }
                                    }) } + [InspectorMenuOption(title: "", separator: true, action: {}), InspectorMenuOption(title: "Создать тег…", symbol: "plus", action: { state.sheet = .tag(nil) })])
                                    .help("Добавить или убрать теги").accessibilityLabel("Теги задачи")
                            }
                        }
                        Divider()
                        HStack {
                            Text(item.kind == .note ? "Текст заметки" : "Описание").fontWeight(.medium)
                            Spacer()
                            if item.kind == .task { Button(preview ? "Редактировать" : "Просмотр") { preview.toggle() }.buttonStyle(.plain).foregroundStyle(Palette.accent).font(.system(size: 11)) }
                        }
                        if item.kind == .note {
                            HStack(spacing: 3) {
                                formatButton("bold", "Жирный", "**", "**")
                                formatButton("italic", "Курсив", "*", "*")
                                formatButton("textformat.size", "Заголовок", "## ", "")
                                formatButton("list.bullet", "Список", "- ", "")
                                formatButton("checklist", "Чек-лист", "- [ ] ", "")
                                formatButton("link", "Ссылка", "[", "](https://)")
                            }
                            RichNoteEditor(text: binding(\.body, fallback: ""), action: format, tags: state.data.tags, editable: !item.deleted, commitTags: { state.commitHashtags(id) }).frame(minHeight: 260)
                        } else if preview {
                            MarkdownPreview(text: item.body).frame(minHeight: 260)
                        } else {
                            HStack(spacing: 3) {
                                formatButton("bold", "Жирный", "**", "**")
                                formatButton("italic", "Курсив", "*", "*")
                                formatButton("textformat.size", "Заголовок", "## ", "")
                                formatButton("list.bullet", "Список", "- ", "")
                                formatButton("checklist", "Чек-лист", "- [ ] ", "")
                                formatButton("chevron.left.forwardslash.chevron.right", "Код", "`", "`")
                                formatButton("link", "Ссылка", "[", "](https://)")
                            }
                            MarkdownEditor(text: binding(\.body, fallback: ""), action: format, tags: state.data.tags, onCommit: { state.commitHashtags(id) }).frame(minHeight: 180)
                        }
                        if item.kind == .task {
                            Divider()
                            Text("Чек-лист").fontWeight(.medium)
                            ForEach(item.checklist) { check in
                                HStack {
                                    Button { state.update(id) { v in if let index = v.checklist.firstIndex(where: { $0.id == check.id }) { v.checklist[index].done.toggle() } } } label: {
                                        Image(systemName: check.done ? "checkmark.circle.fill" : "circle").foregroundStyle(.secondary)
                                    }.buttonStyle(.plain)
                                    TextField("Пункт", text: Binding(get: { item.checklist.first { $0.id == check.id }?.title ?? "" }, set: { text in state.update(id) { v in if let i = v.checklist.firstIndex(where: { $0.id == check.id }) { v.checklist[i].title = text } } })).textFieldStyle(.plain)
                                    IconButton(symbol: "minus", help: "Удалить пункт") { state.update(id) { $0.checklist.removeAll { $0.id == check.id } } }
                                }
                            }
                            TextField("+ Добавить пункт", text: $newCheck).textFieldStyle(.plain).onSubmit {
                                let text = newCheck.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !text.isEmpty { state.update(id) { $0.checklist.append(CheckItem(title: text)) }; newCheck = "" }
                            }
                        }
                    }.padding(18).disabled(item.deleted)
                }
                Divider()
                HStack {
                    if item.deleted { Button("Восстановить") { state.update(id) { $0.deleted = false } } }
                    else { Button(role: .destructive) { state.delete(id) } label: { Label("Удалить", systemImage: "trash") }.buttonStyle(.plain) }
                    Spacer(); Text(state.errorMessage == nil ? "Сохранено на Mac" : "Ошибка сохранения").font(.system(size: 10)).foregroundStyle(.secondary)
                }.padding(.horizontal, 12).padding(.vertical, 8)
            }.background(Palette.sidebar)
        }
    }
    private func formatButton(_ symbol: String, _ title: String, _ before: String, _ after: String) -> some View {
        IconButton(symbol: symbol, help: title) { format = EditorAction(before: before, after: after) }
    }
    private func projectMenu(_ item: Item) -> some View {
        let name = item.kind == .note && item.projectID == nil ? "Без проекта" : state.projectName(item.projectID)
        return InspectorDropdown(symbol: "folder", title: name, tint: item.projectID == nil ? .secondary : Color(nsColor: SemanticTint.color(hex: state.color(item), dark: colorScheme == .dark)), options:
            [InspectorMenuOption(title: item.kind == .note ? "Без проекта" : "Входящие", symbol: "tray", selected: item.projectID == nil, action: { state.update(id) { $0.projectID = nil; $0.section = "Без раздела" } })] +
            state.activeProjects.filter { $0.kind == item.kind }.map { project in
                InspectorMenuOption(title: project.name, symbol: "folder", selected: item.projectID == project.id, action: { state.update(id) { $0.projectID = project.id; $0.section = project.sections.first ?? "Без раздела" } })
            }).help("Изменить проект").accessibilityLabel("Проект: " + name)
    }
    private func scheduling(_ item: Item) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Планирование", selection: Binding(get: { item.schedule.isTimed ? 2 : (item.schedule.date == nil ? 0 : 1) }, set: { mode in
                state.update(id) { value in
                    let date = value.schedule.date ?? Date()
                    value.schedule = mode == 0 ? .unscheduled : mode == 1 ? .day(state.calendar.startOfDay(for: date)) : .timed(date)
                }
            })) { Text("Без даты").tag(0); Text("Весь день").tag(1); Text("Время").tag(2) }.pickerStyle(.segmented).labelsHidden().controlSize(.small)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { compactDate(item); Spacer(minLength: 4); if item.schedule.isTimed || item.schedule.date == nil { compactDuration(item) } }.fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 6) { compactDate(item); if item.schedule.isTimed || item.schedule.date == nil { compactDuration(item) } }
            }.frame(maxWidth: .infinity, alignment: .leading)
            MetadataFlow {
                InspectorDropdown(symbol: item.priority == 0 ? "flag" : "flag.fill", title: item.priority == 0 ? "Приоритет" : AppState.priorityTitle(item.priority), tint: Color(nsColor: SemanticTint.priority(item.priority, dark: colorScheme == .dark)), options: [0,1,2,3].map { priority in
                    InspectorMenuOption(title: AppState.priorityTitle(priority), symbol: "flag", selected: item.priority == priority, action: { state.update(id) { $0.priority = priority } })
                }).help("Изменить приоритет").accessibilityLabel("Приоритет: " + AppState.priorityTitle(item.priority))
                InspectorDropdown(symbol: "repeat", title: item.recurrence == .none ? "Без повтора" : item.recurrenceLabel, tint: item.recurrence == .none ? .secondary : Palette.accent, options: Recurrence.allCases.map { value in
                    InspectorMenuOption(title: value.title, symbol: "repeat", selected: item.recurrence == value, action: { state.update(id) { $0.recurrence = value; if value == .intervalDays && $0.repeatEveryDays == nil { $0.repeatEveryDays = 3 } } })
                }).help("Изменить повтор")
            }
            if item.recurrence == .intervalDays {
                Stepper("Каждые \(item.repeatEveryDays ?? 3) дн.", value: Binding(get: { self.item?.repeatEveryDays ?? 3 }, set: { days in state.update(id) { $0.repeatEveryDays = days } }), in: 1...3650).font(.system(size: 12)).accessibilityLabel("Интервал повтора в днях")
            }
        }
    }
    private func compactDate(_ item: Item) -> some View {
        Button { dateOpen = true } label: {
            InspectorPill(symbol: "calendar", title: item.schedule.date.map { state.dayLabel($0) + (item.schedule.isTimed ? ", " + state.time($0) : "") } ?? "Выбрать дату", tint: Palette.accent)
        }.buttonStyle(.plain).help("Выбрать дату и время")
            .popover(isPresented: $dateOpen) {
                TaskDatePopover(schedule: binding(\.schedule, fallback: .unscheduled), calendar: state.calendar) { dateOpen = false }
            }
    }
    private func compactDuration(_ item: Item) -> some View {
        DurationControl(minutes: Binding(get: { self.item?.duration ?? item.duration }, set: { minutes in state.update(id) { $0.duration = minutes } }))
            .help("Длительность" + (item.end.map { ". Окончание: " + state.time($0) } ?? ""))
    }
    private func reminderButton(_ item: Item) -> some View {
        let count = item.schedule.isTimed ? NotificationPlan.timedOffsets(item: item, preferences: state.data.preferences).count : NotificationPlan.allDayRules(item: item, preferences: state.data.preferences).count
        return Button { remindersOpen = true } label: {
            InspectorPill(symbol: count == 0 ? "bell" : "bell.badge", title: count == 0 ? "Напомнить" : "\(count)", tint: count == 0 ? .secondary : Palette.accent)
        }.buttonStyle(.plain).help("Напоминания: \(count)").accessibilityLabel("Напоминания: \(count)")
            .popover(isPresented: $remindersOpen) { TaskReminderEditor(state: state, id: id, initiallyExpanded: true).frame(width: 300).padding(16) }
    }

}

struct InspectorPill: View {
    let symbol: String
    let title: String
    let tint: Color
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 10, weight: .medium))
            if !title.isEmpty { Text(title).font(.system(size: 11, weight: .medium)).lineLimit(1).truncationMode(.middle) }
            Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold)).opacity(0.7)
        }.foregroundStyle(tint).padding(.horizontal, 8).padding(.vertical, 6).background(tint.opacity(0.10), in: Capsule())
    }
}

struct FlowTags: View {
    let state: AppState
    let item: Item
    var body: some View {
        MetadataFlow {
            ForEach(state.data.tags.filter { state.tagIDs(for: state.item(item.id) ?? item).contains($0.id) }.map(\.id), id: \.self) { id in
                if let tag = state.data.tags.first(where: { $0.id == id }) {
                    Button { if item.kind == .note { state.area = .notes }; state.filterByTag(tag.id) } label: { TagCapsule(tag: tag) }.buttonStyle(.plain).help("Показать записи с тегом #" + tag.name)
                }
            }
        }
    }
}

struct EditorAction: Equatable { let id = UUID(); let before: String; let after: String }
struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    var action: EditorAction?
    var tags: [Tag] = []
    var fontSize: CGFloat = 13
    var placeholder = ""
    var autoFocus = false
    var fitContent = false
    var focusRequest: UUID? = nil
    var submit: (() -> Void)? = nil
    var onCommit: () -> Void = {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 280, height: 180)); scroll.hasVerticalScroller = !fitContent; scroll.drawsBackground = false
        let editor = TagTextView(frame: NSRect(x: 0, y: 0, width: 280, height: 180)); editor.isRichText = false; editor.font = .systemFont(ofSize: fontSize, weight: fontSize > 16 ? .semibold : .regular)
        editor.minSize = NSSize(width: 0, height: 20)
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.textColor = .labelColor; editor.backgroundColor = .clear
        editor.isVerticallyResizable = true; editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]; editor.textContainer?.widthTracksTextView = true
        editor.textContainerInset = NSSize(width: 4, height: 6)
        editor.delegate = context.coordinator; editor.string = text
        editor.allowsUndo = true; editor.focusRingType = .none
        editor.setAccessibilityLabel(placeholder.isEmpty ? "Текст Markdown" : placeholder)
        editor.toolTip = "Нажмите ссылку, чтобы открыть. ⌥-нажатие — редактировать ссылку. Для тегов введите #."
        editor.linkTextAttributes = [.foregroundColor: NSColor.systemBlue, .underlineStyle: NSUnderlineStyle.single.rawValue]
        scroll.documentView = editor
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? TagTextView else { return }
        editor.tags = tags; editor.placeholder = placeholder; editor.isTitleField = fitContent; editor.onCommandReturn = submit
        if editor.string != text { let selection = editor.selectedRange(); editor.string = text; editor.setSelectedRange(NSRange(location: min(selection.location, (text as NSString).length), length: 0)) }
        editor.refreshAttributes()
        if fitContent { editor.sizeToFit() }
        if (autoFocus && !context.coordinator.requestedFocus) || (focusRequest != nil && focusRequest != context.coordinator.lastFocusRequest) {
            context.coordinator.requestedFocus = true; context.coordinator.lastFocusRequest = focusRequest
            DispatchQueue.main.async { [weak editor] in if let editor { editor.window?.makeFirstResponder(editor) } }
        }
        if let action, action.id != context.coordinator.lastAction {
            context.coordinator.lastAction = action.id
            let range = editor.selectedRange(), selected = (editor.string as NSString).substring(with: range)
            editor.insertText(action.before + selected + action.after, replacementRange: range)
            editor.setSelectedRange(NSRange(location: range.location + (action.before as NSString).length, length: (selected as NSString).length))
            editor.window?.makeFirstResponder(editor)
        }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        guard fitContent, let width = proposal.width, width.isFinite else { return nil }
        let bounds = ((text.isEmpty ? placeholder : text) as NSString).boundingRect(with: NSSize(width: max(60, width - 8), height: 220), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: NSFont.systemFont(ofSize: fontSize, weight: .semibold)])
        return CGSize(width: width, height: max(fontSize + 16, ceil(bounds.height) + 16))
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditor
        var lastAction: UUID?
        var requestedFocus = false
        var lastFocusRequest: UUID?
        init(_ parent: MarkdownEditor) { self.parent = parent }
        func textDidEndEditing(_ notification: Notification) { parent.onCommit() }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? TagTextView else { return }
            parent.text = editor.string; editor.refreshAttributes()
            if !editor.hasMarkedText(), editor.rangeForUserCompletion.location != NSNotFound { editor.complete(nil) }
        }
        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            if let url = link as? URL, MarkdownHTML.safeURL(url.absoluteString) != nil { NSWorkspace.shared.open(url); return true }
            return false
        }
    }
}

struct CreationSheet: View {
    @Bindable var state: AppState
    let kind: CreationKind
    @Environment(\.dismiss) private var dismiss
    @ViewState private var name = ""
    @ViewState private var loaded = false
    @ViewState private var color = "4F8CFF"
    @ViewState private var folder = ""
    @ViewState private var itemKind: ItemKind = .task
    @ViewState private var parentID: UUID?
    @ViewState private var sectionError: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title).font(.system(size: 20, weight: .semibold))
            TextField("Название", text: $name).onSubmit(save).onChange(of: name) { _, _ in sectionError = nil }
            if let sectionError { Text(sectionError).font(.system(size: 12)).foregroundStyle(.red) }
            switch kind {
            case .project(let id):
                Picker("Тип", selection: $itemKind) { Text("Задачи").tag(ItemKind.task); Text("Заметки").tag(ItemKind.note) }.disabled(id != nil)
                TextField("Папка (необязательно)", text: $folder)
            case .tag(let id):
                Picker("Родительский тег", selection: $parentID) {
                    Text("Без родителя").tag(nil as UUID?)
                    ForEach(state.data.tags.filter { tag in id.map { !state.tagFamily($0).contains(tag.id) } ?? true }) { Text($0.name).tag(Optional($0.id)) }
                }
            case .section: EmptyView()
            }
            if case .section = kind {} else {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Цвет").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 12) {
                        ForEach(ProjectTagPalette.choices) { option in
                            let selected = SemanticTint.vibrantHex(color) == option.hex
                            Button { color = option.hex } label: {
                                Circle().fill(Color(hex: option.hex)).frame(width: 26, height: 26)
                                    .overlay {
                                        if selected { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(["E8D244", "A7DE3B", "FFAD40", "45D578", "28D9AD", "26CFC0", "35CCE8", "58BFFF"].contains(option.hex) ? .black.opacity(0.75) : .white) }
                                    }
                                    .padding(3).overlay { Circle().stroke(selected ? Color.primary.opacity(0.65) : .clear, lineWidth: 1.5) }
                            }.buttonStyle(.plain).help(option.name).accessibilityLabel("Цвет: " + option.name).accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                    ColorPicker("Свой цвет", selection: Binding(get: { Color(hex: color) }, set: { value in
                        guard let rgb = NSColor(value).usingColorSpace(.sRGB) else { return }
                        color = String(format: "%02X%02X%02X", Int((rgb.redComponent * 255).rounded()), Int((rgb.greenComponent * 255).rounded()), Int((rgb.blueComponent * 255).rounded()))
                    }), supportsOpacity: false).font(.system(size: 12))
                }

            }
            HStack { Button("Отмена") { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button("Сохранить", action: save).keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }.padding(26).frame(width: 390).onAppear(perform: load)
    }
    private var title: String { switch kind { case .project(let id): id == nil ? "Новый проект" : "Изменить проект"; case .tag(let id): id == nil ? "Новый тег" : "Изменить тег"; case .section(let id): state.data.projects.first(where: { $0.id == id })?.kanban == true ? "Новый этап" : "Новый раздел" } }
    private func load() {
        guard !loaded else { return }; loaded = true
        color = ProjectTagPalette.nextColor(in: state.data)
        if state.area == .notes { itemKind = .note }
        switch kind {
        case .project(let id): if let p = state.data.projects.first(where: { $0.id == id }) { name = p.name; color = p.color; folder = p.folder; itemKind = p.kind }
        case .tag(let id): if let t = state.data.tags.first(where: { $0.id == id }) { name = t.name; color = t.color; parentID = t.parentID }
        case .section: break
        }
    }
    private func save() {
        var title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if case .tag = kind { title = title.trimmingCharacters(in: CharacterSet(charactersIn: "# ")) }
        guard !title.isEmpty else { return }
        switch kind {
        case .project(let id):
            guard !state.data.projects.contains(where: { $0.id != id && $0.name.localizedCaseInsensitiveCompare(title) == .orderedSame }) else { state.errorMessage = "Проект с таким названием уже есть"; return }
            state.change { s in
                if let i = s.projects.firstIndex(where: { $0.id == id }) { s.projects[i].name = title; s.projects[i].color = color; s.projects[i].folder = folder }
                else { var p = Project(name: title, color: color, kind: itemKind); p.folder = folder; s.projects.append(p) }
            }
        case .tag(let id):
            guard !state.data.tags.contains(where: { $0.id != id && $0.name.localizedCaseInsensitiveCompare(title) == .orderedSame }) else { state.errorMessage = "Тег с таким названием уже есть"; return }
            state.change { s in
                if let i = s.tags.firstIndex(where: { $0.id == id }) { s.tags[i].name = title; s.tags[i].color = color; s.tags[i].parentID = parentID }
                else { s.tags.append(Tag(name: title, color: color, parentID: parentID)) }
            }
        case .section(let id):
            if let message = state.createSection(title, in: id) { sectionError = message; return }
        }
        dismiss()
    }
}
