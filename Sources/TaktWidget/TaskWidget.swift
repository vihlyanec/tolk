import AppIntents
import SwiftUI
import WidgetKit

struct TaskWidgetEntry: TimelineEntry {
    enum Availability { case ready, needsApp, missingList }
    let date: Date
    let listID: String
    let title: String
    let tasks: [WidgetTask]
    let timeZone: TimeZone
    var availability = Availability.ready
    var preview = false

    static var example: Self {
        let zone = TimeZone(identifier: "Europe/Moscow") ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let day = calendar.startOfDay(for: .now)
        let rows = [
            WidgetTask(id: UUID(), title: "Сверить смету с подрядчиком", date: day.addingTimeInterval(-86400), timed: false, priority: 1, revision: day),
            WidgetTask(id: UUID(), title: "Отправить правки к макету", date: day.addingTimeInterval(39600), timed: true, priority: 2, revision: day),
            WidgetTask(id: UUID(), title: "Согласовать дату созвона", date: day.addingTimeInterval(52200), timed: true, priority: 0, revision: day)
        ]
        return .init(date: .now, listID: "today", title: "Сегодня", tasks: rows, timeZone: zone, preview: true)
    }
}

struct TaskWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TaskWidgetEntry { .example }
    func snapshot(for configuration: ChooseTaskList, in context: Context) async -> TaskWidgetEntry {
        context.isPreview ? .example : entry(configuration)
    }
    func timeline(for configuration: ChooseTaskList, in context: Context) async -> Timeline<TaskWidgetEntry> {
        Timeline(entries: [entry(configuration)], policy: .after(.now.addingTimeInterval(15 * 60)))
    }

    private func entry(_ configuration: ChooseTaskList) -> TaskWidgetEntry {
        let id = configuration.list?.id ?? "today"
        let title = configuration.list?.name ?? "Сегодня"
        guard let data = try? WidgetStore.installed?.read(), !data.lists.isEmpty else {
            return .init(date: .now, listID: id, title: title, tasks: [], timeZone: .current, availability: .needsApp)
        }
        let zone = TimeZone(identifier: data.timeZone) ?? .current
        guard let list = data.lists.first(where: { $0.id == id }) else {
            return .init(date: .now, listID: id, title: title, tasks: [], timeZone: zone, availability: .missingList)
        }
        return .init(date: .now, listID: id, title: list.title, tasks: data.tasks(in: list), timeZone: zone)
    }
}

