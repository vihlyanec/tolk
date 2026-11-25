import SwiftUI
import TaktCore

struct CaptureSuggestion: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let replacement: String
    var createProject = false
    var createTag = false
    var replacementRange: NSRange?
    var projectID: UUID?
    var projectName: String?

    func applying(to text: String, lastToken: String) -> String {
        let range = replacementRange ?? NSRange(location: (text as NSString).length - (lastToken as NSString).length, length: (lastToken as NSString).length)
        return (text as NSString).replacingCharacters(in: range, with: replacement + " ")
    }

    static func projectPaths(in text: String, projects: [Project], allowCreation: Bool = false) -> [Self]? {
        guard let range = QuickProjectPath.completionRange(in: text) else { return nil }
        let query = (text as NSString).substring(with: range)
        var choices = QuickProjectPath.completions(for: query, projects: projects).map { value in
            Self(id: value.project.id.uuidString + (value.section.map { "/" + $0 } ?? ""),
                 title: value.project.name + (value.section.map { " / " + $0 } ?? ""),
                 symbol: value.section == nil ? "folder" : "rectangle.split.3x1", replacement: value.command,
                 replacementRange: range, projectID: value.project.id)
        }
        let name = String(query.dropFirst())
        if allowCreation && choices.isEmpty && !name.isEmpty && !name.contains(where: { $0.isWhitespace || $0 == "/" || $0 == "\"" }),
           QuickProjectPath.matches(in: query, projects: projects).isEmpty {
            choices.append(Self(id: "create", title: "Создать проект «\(name)»", symbol: "plus",
                                replacement: QuickProjectPath.command(name), createProject: true, replacementRange: range, projectName: name))
        }
        return choices
    }
}
struct QuickCaptureView: View {
    @Bindable var state: AppState
    let initialDate: Date?
    let initialDuration: Int?
    let dismiss: () -> Void
    let heightChanged: (CGFloat) -> Void
    let width: CGFloat
    @ViewState private var text: String
    @ViewState private var literals: [QuickLiteralToken]
    @ViewState private var description: String
    @ViewState private var descriptionExpanded: Bool
    @ViewState private var descriptionFocus: UUID?
    @ViewState private var titleFocused = true
    @ViewState private var titleFocus: UUID?
    @ViewState private var highlighted = 0
    @ViewState private var durationOverride: Int?
    init(state: AppState, initialDate: Date? = nil, initialDuration: Int? = nil, width: CGFloat = 640, heightChanged: @escaping (CGFloat) -> Void = { _ in }, dismiss: @escaping () -> Void) {
        self.state = state; self.initialDate = initialDate; self.initialDuration = initialDuration; self.heightChanged = heightChanged; self.dismiss = dismiss; self.width = width
        _text = State(initialValue: state.data.preferences.quickDraft)
        _description = State(initialValue: state.data.preferences.quickDraftBody ?? "")
        _descriptionExpanded = State(initialValue: state.data.preferences.quickDraftDescriptionExpanded == true || !(state.data.preferences.quickDraftBody ?? "").isEmpty)
        _literals = State(initialValue: (state.data.preferences.quickDraftLiterals ?? []).filter { $0.matches(state.data.preferences.quickDraft) })
    }
    private var parsed: ParsedTask {
        var value = QuickParser.parse(text, projects: state.activeProjects, tags: state.data.tags, calendar: state.calendar, literalRanges: QuickLiteralToken.ranges(literals, in: text))
        if let durationOverride { value.duration = durationOverride }
        else if !value.hasExplicitDuration, let initialDuration { value.duration = initialDuration }
        return value
    }
    private var token: String { String(text.split(separator: " ", omittingEmptySubsequences: false).last ?? "") }
    private var suggestions: [CaptureSuggestion] {
        if QuickLiteralToken.suppressesSuggestions(literals, in: text) { return [] }
        if let paths = CaptureSuggestion.projectPaths(in: text, projects: state.activeProjects, allowCreation: true), !paths.isEmpty {
            return Array(paths.prefix(6))
        }
        if token.hasPrefix("#") {
            let query = String(token.dropFirst())
            let tags = state.data.tags.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
            var values = tags.map { CaptureSuggestion(id: $0.id.uuidString, title: "#" + $0.name, symbol: "number", replacement: Hashtags.command($0.name)) }
            if !query.isEmpty && tags.isEmpty { values.append(CaptureSuggestion(id: "create", title: "Создать тег «\(query)»", symbol: "plus", replacement: "#" + query, createTag: true)) }
            return Array(values.prefix(6))
        }
        if token == "!" { return [1,2,3,0].map { CaptureSuggestion(id: "\($0)", title: AppState.priorityTitle($0), symbol: "flag", replacement: "!\($0)") } }
        return []
    }
    private var visibleSuggestions: [CaptureSuggestion] { titleFocused ? suggestions : [] }
    private var panelHeight: CGFloat { 62 + (visibleSuggestions.isEmpty ? 0 : 11 + CGFloat(visibleSuggestions.count) * 34) + (descriptionExpanded ? 153 : 0) }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                SmartCaptureInput(text: $text, literals: $literals, parsed: parsed, projects: state.activeProjects, tags: state.data.tags,
                                  placeholder: "Добавить задачу…", fontSize: 16, autoFocus: true, focusRequest: titleFocus, singleLine: true, calendar: state.calendar,
                                  onFocus: { titleFocused = $0 }, expandDescription: openDescription, submit: submit,
                                  move: { direction in guard !suggestions.isEmpty else { return false }; highlighted = (highlighted + direction + suggestions.count) % suggestions.count; return true },
                                  complete: { guard !suggestions.isEmpty else { return false }; choose(suggestions[min(highlighted, suggestions.count - 1)]); return true })
                    .frame(height: 30)
                    .onChange(of: text) { _, _ in highlighted = 0; queueDraft() }
                    .onChange(of: literals) { _, _ in queueDraft() }
                DurationControl(minutes: Binding(get: { parsed.duration }, set: { durationOverride = $0 }))
            }.padding(.horizontal, 18).frame(height: 62)
            if !visibleSuggestions.isEmpty {
                Divider().padding(.horizontal, 12)
                VStack(spacing: 2) {
                    ForEach(Array(visibleSuggestions.enumerated()), id: \.element.id) { index, suggestion in
                        Button { choose(suggestion) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: suggestion.symbol).foregroundStyle(captureSuggestionColor(suggestion, state: state)).frame(width: 18)
                                Text(suggestion.title).lineLimit(1); Spacer()
                            }.font(.system(size: 12)).padding(.horizontal, 10).frame(height: 32).contentShape(Rectangle())
                        }.buttonStyle(.plain).background(index == highlighted ? Palette.accent.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 6))
                    }
                }.padding(6)
            }
            if descriptionExpanded {
                Divider().padding(.horizontal, 18)
                CaptureDescriptionView(text: $description, tags: state.data.tags, focusRequest: descriptionFocus, save: save)
            }
        }.frame(width: width, height: panelHeight).background(Palette.sidebar, in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).stroke(Palette.line, lineWidth: 1) }
            .preferredColorScheme(state.data.preferences.theme == "light" ? .light : state.data.preferences.theme == "dark" ? .dark : nil)
            .onAppear { heightChanged(panelHeight) }
            .onChange(of: panelHeight) { _, height in heightChanged(height) }
            .onChange(of: description) { _, _ in queueDraft() }
            .onChange(of: descriptionExpanded) { _, _ in queueDraft() }
            .onDisappear { state.flushQuickDraft() }
            .onExitCommand(perform: cancel)
    }
    private func openDescription() { descriptionExpanded = true; titleFocused = false; descriptionFocus = UUID() }
    private func setText(_ value: String) { literals = QuickLiteralToken.rebased(literals, from: text, to: value); text = value }
    private func queueDraft() {
        state.queueQuickDraft(QuickCaptureDraft(text: text, literals: literals, body: description, descriptionExpanded: descriptionExpanded))
    }
    private func cancel() { state.clearQuickDraft(); dismiss() }
    private func choose(_ suggestion: CaptureSuggestion) {
        let name = suggestion.projectName ?? String(token.dropFirst())
        if suggestion.createProject { state.change { $0.projects.append(Project(name: name, color: ProjectTagPalette.nextColor(in: $0))) } }
        if suggestion.createTag { state.change { $0.tags.append(Tag(name: name, color: ProjectTagPalette.nextColor(in: $0))) } }
        setText(suggestion.applying(to: text, lastToken: token))
    }
    private func submit() {
        switch CaptureBehavior.submitAction(text: text, parsed: parsed, suggestionCount: suggestions.count) {
        case .applySuggestion: choose(suggestions[min(highlighted, suggestions.count - 1)])
        case .finishToken: setText(text + " ")
        case .create: save()
        case .stay: break
        }
    }
    private func save() {
        guard !parsed.title.isEmpty else { titleFocus = UUID(); return }
        guard state.capture(parsed, body: description, initialDate: initialDate) != nil else { return }
        state.clearQuickDraft(); dismiss()
    }
}

