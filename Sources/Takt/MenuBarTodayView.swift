import SwiftUI
import TaktCore

/// A fixed Today surface sharing the real AppState, without changing main-window filters.
struct MenuBarTodayView: View {
    @Bindable var state: AppState
    let openTask: (UUID) -> Void
    let openMain: () -> Void
    let openSettings: () -> Void
    let close: () -> Void
    @ViewState private var draft = ""
    @FocusState private var captureFocused: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            let tasks = state.menuTodayTasks
            let overdue = tasks.filter(state.isOverdue)
            let today = tasks.filter { !state.isOverdue($0) }
            VStack(spacing: 0) {
                HStack {
                    Text("Сегодня").font(.system(size: 20, weight: .semibold))
                    Spacer()
                    Text("\(tasks.count)").font(.system(size: 13)).monospacedDigit().foregroundStyle(.secondary)
                    IconButton(symbol: "xmark", help: "Закрыть список на сегодня", action: close)
                }.padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 6)
                HStack(spacing: 8) {
                    Image(systemName: "plus").foregroundStyle(Palette.accent)
                    TextField("Добавить задачу на сегодня", text: $draft)
                        .textFieldStyle(.plain).focused($captureFocused).onSubmit(addTask)
                        .accessibilityLabel("Новая задача на сегодня")
                    Button(action: addTask) { Image(systemName: "return") }
                        .buttonStyle(.plain).foregroundStyle(Palette.accent)
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .help("Добавить на сегодня").accessibilityLabel("Добавить на сегодня")
                }.padding(12).background(Palette.canvas, in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 16).padding(.bottom, 12)
                Divider()
                if tasks.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "checkmark.circle").font(.system(size: 30, weight: .light)).foregroundStyle(Palette.accent)
                        Text("На сегодня всё").font(.headline)
                        Text("Здесь будут задачи на сегодня\nи незавершённые просроченные.")
                            .foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            if !overdue.isEmpty { section("Просрочено", tasks: overdue) }
                            if !today.isEmpty { section("Сегодня", tasks: today) }
                        }.padding(.vertical, 6)
                    }.frame(maxHeight: .infinity)
                }
                if let error = state.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                }
                Divider()
                HStack {
                    Button(action: openMain) { Label("Открыть Толк", systemImage: "arrow.up.right.square") }
                        .buttonStyle(.plain).foregroundStyle(Palette.accent)
                    Spacer()
                    IconButton(symbol: "gearshape", help: "Настройки Толка", action: openSettings)
                }.padding(.horizontal, 16).padding(.vertical, 8)
            }.frame(width: 380, height: 560).background(Palette.sidebar)
        }
        .font(.system(size: 13)).tint(Palette.accent)
        .preferredColorScheme(state.data.preferences.theme == "dark" ? .dark : state.data.preferences.theme == "light" ? .light : nil)
        .onExitCommand(perform: close)
    }
    private func addTask() {
        guard state.captureMenuToday(draft) != nil else { return }
        draft = ""; captureFocused = true
    }
    private func section(_ title: String, tasks: [Item]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 6)
            ForEach(tasks) { item in
                HStack(alignment: .top, spacing: 8) {
                    CompleteButton(item: item) { state.complete(item.id) }
                    Button { openTask(item.id) } label: {
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title).lineLimit(2).multilineTextAlignment(.leading).foregroundStyle(.primary)
                                if let project = state.data.projects.first(where: { $0.id == item.projectID }) {
                                    Text(project.name).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            Spacer(minLength: 0)
                            Text(scheduleLabel(item)).font(.system(size: 11)).monospacedDigit()
                                .foregroundStyle(state.isOverdue(item) ? Color.red : .secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain).help("Открыть задачу: " + item.title)
                }.padding(.horizontal, 16).padding(.vertical, 9)
            }
        }
    }
    private func scheduleLabel(_ item: Item) -> String {
        guard let date = item.schedule.date else { return "" }
        if state.isOverdue(item) {
            if state.calendar.isDateInYesterday(date) { return "Вчера" }
            let formatter = DateFormatter(); formatter.calendar = state.calendar
            formatter.timeZone = state.calendar.timeZone; formatter.locale = Locale(identifier: "ru_RU")
            formatter.dateFormat = "d MMM"; return formatter.string(from: date)
        }
        if item.schedule.isTimed {
            let formatter = DateFormatter(); formatter.timeZone = state.calendar.timeZone
            formatter.dateFormat = "HH:mm"; return formatter.string(from: date)
        }
        return ""
    }
}
