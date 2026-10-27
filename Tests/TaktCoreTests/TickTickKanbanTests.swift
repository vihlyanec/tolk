import Foundation
import Testing
@testable import TaktCore

private let board = TickTickProject(["id": .string("board"), "name": .string("Доска"), "viewMode": .string("kanban")])
private func column(_ id: String, _ name: String, _ order: Int64 = 0) -> TickTickColumn {
    TickTickColumn(id: id, projectId: "board", name: name, sortOrder: order)
}
private func importBoard(_ columns: [TickTickColumn]?, into s: inout Snapshot, tasks: [TickTickTask] = []) {
    SyncEngine.ingest(projects: [board], tasks: tasks, inboxIDs: ["inbox"], columns: columns.map { ["board": $0] } ?? [:], into: &s)
}
private func connectedBoard() -> Snapshot {
    var s = Snapshot(); s.tickTick = TickTickSyncState(connectionID: UUID()); return s
}

@Test func kanbanImportsStableStagesOrderAndConfirmedColumnPlacement() throws {
    var s = connectedBoard()
    let task = TickTickTask(["id": .string("task"), "projectId": .string("board"), "title": .string("Задача"), "columnId": .string("a")])
    let stages = [column("b", "Готово", 20), column("a", "В работе", -10)]
    importBoard(stages, into: &s, tasks: [task])
    #expect(s.projects[0].kanban)
    #expect(s.projects[0].sections == ["Без раздела", "В работе", "Готово"])
    #expect(s.items[0].section == "В работе")
    let original = s
    importBoard(stages, into: &s, tasks: [task])
    #expect(s.projects == original.projects && s.items == original.items)
    #expect(s.tickTick?.projects == original.tickTick?.projects)
    #expect(s.tickTick?.outbox.isEmpty == true)
    s.projects[0].kanban = false
    importBoard(stages.reversed(), into: &s)
    #expect(!s.projects[0].kanban)
    s.items[0].title = "Правка названия"; SyncEngine.enqueueChanges(in: &s)
    let pending = try #require(s.tickTick?.outbox[s.items[0].id.uuidString])
    #expect(pending.task.raw["columnId"] == .string("a"))
    #expect(pending.task.raw["section"] == nil)
}

@Test func kanbanRemotePlacementUpdatesButLocalDragWinsAndUnknownIDsDoNotResetIt() throws {
    var s = connectedBoard()
    let stages = [column("a", "Первый"), column("b", "Второй", 1)]
    var task = TickTickTask(["id": .string("task"), "projectId": .string("board"), "title": .string("Задача"), "columnId": .string("a")])
    importBoard(stages, into: &s, tasks: [task])
    task.raw["columnId"] = .string("b")
    importBoard(stages, into: &s, tasks: [task])
    #expect(s.items[0].section == "Второй")
    task.raw["columnId"] = .string("missing")
    importBoard(stages, into: &s, tasks: [task])
    #expect(s.items[0].section == "Второй")
    #expect(s.tickTick?.unresolvedColumnTaskCount == 1)
    task.raw["columnId"] = nil
    importBoard(stages, into: &s, tasks: [task])
    #expect(s.items[0].section == "Второй")
    #expect(s.tickTick?.unresolvedColumnTaskCount == 0)
    s.projects[0].sections.append("Местный")
    s.items[0].section = "Местный"
    task.raw["columnId"] = .string("a")
    importBoard(stages, into: &s, tasks: [task])
    importBoard(stages, into: &s, tasks: [task])
    #expect(s.items[0].section == "Местный" && s.tickTick?.outbox.isEmpty == true)
}

@Test func kanbanRenameAdvancesPlacementBaselineAndRemoteProjectMoveDropsOldSection() throws {
    var s = connectedBoard()
    var task = TickTickTask(["id": .string("task"), "projectId": .string("board"), "columnId": .string("a")])
    importBoard([column("a", "Старое имя"), column("b", "Второй", 1)], into: &s, tasks: [task])
    importBoard([column("a", "Новое имя"), column("b", "Второй", 1)], into: &s, tasks: [task])
    #expect(s.items[0].section == "Новое имя")
    task.raw["columnId"] = .string("b")
    importBoard([column("a", "Новое имя"), column("b", "Второй", 1)], into: &s, tasks: [task])
    #expect(s.items[0].section == "Второй")
    let other = TickTickProject(["id": .string("other"), "name": .string("Другой проект")])
    task.raw["projectId"] = .string("other"); task.raw["columnId"] = nil
    SyncEngine.ingest(projects: [board, other], tasks: [task], inboxIDs: ["inbox"], into: &s)
    #expect(s.items[0].section == "Без раздела")
    #expect(s.items[0].projectID == s.projects.first { $0.name == "Другой проект" }?.id)
}

