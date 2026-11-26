import Foundation
import Testing
import TaktCore
@testable import Takt

@Test @MainActor func widgetListsShareCompletionAndDemoRestartKeepsIt() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = WidgetStore(directory: directory)
    let url = directory.appendingPathComponent("demo.sqlite")
    let state = AppState(demo: true, storageURL: url)
    let bridge = WidgetBridge(store: store, state: state)
    bridge.start()
    defer { bridge.stop() }
    var widget = try store.read()
    let today = try #require(widget.lists.first { $0.id == "today" })
    let inbox = try #require(widget.lists.first { $0.id == "inbox" })
    let row = try #require(inbox.tasks.first { $0.date != nil })
    #expect(today.tasks.contains(row))
    #expect(widget.lists.contains { $0.title == "Работа без времени" && $0.tasks.contains { !$0.timed } })
    #expect(try !store.complete(row.id, revision: row.revision.addingTimeInterval(-1)))
    #expect(try store.complete(row.id, revision: row.revision))
    #expect(try store.complete(row.id, revision: row.revision))
    widget = try store.read()
    #expect(widget.completions.count == 1)
    #expect(!widget.tasks(in: today).contains(row) && !widget.tasks(in: inbox).contains(row))
    #expect(state.item(row.id)?.isActiveTask == true)

    let reopened = AppState(demo: true, storageURL: url)
    let newBridge = WidgetBridge(store: store, state: reopened)
    bridge.stop()
    newBridge.start()
    defer { newBridge.stop() }
    #expect(reopened.item(row.id)?.completed == true)
    #expect(try store.read().completions.isEmpty)
    #expect(try !store.complete(row.id, revision: row.revision))
    #expect(AppState(demo: true, storageURL: url).item(row.id)?.completed == true)
}

@Test @MainActor func widgetCompletionUsesTheRegularDatabaseAndLeavesOtherTasksUntouched() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let databaseURL = directory.appendingPathComponent("database/takt.sqlite")
    let state = AppState(storageURL: databaseURL)
    let store = WidgetStore(directory: directory.appendingPathComponent("widget"))
    var task = Item(title: "Открытая задача")
    task.body = "Текст, который доступен только в Толке"
    let unrelated = Item(title: "Другая задача")
    state.add(task)
    state.add(unrelated)
    let bridge = WidgetBridge(store: store, state: state)
    bridge.start()
    defer { bridge.stop() }
    let row = try #require(try store.read().lists.first { $0.id == "inbox" }?.tasks.first { $0.id == task.id })
    let cache = try String(contentsOf: store.directory.appendingPathComponent("widget.json"), encoding: .utf8)
    #expect(!cache.contains(task.body))
    let permissions = try FileManager.default.attributesOfItem(atPath: store.directory.path)[.posixPermissions] as? Int
    #expect(permissions == 0o700)
    #expect(try store.complete(task.id, revision: row.revision))
    bridge.stop()
    let restarted = AppState(storageURL: databaseURL)
    let restartingBridge = WidgetBridge(store: store, state: restarted)
    restartingBridge.start()
    defer { restartingBridge.stop() }
    #expect(restarted.item(task.id)?.completed == true)
    #expect(restarted.item(unrelated.id)?.isActiveTask == true)
    #expect(restarted.item(task.id)?.body == task.body)
    #expect(try store.read().completions.isEmpty)
}

@Test @MainActor func widgetTagListsIncludeLegacyAndNestedTagsFromTheTasksArea() throws {
    let state = AppState(demo: true)
    let parent = Tag(name: "дела")
    let child = Tag(name: "проекты", parentID: parent.id)
    var task = Item(title: "Отправить черновик")
    task.tagIDs = [child.id]
    var legacy = Item(title: "Сверить #дела")
    legacy.body = "Текст старой задачи"
    let note = Item(title: "Мысль #дела", kind: .note)
    state.change { snapshot in
        snapshot.tags = [parent, child]
        snapshot.items = [task, legacy, note]
    }
    state.area = .notes
    let lists = state.widgetTaskLists()
    let tagged = try #require(lists.first { $0.id == "tag:\(parent.id)" })
    #expect(Set(tagged.tasks.map(\.id)) == Set([task.id, legacy.id]))
}