struct TaskWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var appearance
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    let entry: TaskWidgetEntry
    private var blue: Color { Color(red: 89 / 255, green: 139 / 255, blue: 1) }
    private var secondary: Color { appearance == .dark ? .secondary : Color(white: 0.42) }
    private var home: URL { widgetURL("list", entry.listID) }

    private func widgetURL(_ action: String, _ identifier: String) -> URL {
        URL(string: "\(WidgetStore.scheme)://\(action)/\(identifier)")!
    }

    var body: some View {
        GeometryReader { space in
            let rowsThatFit = max(1, Int((space.size.height - 26) / 24))
            list(limit: min(rowsThatFit, family == .systemLarge ? 10 : 5))
        }
        .widgetURL(home)
        .containerBackground(for: .widget) {
            appearance == .dark ? Color(red: 0.145, green: 0.153, blue: 0.172) : Color.white
        }
    }

    private func list(limit: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 7) {
                widgetLink(to: home) { Text(entry.title) }.font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary).lineLimit(1).privacySensitive()
                if entry.availability == .ready {
                    Text(entry.tasks.count, format: .number).font(.caption).monospacedDigit().foregroundStyle(secondary)
                        .accessibilityLabel("Задач: \(entry.tasks.count)")
                }
                Spacer(minLength: 3)
                widgetLink(to: widgetURL("new", entry.listID)) {
                    Image(systemName: "plus").font(.system(size: 14, weight: .semibold))
                        .frame(width: 24, height: 22).foregroundStyle(blue)
                }.accessibilityLabel("Добавить задачу")
            }.padding(.bottom, 2)

            if entry.tasks.isEmpty { emptyState }
            ForEach(entry.tasks.prefix(limit)) { task in row(task) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private var emptyState: some View {
        switch entry.availability {
        case .ready:
            Text(entry.listID == "today" ? "На сегодня всё" : "Нет открытых задач").foregroundStyle(secondary)
        case .needsApp:
            Link("Открыть \(WidgetStore.appName)", destination: home).foregroundStyle(blue)
        case .missingList:
            Text("Выберите другой список в настройках виджета").foregroundStyle(secondary)
        }
    }

    private func row(_ task: WidgetTask) -> some View {
        HStack(spacing: 5) {
            if entry.preview { checkbox(task) }
            else {
                Button(intent: CompleteWidgetTask(task)) { checkbox(task) }
                    .buttonStyle(.plain).accessibilityLabel("Выполнить: \(task.title)")
                    .accessibilityValue(priorityLabel(task.priority))
            }
            widgetLink(to: widgetURL("task", task.id.uuidString)) {
                HStack(spacing: 8) {
                    Text(task.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    Spacer(minLength: 0)
                    if let label = dateLabel(task) {
                        Text(label.text).font(.system(size: 11)).monospacedDigit().fixedSize()
                            .foregroundStyle(label.overdue ? overdueColor : secondary)
                            .accessibilityLabel(label.overdue ? "Просрочено, \(label.text)" : label.text)
                    }
                }.contentShape(Rectangle())
            }.foregroundStyle(.primary)
        }.frame(height: 21).privacySensitive()
    }

    @ViewBuilder private func widgetLink<Label: View>(to url: URL, @ViewBuilder label: () -> Label) -> some View {
        if entry.preview { label() }
        else { Link(destination: url, label: label).buttonStyle(.plain) }
    }

    private var overdueColor: Color { appearance == .dark ? Color(red: 1, green: 0.48, blue: 0.45) : Color(red: 0.70, green: 0.12, blue: 0.14) }
    private func priorityLabel(_ priority: Int) -> String {
        switch priority {
        case 1: "Высокий приоритет"
        case 2: "Средний приоритет"
        case 3: "Низкий приоритет"
        default: "Без приоритета"
        }
    }
    private func checkbox(_ task: WidgetTask) -> some View {
        let color: Color = switch task.priority {
        case 1: overdueColor
        case 2: appearance == .dark ? Color(red: 1, green: 0.67, blue: 0.35) : Color(red: 0.65, green: 0.32, blue: 0.07)
        case 3: blue
        default: secondary
        }
        let symbol = differentiateWithoutColor && (1...3).contains(task.priority) ? "\(task.priority).circle" : "circle"
        return Image(systemName: symbol).font(.system(size: 15, weight: .medium))
            .foregroundStyle(color).frame(width: 25, height: 22).contentShape(Rectangle())
    }

    private func dateLabel(_ task: WidgetTask) -> (text: String, overdue: Bool)? {
        guard let date = task.date else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = entry.timeZone
        let today = calendar.startOfDay(for: entry.date)
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today), calendar.isDate(date, inSameDayAs: yesterday) {
            return ("Вчера", true)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.calendar = calendar
        formatter.timeZone = entry.timeZone
        if calendar.isDate(date, inSameDayAs: today) {
            guard task.timed else { return nil }
            formatter.dateFormat = "HH:mm"
        } else { formatter.dateFormat = "d MMM" }
        return (formatter.string(from: date), date < today)
    }
}

@main struct TaskWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetStore.kind, intent: ChooseTaskList.self, provider: TaskWidgetProvider()) { entry in
            TaskWidgetView(entry: entry)
        }
        .configurationDisplayName("Задачи Толка")
        .description("Сегодня, проект, тег или сохранённый фильтр.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}
