import Foundation
import AppKit
import SwiftUI
import Testing
import TaktCore
@testable import Takt

@Test @MainActor func kanbanStagesCanBeCreatedOnEmptyBoardAndUndoneWithoutExportingThem() throws {
    let state = AppState(demo: true)
    let remote = TickTickProject(["id": .string("board"), "name": .string("Пустая доска"), "viewMode": .string("kanban")])
    state.change(undo: false) { snapshot in
        snapshot.tickTick = TickTickSyncState(connectionID: UUID())
        SyncEngine.ingest(projects: [remote], tasks: [], inboxIDs: ["inbox"], into: &snapshot)
    }
    let project = try #require(state.data.projects.first { $0.name == remote.name })
    state.scope = .project(project.id); state.inspectorVisible = false
    #expect(state.visibleItems.isEmpty)
    #expect(state.createSection("  Проверка  ", in: project.id) == nil)
    #expect(state.project?.sections == ["Без раздела", "Проверка"])
    #expect(state.createSection("проверка", in: project.id) != nil)
    #expect(state.createSection(" \n ", in: project.id) != nil)
    #expect(state.data.tickTick?.outbox.isEmpty == true)
    state.undo()
    #expect(state.project?.sections == ["Без раздела"])
    state.redo()
    state.change(undo: false) { SyncEngine.ingest(projects: [remote], tasks: [], inboxIDs: ["inbox"], columns: ["board": []], into: &$0) }
    #expect(state.project?.sections.contains("Проверка") == true)
    if let directory = ProcessInfo.processInfo.environment["TOLK_STAGE_QA_OUTPUT"] {
        for width in [1080, 1440] {
            let root = NSHostingView(rootView: MainView(state: state).frame(width: CGFloat(width), height: 760).environment(\.colorScheme, .dark))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: CGFloat(width), height: 760), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = root; root.frame = window.contentLayoutRect
            root.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.15))
            let bitmap = try #require(root.bitmapImageRepForCachingDisplay(in: root.bounds))
            root.cacheDisplay(in: root.bounds, to: bitmap)
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: directory).appendingPathComponent("kanban-empty-\(width).png"))
            window.contentView = nil; window.close()
        }
    }
}
