import Foundation
import Testing
import TaktCore
@testable import Takt

@Test @MainActor func focusCueOnlyPlaysForExplicitFocusStarts() throws {
    let focus = PomodoroController(url: nil, notificationsEnabled: false)
    var cues = 0
    focus.playStartSound = { cues += 1 }
    let now = Date(timeIntervalSince1970: 1000)
    focus.start(Item(title: "Звуковой тест"), now: now)
    #expect(cues == 1)
    focus.resume(now: now)
    focus.next(now: now)
    focus.pause(now: now.addingTimeInterval(60))
    focus.saveResumeNote("Следующий шаг")
    #expect(cues == 1)
    focus.resume(now: now.addingTimeInterval(120))
    #expect(cues == 2)
    // Remote sync and restoration must not replay a local action cue.
    try focus.acceptSharedSession(focus.sharedSession)
    #expect(cues == 2)
    focus.next(now: now.addingTimeInterval(1560))
    #expect(focus.session?.phase == .shortBreak && cues == 2)
    focus.pause(now: now.addingTimeInterval(1570))
    focus.resume(now: now.addingTimeInterval(1580))
    #expect(cues == 2)
    focus.next(now: now.addingTimeInterval(1870))
    #expect(focus.session?.phase == .focus && cues == 3)
    focus.stop()
    #expect(cues == 3)
}

@Test @MainActor func notificationAudioFilesAreDistinctPlayablePCM() throws {
    #expect(NotificationAudio.phaseEnd(.focus) == .focusEnd)
    #expect(NotificationAudio.phaseEnd(.shortBreak) == .focusStart)
    #expect(NotificationAudio.phaseEnd(.longBreak) == .focusStart)
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources")
    var files = Set<Data>()
    for sound in NotificationAudio.allCases {
        let data = try Data(contentsOf: root.appendingPathComponent(sound.fileName))
        #expect(String(data: data.prefix(4), encoding: .ascii) == "RIFF")
        #expect(String(data: data[8..<12], encoding: .ascii) == "WAVE")
        #expect(data.count > 44100 && data.count < 44100 * 2 * 3)
        files.insert(data)
    }
    #expect(files.count == 3)
}
