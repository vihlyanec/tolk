import AppKit
import Foundation
import Testing
import TaktCore
@testable import Takt

@Test @MainActor func globalPausePanelStaysNonactivatingAndKeepsItsDraftAcrossUpdates() throws {
    let state = AppState(demo: true)
    let popup = FocusPauseController(state: state)
    state.pomodoro.didUpdate = { [weak popup] in popup?.sync() }
    defer { state.pomodoro.stop(); popup.panel?.orderOut(nil) }
    state.pomodoro.start(Item(title: "Вымышленный глобальный фокус"))
    #expect(popup.panel == nil)
    state.pomodoro.pause()
    let panel = try #require(popup.panel)
    #expect(panel.isVisible && panel.styleMask.contains(.nonactivatingPanel))
    #expect(panel.styleMask.contains(.titled) && !panel.canBecomeMain)
    #expect(panel.level == .floating && !panel.hidesOnDeactivate)
    #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
    let host = try #require(panel.contentView)
    state.pomodoro.pauseDraft = "Начать со второго пункта"
    popup.sync(); popup.sync()
    #expect(panel.contentView === host)
    #expect(state.pomodoro.pauseDraft == "Начать со второго пункта")
    let remaining = state.pomodoro.session?.remaining
    state.pomodoro.saveResumeNote(state.pomodoro.pauseDraft)
    #expect(!panel.isVisible && !state.pomodoro.pausePrompt)
    #expect(state.pomodoro.session?.remaining == remaining)
    #expect(state.pomodoro.session?.deadline == nil)
    state.pomodoro.resume()
    #expect(!panel.isVisible && state.pomodoro.session?.resumeNote == "Начать со второго пункта")
    state.pomodoro.pause()
    #expect(panel.isVisible && state.pomodoro.pauseDraft == "Начать со второго пункта")
    state.pomodoro.pauseDraft = "Не сохранять этот черновик"
    panel.cancelOperation(nil)
    #expect(!panel.isVisible && state.pomodoro.session?.resumeNote == "Начать со второго пункта")
    state.pomodoro.requestResumeNote()
    #expect(panel.isVisible)
    state.pomodoro.start(Item(title: "Другой сеанс"))
    #expect(!panel.isVisible && !state.pomodoro.pausePrompt)
}

@Test @MainActor func globalPausePanelClosesWhenSharedSessionStopsOrResumes() throws {
    let state = AppState(demo: true)
    let popup = FocusPauseController(state: state)
    state.pomodoro.didUpdate = { [weak popup] in popup?.sync() }
    defer { state.pomodoro.stop(); popup.panel?.orderOut(nil) }
    state.pomodoro.start(Item(title: "Общий вымышленный фокус"))
    let running = state.pomodoro.sharedSession
    state.pomodoro.pause()
    #expect(popup.panel?.isVisible == true)
    try state.pomodoro.acceptSharedSession(running)
    #expect(popup.panel?.isVisible == false && !state.pomodoro.pausePrompt)
    state.pomodoro.pause()
    try state.pomodoro.acceptSharedSession("")
    #expect(popup.panel?.isVisible == false && state.pomodoro.session == nil)
}

@Test @MainActor func globalPausePopupIsCenteredAndFitsTheCurrentScreen() {
    for screen in [NSRect(x: 0, y: 25, width: 1440, height: 850), NSRect(x: -1920, y: 0, width: 1920, height: 1080), NSRect(x: 0, y: 0, width: 320, height: 240)] {
        let frame = FocusPauseGeometry.frame(in: screen, size: NSSize(width: 430, height: 340))
        #expect(frame.midX == screen.midX && frame.midY == screen.midY)
        #expect(screen.contains(frame))
    }
}

@Test @MainActor func pauseObserversReceiveThePromptAndSavingFailuresDoNotDismissIt() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = folder.appendingPathComponent("store")
    let url = store.appendingPathComponent("pomodoro.json")
    let focus = PomodoroController(url: url, notificationsEnabled: false)
    var promptStates = [Bool]()
    focus.didUpdate = { [weak focus] in promptStates.append(focus?.pausePrompt ?? false) }
    focus.start(Item(title: "Ошибка записи в тестовую папку"))
    focus.pause()
    #expect(promptStates.last == true)
    focus.saveResumeNote("Прежний сохранённый шаг")
    let committed = focus.sharedSession
    focus.requestResumeNote()
    try FileManager.default.removeItem(at: store)
    try Data().write(to: store)
    var published = [String]()
    focus.didChange = { published.append($0) }
    focus.pauseDraft = "Сохранить следующий шаг"
    focus.saveResumeNote(focus.pauseDraft)
    #expect(focus.pausePrompt && focus.error != nil)
    #expect(focus.pauseDraft == "Сохранить следующий шаг")
    #expect(focus.session?.resumeNote == "Прежний сохранённый шаг")
    #expect(focus.sharedSession == committed && published.isEmpty)
    focus.skipResumeNote()
    #expect(promptStates.last == false)
    #expect(focus.sharedSession == committed)
    focus.requestResumeNote()
    #expect(focus.pauseDraft == "Прежний сохранённый шаг")
    focus.pauseDraft = "Повторно сохранённый шаг"
    try FileManager.default.removeItem(at: store)
    focus.saveResumeNote(focus.pauseDraft)
    #expect(!focus.pausePrompt && focus.error == nil)
    #expect(focus.session?.resumeNote == "Повторно сохранённый шаг")
    #expect(published == [focus.sharedSession])
    let restored = PomodoroController(url: url, notificationsEnabled: false)
    #expect(restored.session?.resumeNote == "Повторно сохранённый шаг")
}

@Test @MainActor func pausedSideTimerKeepsResumeNoteVisibleUntilWorkResumes() async throws {
    let state = AppState(demo: true)
    let edge = FocusEdgeController(state: state)
    state.pomodoro.didUpdate = { [weak edge] in edge?.sync() }
    defer { state.pomodoro.stop(); edge.panel?.orderOut(nil) }
    state.pomodoro.start(Item(title: "Заметка у таймера"))
    state.pomodoro.pause()
    state.pomodoro.saveResumeNote("Открыть второй раздел черновика")
    let panel = try #require(edge.panel)
    #expect(edge.presentation.expanded && panel.frame.size == FocusEdgeGeometry.expandedWithNote)
    edge.hover(false)
    try await Task.sleep(for: .milliseconds(280))
    #expect(edge.presentation.expanded)
    state.pomodoro.resume()
    #expect(!edge.presentation.expanded && panel.frame.size == FocusEdgeGeometry.compact)
    edge.hover(true)
    #expect(panel.frame.size == FocusEdgeGeometry.expandedWithNote)
    #expect(state.pomodoro.session?.resumeNote == "Открыть второй раздел черновика")
}