@Test func kanbanRenameKeepsLocalPlacementByRemoteIdentityAndHandlesDuplicateNames() throws {
    var s = connectedBoard()
    importBoard([column("a", "Этап"), column("b", "Этап", 1)], into: &s)
    #expect(s.projects[0].sections == ["Без раздела", "Этап", "Этап (TickTick 2)"])
    let id = s.projects[0].id
    var item = Item(title: "Местная задача", projectID: id); item.section = "Этап"
    var other = Item(title: "Другая задача", projectID: id); other.section = "Этап (TickTick 2)"
    s.items = [item, other]; s.projects[0].sections.append("Местный этап")
    importBoard([column("a", "Новое имя", 10), column("b", "Этап", -10)], into: &s)
    #expect(s.items[0].section == "Новое имя" && s.items[1].section == "Этап (TickTick 2)")
    #expect(s.projects[0].sections == ["Без раздела", "Местный этап", "Этап (TickTick 2)", "Новое имя"])
    let links = try #require(s.tickTick?.projects[id.uuidString]?.columns)
    #expect(links.map(\.remote.id) == ["b", "a"])
    #expect(links.first { $0.remote.id == "a" }?.localSection == "Новое имя")
    // Local drag remains local even when the remote column name changes.
    s.items[0].section = "Местный этап"
    importBoard([column("a", "Ещё имя"), column("b", "Этап", 1)], into: &s)
    #expect(s.items[0].section == "Местный этап")
}

@Test func kanbanDoesNotAdoptSameNamedLocalSectionsAndKeepsOccupiedRemovedStages() throws {
    var s = connectedBoard()
    var p = Project(name: "Местный проект"); p.sections += ["В работе"]
    s.projects = [p]
    s.tickTick?.projects[p.id.uuidString] = TickTickProjectLink(remote: board, local: p)
    importBoard([column("a", "В работе"), column("b", "Пустой", 1)], into: &s)
    #expect(s.projects[0].sections == ["Без раздела", "В работе", "В работе (TickTick 2)", "Пустой"])
    #expect(!s.projects[0].kanban)
    var item = Item(title: "Можно восстановить", projectID: p.id); item.section = "В работе (TickTick 2)"; item.deleted = true
    s.items = [item]
    importBoard(nil, into: &s)
    #expect(s.projects[0].sections.contains("Пустой"))
    importBoard([], into: &s)
    #expect(!s.projects[0].sections.contains("Пустой"))
    #expect(s.projects[0].sections.contains("В работе (TickTick 2)"))
    #expect(s.items[0] == item)
    #expect(s.tickTick?.projects[p.id.uuidString]?.columns == [])
}

@Test func kanbanRejectsInvalidColumnsAndKeepsUnknownMembershipLocal() throws {
    var s = connectedBoard()
    importBoard([column("a", "Этап")], into: &s)
    let before = s.projects
    let wrong = TickTickColumn(id: "b", projectId: "other", name: "Чужой", sortOrder: 0)
    importBoard([wrong], into: &s)
    #expect(s.projects == before)
    importBoard([column("a", "Один"), column("a", "Два")], into: &s)
    #expect(s.projects == before)
}

@Test func kanbanLinksPersistAndOldSyncStateStillDecodes() throws {
    var s = connectedBoard(); importBoard([column("a", "Этап", Int64.min)], into: &s)
    let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
    defer { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path.path + suffix) } }
    do { let db = try Database(url: path); try db.save(s) }
    let reopened = try Database(url: path).load()
    #expect(reopened == s)
    let encoder = JSONEncoder(), decoder = JSONDecoder()
    var old = s
    for key in old.tickTick?.projects.keys ?? Dictionary<String, TickTickProjectLink>().keys { old.tickTick?.projects[key]?.columns = nil }
    let decoded = try decoder.decode(Snapshot.self, from: encoder.encode(old)).validated()
    #expect(decoded.tickTick?.projects.values.first?.columns == nil)
    var migrated = decoded; importBoard([column("a", "Этап")], into: &migrated)
    #expect(migrated.projects[0].sections.contains("Этап"))
    #expect(migrated.projects[0].sections.contains("Этап (TickTick 2)"))
}
