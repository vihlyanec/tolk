import Foundation
import AppKit
import SwiftUI
import Testing
import TaktCore
@testable import Takt

@Test @MainActor func quickCaptureNativeEditorDoesNotRunSaveServicesOnTyping() throws {
    let state = AppState(demo: true)
    var notifications = 0; state.didSave = { notifications += 1 }
    let root = NSHostingView(rootView: QuickCaptureView(state: state, dismiss: {}).frame(width: 640, height: 62))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 62), styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = root; root.frame = window.contentLayoutRect
    defer { state.clearQuickDraft(); window.contentView = nil; window.close() }
    root.layoutSubtreeIfNeeded()
    func editor(in view: NSView) -> CaptureTextView? {
        if let found = view as? CaptureTextView { return found }
        for child in view.subviews { if let found = editor(in: child) { return found } }
        return nil
    }
    let input = try #require(editor(in: root))
    for character in "Привет" { input.insertText(String(character), replacementRange: input.selectedRange()) }
    root.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    #expect(input.string == "Привет" && notifications == 0)
    state.flushQuickDraft()
    #expect(state.data.preferences.quickDraft == "Привет")
}

@Test @MainActor func quickDraftKeystrokesDoNotPersistOrRefreshServicesAndFlushLatestTogether() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("test.sqlite")
    let state = AppState(storageURL: url)
    let db = try Database(url: url)
    var notifications = 0; state.didSave = { notifications += 1 }
    let initial = state.data
    for text in ["П", "Пр", "При", "Прив", "Приве", "Привет"] {
        state.queueQuickDraft(QuickCaptureDraft(text: text, literals: [], body: "Описание", descriptionExpanded: true))
    }
    #expect(state.data == initial && notifications == 0)
    #expect(try db.load() == initial)
    state.flushQuickDraft()
    let saved = try db.load().preferences
    #expect(saved.quickDraft == "Привет" && saved.quickDraftBody == "Описание" && saved.quickDraftDescriptionExpanded == true)
    #expect(notifications == 0 && state.data.items.isEmpty)
    state.queueQuickDraft(QuickCaptureDraft(text: "Не успеть записать"))
    state.clearQuickDraft(); state.flushQuickDraft()
    #expect(try db.load().preferences.quickDraft.isEmpty)
    #expect(state.data.preferences.quickDraftBody == nil && notifications == 0)
}

@Test @MainActor func quickDraftDebounceSavesAfterPauseWithoutRecreatingDiscardedOrSubmittedText() async throws {
    let state = AppState(demo: true)
    var notifications = 0; state.didSave = { notifications += 1 }
    state.queueQuickDraft(QuickCaptureDraft(text: "Первое"))
    state.queueQuickDraft(QuickCaptureDraft(text: "Последнее", body: "Текст"))
    // Other MainActor UI tests may run before the debounce task first starts.
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while state.data.preferences.quickDraft != "Последнее", ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(25))
    }
    #expect(state.data.preferences.quickDraft == "Последнее" && notifications == 0)
    state.queueQuickDraft(QuickCaptureDraft(text: "Уже отправлено"))
    let before = state.data.items.count
    let id = try #require(state.capture(QuickParser.parse("Задача", projects: [], tags: [])))
    state.clearQuickDraft()
    try await Task.sleep(for: .milliseconds(650))
    #expect(state.data.preferences.quickDraft.isEmpty && notifications == 1)
    #expect(state.data.items.count == before + 1 && state.item(id) != nil)
    state.undo()
    #expect(state.data.items.count == before && notifications == 2)
    #expect(state.data.preferences.quickDraft.isEmpty)
    state.queueQuickDraft(QuickCaptureDraft(text: "Отмена")); state.clearQuickDraft()
    state.queueQuickDraft(QuickCaptureDraft(text: "Новое окно")); state.flushQuickDraft()
    try await Task.sleep(for: .milliseconds(650))
    #expect(state.data.preferences.quickDraft == "Новое окно")
}

@Test @MainActor func quickDraftDoesNotChangeSyncOutboxOrOverwriteIncomingData() throws {
    let state = AppState(demo: true)
    state.change(undo: false) { s in
        s.tickTick = TickTickSyncState(connectionID: UUID())
        SyncEngine.ingest(projects: [], tasks: [TickTickTask(["id": .string("remote"), "projectId": .string("inbox"), "title": .string("Из TickTick")])], inboxIDs: ["inbox"], into: &s)
    }
    let outbox = state.data.tickTick?.outbox
    state.queueQuickDraft(QuickCaptureDraft(text: "Черновик"))
    state.change(undo: false) { $0.items.append(Item(title: "Пришло из синхронизации")) }
    state.flushQuickDraft()
    #expect(state.data.items.contains { $0.title == "Пришло из синхронизации" })
    #expect(state.data.tickTick?.outbox == outbox)
    var restored = Snapshot(); restored.preferences.quickDraft = "Восстановленное"
    state.queueQuickDraft(QuickCaptureDraft(text: "Старый черновик"))
    state.restore(restored); state.flushQuickDraft()
    #expect(state.data.preferences.quickDraft == "Восстановленное")
}

@Test @MainActor func quickDraftTypingProfileUsesOnlySyntheticTemporaryDatabase() throws {
    // Opt-in timing, without wall-clock thresholds that would make CI flaky.
    guard ProcessInfo.processInfo.environment["TOLK_PROFILE_CAPTURE"] == "1" else { return }
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("profile.sqlite")
    var snapshot = Snapshot(); snapshot.tickTick = TickTickSyncState(connectionID: UUID())
    for i in 0..<95 {
        var item = Item(title: "Тестовая задача \(i)"); item.body = String(repeating: "Описание ", count: 80)
        snapshot.items.append(item)
    }
    try Database(url: url).save(snapshot)
    let state = AppState(storageURL: url)
    var services = 0; state.didSave = { services += 1 }
    // Warm the daily-backup path before comparing per-keystroke work.
    state.change(undo: false) { $0.preferences.quickDraft = "Разогрев" }
    services = 0
    let clock = ContinuousClock(), oldStart = clock.now
    for i in 1...60 { state.change(undo: false) { $0.preferences.quickDraft = String(repeating: "П", count: i) } }
    let oldTime = oldStart.duration(to: clock.now), oldServices = services
    services = 0
    let newStart = clock.now
    for i in 1...60 { state.queueQuickDraft(QuickCaptureDraft(text: String(repeating: "Р", count: i))) }
    let newTime = newStart.duration(to: clock.now)
    #expect(services == 0 && oldServices == 60)
    state.flushQuickDraft()
    #expect(try Database(url: url).load().preferences.quickDraft == String(repeating: "Р", count: 60))
    print("Synthetic Ctrl-Q profile (60 updates, 95 tasks): old synchronous path=\(oldTime), queued typing path=\(newTime), service callbacks=\(oldServices)→\(services)")
}
