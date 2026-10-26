import SwiftUI
import AppKit
import TaktCore

struct NotesWorkspace: View {
    @Bindable var state: AppState
    @ViewState private var trash = false
    private var notes: [Item] {
        state.data.items.filter { $0.kind == .note && $0.deleted == trash && state.matchesQuery($0, state.search) }.sorted { $0.modified > $1.modified }
    }
    private var selected: Item? { notes.first { $0.id == state.selectedID } }
    var body: some View {
        HStack(spacing: 0) {
            if state.sidebarVisible {
                VStack(spacing: 0) {
                    HStack {
                        Text(trash ? "Корзина заметок" : "Заметки").font(.system(size: 20, weight: .semibold)); Spacer()
                        IconButton(symbol: "square.and.pencil", help: "Создать заметку") { trash = false; state.createNote() }
                    }.padding(16)
                    HStack { Image(systemName: "magnifyingglass").foregroundStyle(.secondary); TextField("Поиск заметок", text: $state.search).textFieldStyle(.plain) }
                        .padding(8).background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 6)).padding(.horizontal, 12).padding(.bottom, 12)
                    Divider()
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(notes) { note in
                                Button { state.selectedID = note.id } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(note.title.isEmpty ? "Новая заметка" : note.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                                        Text(note.body.isEmpty ? "Нет дополнительного текста" : note.body).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                                        Text(state.dayLabel(note.modified)).font(.system(size: 10)).foregroundStyle(.secondary)
                                    }.frame(maxWidth: .infinity, alignment: .leading).padding(12).contentShape(Rectangle())
                                }.buttonStyle(.plain).background(state.selectedID == note.id ? Palette.accent.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 6))
                                    .contextMenu { ItemContextMenu(state: state, item: note) }
                            }
                        }.padding(8)
                    }
                    Divider()
                    HStack { Text(noteCountLabel).font(.system(size: 11)).foregroundStyle(.secondary); Spacer(); Button { trash.toggle(); state.selectedID = nil } label: { Label(trash ? "Все заметки" : "Корзина", systemImage: trash ? "note.text" : "trash") }.buttonStyle(.plain) }.padding(12)
                }.frame(width: 320).background(Palette.sidebar)
                Divider()
            }
            if let note = selected { NoteDocumentEditor(state: state, id: note.id).id(note.id) }
            else { EmptyState(symbol: "note.text", title: notes.isEmpty ? "Нет заметок" : "Выберите заметку", detail: "Создайте заметку кнопкой слева или через Control-D.") }
        }.onAppear { chooseFirst() }
            .onChange(of: state.data.items.map { $0.id.uuidString + String($0.deleted) }) { _, _ in chooseFirst() }
            .onChange(of: state.search) { _, _ in chooseFirst() }
            .onChange(of: trash) { _, _ in chooseFirst() }
    }
    private var noteCountLabel: String {
        let count = notes.count
        let suffix = (11...14).contains(count % 100) ? "заметок" : count % 10 == 1 ? "заметка" : (2...4).contains(count % 10) ? "заметки" : "заметок"
        return "\(count) \(suffix)"
    }
    private func chooseFirst() { if selected == nil { state.selectedID = notes.first?.id } }
}
struct NoteDocumentEditor: View {
    @Bindable var state: AppState
    let id: UUID
    @ViewState private var format: EditorAction?
    @ViewState private var linkOpen = false
    @ViewState private var linkURL = "https://"
    private var item: Item? { state.data.items.first { $0.id == id } }
    var body: some View {
        if let item {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    if item.deleted { Button("Восстановить заметку") { state.update(id) { $0.deleted = false } } }
                    else {
                        formatButton("bold", "Жирный", "**", "**")
                        formatButton("italic", "Курсив", "*", "*")
                        formatButton("textformat.size", "Заголовок", "## ", "")
                        formatButton("checklist", "Чек-лист", "- [ ] ", "")
                        Menu {
                            Button("Маркированный список") { format = EditorAction(before: "- ", after: "") }
                            Button("Нумерованный список") { format = EditorAction(before: "1. ", after: "") }
                            Button("Цитата") { format = EditorAction(before: "> ", after: "") }
                            Button("Зачёркнутый") { format = EditorAction(before: "~~", after: "~~") }
                            Button("Код") { format = EditorAction(before: "`", after: "`") }
                            Button("Блок кода") { format = EditorAction(before: "```\n", after: "\n```") }
                            Button("Ссылка…") { linkURL = "https://"; linkOpen = true }
                            Button("Таблица") { format = EditorAction(before: "| Колонка 1 | Колонка 2 |\n| --- | --- |\n| ", after: " | |\n") }
                            Button("Разделитель") { format = EditorAction(before: "\n---\n", after: "") }
                        } label: { Image(systemName: "textformat").frame(width: 28, height: 28) }.menuStyle(.borderlessButton).fixedSize().help("Дополнительное форматирование")
                    }
                    Spacer()
                    IconButton(symbol: "pin", help: "Открыть стикер") { state.showSticky(id) }.disabled(item.deleted)
                    Menu {
                        Picker("Проект", selection: Binding(get: { self.item?.projectID }, set: { value in state.update(id) { $0.projectID = value } })) {
                            Text("Без проекта").tag(nil as UUID?)
                            ForEach(state.activeProjects.filter { $0.kind == .note }) { Text($0.name).tag(Optional($0.id)) }
                        }
                        Button("Создать проект заметок…") { state.sheet = .project(nil) }
                        Divider()
                        ForEach(state.data.tags) { tag in
                            Toggle(tag.name, isOn: Binding(get: { self.item?.tagIDs.contains(tag.id) == true }, set: { on in state.update(id) { value in value.tagIDs.removeAll { $0 == tag.id }; if on { value.tagIDs.append(tag.id) } } }))
                        }
                        Button("Создать тег…") { state.sheet = .tag(nil) }
                    } label: { Image(systemName: "ellipsis").frame(width: 28, height: 28) }.fixedSize().menuStyle(.borderlessButton).help("Проект и теги заметки").disabled(item.deleted)
                    if !item.deleted { IconButton(symbol: "trash", help: "Удалить заметку") { state.delete(id) } }
                }.padding(.horizontal, 18).frame(height: 58)
                Divider()
                VStack(alignment: .leading, spacing: 14) {
                    Text(item.modified.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 11)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    TagTitleInput(text: Binding(get: { self.item?.title ?? "" }, set: { text in state.update(id) { $0.title = text } }), tags: state.data.tags, fontSize: 25, placeholder: "Название заметки", autoFocus: item.title.isEmpty && !item.deleted).disabled(item.deleted)
                    if !item.tagIDs.isEmpty { FlowTags(state: state, item: item) }
                    RichNoteEditor(text: Binding(get: { self.item?.body ?? "" }, set: { text in state.update(id) { $0.body = text } }), action: format, tags: state.data.tags, editable: !item.deleted).frame(maxWidth: .infinity, maxHeight: .infinity)
                }.padding(28)
            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.canvas)
                .popover(isPresented: $linkOpen) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Добавить ссылку").font(.headline)
                        TextField("Адрес ссылки", text: $linkURL).textFieldStyle(.roundedBorder)
                        HStack {
                            Button("Отмена") { linkOpen = false }
                            Spacer()
                            Button("Добавить") { format = EditorAction(before: "[", after: "](\(linkURL))"); linkOpen = false }
                                .disabled(MarkdownHTML.safeURL(linkURL) == nil).keyboardShortcut(.defaultAction)
                        }
                    }.padding(16).frame(width: 300)
                }
        }
    }
    private func formatButton(_ symbol: String, _ title: String, _ before: String, _ after: String) -> some View {
        IconButton(symbol: symbol, help: title) { format = EditorAction(before: before, after: after) }
    }
}


