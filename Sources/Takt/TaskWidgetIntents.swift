import AppIntents
import Foundation
import WidgetKit
#if !TOLK_WIDGET_STANDALONE
import TaktCore
#endif

nonisolated struct TaskListChoice: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Список задач"
    static let defaultQuery = TaskListQuery()
    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        let subtitle: LocalizedStringResource? = switch id.split(separator: ":").first {
        case "project": "Проект"
        case "tag": "Тег"
        case "filter": "Сохранённый фильтр"
        default: nil
        }
        return DisplayRepresentation(title: "\(name)", subtitle: subtitle)
    }
}

nonisolated struct TaskListQuery: EntityQuery {
    func defaultResult() async -> TaskListChoice? { .init(id: "today", name: "Сегодня") }

    func entities(for identifiers: [String]) async throws -> [TaskListChoice] {
        let choices = try await suggestedEntities()
        return identifiers.compactMap { id in choices.first { $0.id == id } }
    }

    func suggestedEntities() async throws -> [TaskListChoice] {
        let lists = try WidgetStore.installed?.read().lists ?? []
        if lists.isEmpty {
            return [.init(id: "today", name: "Сегодня"), .init(id: "inbox", name: "Входящие"),
                    .init(id: "week", name: "Следующие 7 дней")]
        }
        return lists.map { .init(id: $0.id, name: $0.title) }
    }
}

nonisolated struct ChooseTaskList: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Задачи Толка"
    static let description = IntentDescription("Выберите список для этого виджета.")
    @Parameter(title: "Показывать") var list: TaskListChoice?
}

nonisolated struct CompleteWidgetTask: AppIntent {
    static let title: LocalizedStringResource = "Отметить задачу выполненной"
    static let openAppWhenRun = false
    static let isDiscoverable = false
    @Parameter(title: "Задача") var taskID: String
    @Parameter(title: "Версия задачи") var revision: Double

    init() {}
    init(_ task: WidgetTask) {
        taskID = task.id.uuidString
        revision = task.revision.timeIntervalSinceReferenceDate
    }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: taskID), let store = WidgetStore.installed else { return .result() }
        try store.complete(id, revision: Date(timeIntervalSinceReferenceDate: revision))
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetStore.kind)
        return .result()
    }
}