struct DurationControl: View {
    @Binding var minutes: Int
    @ViewState private var custom = false
    var body: some View {
        Menu {
            ForEach([15,30,45,60,90,120,180], id: \.self) { value in
                Button(value % 60 == 0 ? "\(value / 60) ч" : "\(value) мин") { minutes = value }
            }
            Divider(); Button("Своя длительность…") { custom = true }
        } label: {
            Label(minutes % 60 == 0 ? "\(minutes / 60) ч" : "\(minutes) мин", systemImage: "clock")
                .font(.system(size: 11)).padding(6).background(Palette.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 4))
        }.menuStyle(.borderlessButton).fixedSize().help("Изменить длительность задачи")
            .popover(isPresented: $custom) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Длительность задачи").fontWeight(.semibold)
                    HStack { TextField("Минуты", value: Binding(get: { minutes }, set: { minutes = max(1, min(10080, $0)) }), format: .number).frame(width: 80); Text("минут") }
                    Button("Готово") { custom = false }.keyboardShortcut(.defaultAction)
                }.padding(18)
            }
    }
}

struct InlineQuickEntry: View {
    @Bindable var state: AppState
    var section: String?
    var onFinish: (() -> Void)?
    @ViewState private var text = ""
    @ViewState private var minutes: Int?
    @ViewState private var literals: [QuickLiteralToken] = []
    @ViewState private var selectedSuggestion = 0
    @ViewState private var focused = false
    @ViewState private var titleFocus: UUID?
    @ViewState private var description = ""
    @ViewState private var descriptionExpanded = false
    @ViewState private var descriptionFocus: UUID?
    private var parsed: ParsedTask {
        var value = QuickParser.parse(text, projects: state.activeProjects, tags: state.data.tags, calendar: state.calendar, literalRanges: QuickLiteralToken.ranges(literals, in: text))
        if let minutes { value.duration = minutes }; return value
    }
    private var token: String { String(text.split(separator: " ", omittingEmptySubsequences: false).last ?? "") }
    private var choices: [CaptureSuggestion] {
        if QuickLiteralToken.suppressesSuggestions(literals, in: text) { return [] }
        if let paths = CaptureSuggestion.projectPaths(in: text, projects: state.activeProjects), !paths.isEmpty {
            return Array(paths.prefix(5))
        }
        if token.hasPrefix("#") {
            let query = String(token.dropFirst())
            let tags = state.data.tags.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
            if tags.isEmpty && !query.isEmpty { return [CaptureSuggestion(id: "create", title: "Создать тег «\(query)»", symbol: "plus", replacement: Hashtags.command(query), createTag: true)] }
            return tags.prefix(5).map { CaptureSuggestion(id: $0.id.uuidString, title: "#" + $0.name, symbol: "number", replacement: Hashtags.command($0.name)) }
        }
        if token == "!" { return [1,2,3,0].map { CaptureSuggestion(id: "\($0)", title: AppState.priorityTitle($0), symbol: "flag", replacement: "!\($0)") } }
        return []
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle").foregroundStyle(Palette.accent)
                SmartCaptureInput(text: $text, literals: $literals, parsed: parsed, projects: state.activeProjects, tags: state.data.tags,
                                  placeholder: section != nil ? "Название задачи" : state.scope == .today ? "Добавить на сегодня…" : "Добавить задачу…  /проект/этап   #тег   !приоритет",
                                  fontSize: 13, focusRequest: titleFocus, singleLine: true, calendar: state.calendar,
                                  onFocus: { focused = $0 }, expandDescription: openDescription, submit: submit,
                                  move: { direction in guard !choices.isEmpty else { return false }; selectedSuggestion = (selectedSuggestion + direction + choices.count) % choices.count; return true })
                    .frame(height: 32)
                    .onChange(of: text) { _, _ in selectedSuggestion = 0 }
                if section == nil { DurationControl(minutes: Binding(get: { parsed.duration }, set: { minutes = $0 })) }
                Button(action: save) { Image(systemName: "return").frame(width: 24, height: 24) }.buttonStyle(.plain).disabled(parsed.title.isEmpty).help("Добавить задачу")
                if let onFinish { IconButton(symbol: "xmark", help: "Закрыть добавление", action: onFinish) }
            }.padding(.horizontal, 12).padding(.vertical, 8).background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
                .overlay { RoundedRectangle(cornerRadius: 7).stroke(focused ? Palette.accent.opacity(0.6) : Palette.line, lineWidth: 1) }
            if focused && !choices.isEmpty {
                VStack(spacing: 1) {
                    ForEach(Array(choices.enumerated()), id: \.element.id) { index, choice in
                        Button { choose(choice) } label: { HStack { Image(systemName: choice.symbol).foregroundStyle(captureSuggestionColor(choice, state: state)); Text(choice.title); Spacer() }.padding(8).contentShape(Rectangle()) }
                            .buttonStyle(.plain).background(index == selectedSuggestion ? Palette.accent.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 4))
                    }
                }.padding(4).background(Palette.sidebar, in: RoundedRectangle(cornerRadius: 6))
            } else if !text.isEmpty {
                HStack(spacing: 9) {
                    if let date = parsed.schedule.date { Text(state.dayLabel(date) + (parsed.schedule.isTimed ? ", " + state.time(date) : "")) }
                    if let id = parsed.projectID { Text(state.projectName(id) + (parsed.section.map { " / " + $0 } ?? "")) }
                    if parsed.priority != 0 { PriorityCapsule(priority: parsed.priority) }
                    ForEach(parsed.tagIDs, id: \.self) { id in if let tag = state.data.tags.first(where: { $0.id == id }) { TagCapsule(tag: tag) } }
                    if let warning = parsed.warnings.first { Text(warning).foregroundStyle(.orange) }
                }.font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
            if descriptionExpanded {
                CaptureDescriptionView(text: $description, tags: state.data.tags, focusRequest: descriptionFocus, horizontalInset: 12, save: save)
                    .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 7))
            }
        }.padding(.horizontal, section == nil ? 22 : 0).padding(.bottom, section == nil ? 14 : 5)
            .onAppear { if section != nil { titleFocus = UUID() } }
    }
    private func openDescription() { descriptionExpanded = true; focused = false; descriptionFocus = UUID() }
    private func setText(_ value: String) { literals = QuickLiteralToken.rebased(literals, from: text, to: value); text = value }
    private func choose(_ choice: CaptureSuggestion) {
        if choice.createTag { state.change { $0.tags.append(Tag(name: String(token.dropFirst()), color: ProjectTagPalette.nextColor(in: $0))) } }
        setText(choice.applying(to: text, lastToken: token)); focused = true }
    private func submit() {
        switch CaptureBehavior.submitAction(text: text, parsed: parsed, suggestionCount: choices.count) {
        case .applySuggestion: choose(choices[min(selectedSuggestion, choices.count - 1)])
        case .finishToken: setText(text + " ")
        case .create: save()
        case .stay: break
        }
    }
    private func save() {
        guard !parsed.title.isEmpty else { titleFocus = UUID(); return }
        guard state.capture(parsed, body: description, defaultSection: section) != nil else { return }
        text = ""; literals = []; minutes = nil; description = ""; descriptionExpanded = false; descriptionFocus = nil; titleFocus = UUID(); focused = true
        onFinish?()
    }
}

