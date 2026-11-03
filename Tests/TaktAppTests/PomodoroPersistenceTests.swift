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
