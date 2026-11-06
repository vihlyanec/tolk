import Foundation
import Testing
import TaktCore
@testable import Takt

@Test @MainActor func focusSessionRestoresAndStopClearsOnlyItsOwnFile() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("pomodoro.json")
    let task = Item(title: "Тестовый фокус")
    let first = PomodoroController(url: url, notificationsEnabled: false)
    let now = Date(timeIntervalSince1970: 1000)
    first.start(task, now: now)
    first.pause(now: now.addingTimeInterval(60))
    let restored = PomodoroController(url: url, notificationsEnabled: false)
    #expect(restored.session?.taskID == task.id)
    #expect(restored.session?.seconds(at: now.addingTimeInterval(9000)) == 1440)
    restored.stop()
    #expect(!FileManager.default.fileExists(atPath: url.path))
    #expect(PomodoroController(url: url, notificationsEnabled: false).session == nil)
}
@Test @MainActor func focusSwitchRequiresConfirmationAndNeverEditsTasks() throws {
    let state = AppState(demo: true)
    let first = Item(title: "Первая"), second = Item(title: "Вторая")
    let before = state.data
    state.startFocus(first)
    state.pomodoro.pause()
    state.startFocus(first)
    #expect(state.pomodoro.session?.deadline == nil)
    state.startFocus(second)
    #expect(state.pendingFocusTask?.id == second.id)
    #expect(state.pomodoro.session?.taskID == first.id)
    #expect(state.data == before)
    var completed = second; completed.completed = true
    state.startFocus(completed)
    #expect(state.pomodoro.session?.taskID == first.id)
}

@Test @MainActor func pausePromptsImmediatelyAndOptionalResumeNoteSurvivesRestart() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("pomodoro.json")
    let focus = PomodoroController(url: url, notificationsEnabled: false)
    let now = Date(timeIntervalSince1970: 1000)
    focus.start(Item(title: "Задача"), now: now)
    focus.pause(now: now.addingTimeInterval(60))
    #expect(focus.pausePrompt && focus.session?.deadline == nil)
    focus.saveResumeNote("  Начать с третьего пункта  ")
    let restored = PomodoroController(url: url, notificationsEnabled: false)
    #expect(restored.session?.resumeNote == "Начать с третьего пункта")
    #expect(restored.session?.seconds(at: now.addingTimeInterval(9000)) == 1440)
    restored.resume(now: now.addingTimeInterval(9000))
    restored.pause(now: now.addingTimeInterval(9010))
    restored.skipResumeNote()
    #expect(!restored.pausePrompt && restored.session?.deadline == nil)
    restored.saveResumeNote("")
    #expect(restored.session?.resumeNote == nil)
}

@Test @MainActor func sharedFocusPreservesAbsoluteDeadlinePauseNoteAndDoesNotEchoRemoteChanges() throws {
    let first = PomodoroController(url:nil,notificationsEnabled:false)
    let second = PomodoroController(url:nil,notificationsEnabled:false)
    let now = Date(timeIntervalSince1970:1794477600)
    let item = Item(title:"Общий фокус")
    var notifications = 0
    second.didChange = { _ in notifications += 1 }
    first.start(item,now:now)
    try second.acceptSharedSession(first.sharedSession)
    #expect(second.session?.deadline == now.addingTimeInterval(1500))
    #expect(second.session?.taskID == item.id && notifications == 0)
    first.pause(now:now.addingTimeInterval(123))
    first.saveResumeNote("Сверить второй пункт")
    try second.acceptSharedSession(first.sharedSession)
    #expect(second.session?.deadline == nil && second.session?.remaining == 1377)
    #expect(second.session?.resumeNote == "Сверить второй пункт" && notifications == 0)
    let before = second.sharedSession
    #expect(throws:(any Error).self) { try second.acceptSharedSession("{}") }
    #expect(second.sharedSession == before)
    try second.acceptSharedSession("")
    #expect(second.session == nil && notifications == 0)
}