struct StickyView: View {
    @Bindable var state: AppState
    let id: UUID
    let close: () -> Void
    var toggleCollapsed: () -> Void = {}
    @ViewState private var action: EditorAction?
    private var item: Item? { state.data.items.first { $0.id == id && !$0.deleted } }
    var body: some View {
        if let item {
            let collapsed = item.stickyCollapsed == true
            VStack(spacing: 0) {
                StickyDragHandle(title: item.title, collapsed: collapsed, toggle: toggleCollapsed)
                    .frame(height: collapsed ? StickyGeometry.collapsedHeight : 16)
                if !collapsed {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            if item.kind == .task { CompleteButton(item: item) { state.complete(id) } }
                            TagTitleInput(text: Binding(get: { item.title }, set: { text in state.update(id) { $0.title = text } }), tags: state.data.tags, fontSize: 16, placeholder: "Название заметки", onCommit: { state.commitHashtags(id) })
                            Menu {
                                Button("Свернуть в полоску", action: toggleCollapsed)
                                Button(item.stickyPinned ? "Не держать поверх окон" : "Поверх других окон") { state.update(id) { $0.stickyPinned.toggle() } }
                                Menu("Цвет заметки") {
                                    ForEach(["AD94E8", "598BFF", "5BC9A2", "E6A467"], id: \.self) { color in
                                        Button(["AD94E8":"Сиреневый", "598BFF":"Синий", "5BC9A2":"Зелёный", "E6A467":"Тёплый"][color] ?? color) { state.update(id) { $0.stickyColor = color } }
                                    }
                                }
                                Button("Жирный") { action = EditorAction(before: "**", after: "**") }
                                if item.kind == .note {
                                    Button("Создать задачу из строки") { action = EditorAction(before: "convert-task", after: "") }
                                }
                                Divider(); Button("Скрыть заметку", action: close)
                            } label: { Image(systemName: "ellipsis").frame(width: 24, height: 24).contentShape(Rectangle()) }
                                .menuStyle(.borderlessButton).fixedSize().help("Действия с заметкой")
                        }
                        if !state.tagIDs(for: item).isEmpty { FlowTags(state: state, item: item) }
                        RichNoteEditor(text: Binding(get: { self.item?.body ?? "" }, set: { text in state.update(id) { $0.body = text } }),
                                       action: action, tags: state.data.tags, commitTags: { state.commitHashtags(id) },
                                       convertLine: { line, occurrence, title, done, suffix in
                                           state.createTaskFromNoteLine(noteID: id, sourceLine: line, occurrence: occurrence, title: title, completed: done, suffix: suffix)
                                       }, openLinkedTask: state.openLinkedTask,
                                       conversionUnavailable: { state.errorMessage = "Поставьте курсор после текста задачи в заметке." })
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        if let error = state.errorMessage { Text(error).font(.system(size: 11)).foregroundStyle(.red) }
                    }.padding(.horizontal, 12).padding(.bottom, 12)
                }
            }.background(Color(hex: item.stickyColor).opacity(0.13)).background(Palette.sidebar)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay { RoundedRectangle(cornerRadius: 10).stroke(Palette.line, lineWidth: 1) }
                .preferredColorScheme(state.data.preferences.theme == "light" ? .light : state.data.preferences.theme == "dark" ? .dark : nil)
        }
    }
}

private func captureSuggestionColor(_ suggestion: CaptureSuggestion, state: AppState) -> Color {
    let dark = state.data.preferences.theme != "light"
    if suggestion.symbol == "flag" { return Color(nsColor: SemanticTint.priority(Int(suggestion.id) ?? 0, dark: dark)) }
    let hex = state.data.tags.first { $0.id.uuidString == suggestion.id }?.color ?? state.data.projects.first { $0.id == suggestion.projectID || $0.id.uuidString == suggestion.id }?.color ?? "598BFF"
    return Color(nsColor: SemanticTint.color(hex: hex, dark: dark))
}

/// Optional details stay inside the capture draft until the task is submitted.
struct CaptureDescriptionView: View {
    @Binding var text: String
    let tags: [Tag]
    let focusRequest: UUID?
    var horizontalInset: CGFloat = 18
    let save: () -> Void
    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            MarkdownEditor(text: $text, tags: tags, placeholder: "Описание задачи", focusRequest: focusRequest, submit: save)
                .frame(height: 110)
            Text("⌘↵ — добавить задачу").font(.system(size: 10)).foregroundStyle(.secondary)
        }.padding(.horizontal, horizontalInset).padding(.top, 10).padding(.bottom, 12).frame(height: 152)
    }
}
