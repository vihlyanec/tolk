import Foundation
import Testing
@testable import TaktCore

@Test func pomodoroUsesDeadlineAcrossSleepAndRestart() throws {
    let now = Date(timeIntervalSince1970: 1000)
    let value = Pomodoro(taskID: UUID(), title: "Фокус", now: now)
    let restored = try JSONDecoder().decode(Pomodoro.self, from: JSONEncoder().encode(value))
    #expect(restored.seconds(at: now.addingTimeInterval(1499.1)) == 1)
    #expect(restored.seconds(at: now.addingTimeInterval(9000)) == 0)
    #expect(restored.phase == .focus && restored.completed == 0)
}
@Test func pomodoroPauseResumeDoesNotSpendPausedTime() {
    let now = Date(timeIntervalSince1970: 1000)
    var value = Pomodoro(taskID: UUID(), title: "Фокус", now: now)
    value.pause(at: now.addingTimeInterval(100))
    #expect(value.seconds(at: now.addingTimeInterval(5000)) == 1400)
    value.resume(at: now.addingTimeInterval(5000))
    value.resume(at: now.addingTimeInterval(5100)) // repeated resume never extends a running timer
    #expect(value.seconds(at: now.addingTimeInterval(5100)) == 1300)
}
@Test func pomodoroWaitsForNextAndUsesLongFourthBreak() {
    var now = Date(timeIntervalSince1970: 1000)
    var value = Pomodoro(taskID: UUID(), title: "Фокус", now: now)
    value.next(at: now)
    #expect(value.completed == 0)
    for round in 1...4 {
        now = value.deadline!
        value.next(at: now)
        #expect(value.completed == round)
        #expect(value.phase == (round == 4 ? .longBreak : .shortBreak))
        #expect(value.seconds(at: now) == (round == 4 ? 900 : 300))
        value.next(at: now) // cannot skip an unfinished break
        #expect(value.completed == round)
        now = value.deadline!
        value.next(at: now)
        #expect(value.phase == .focus && value.seconds(at: now) == 1500)
    }
}
