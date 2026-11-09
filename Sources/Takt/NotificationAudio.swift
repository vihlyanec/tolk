import AppKit
import UserNotifications
import TaktCore

enum NotificationAudio: String, CaseIterable {
    case focusStart = "FocusStart"
    case focusEnd = "FocusEnd"
    case taskReminder = "TaskReminder"

    var fileName: String { rawValue + ".wav" }
    var notificationSound: UNNotificationSound {
        UNNotificationSound(named: UNNotificationSoundName(fileName))
    }

    static func phaseEnd(_ phase: Pomodoro.Phase) -> NotificationAudio {
        phase == .focus ? .focusEnd : .focusStart
    }
}

/// A local action cue; deadlines use system notifications so they also sound
/// when the app is in the background. Retaining audio avoids overlapping starts.
final class FocusStartFeedback {
    private let sound = Bundle.main.url(forResource: "FocusStart", withExtension: "wav")
        .flatMap { NSSound(contentsOf: $0, byReference: false) }

    func play() {
        sound?.stop()
        sound?.play()
    }
}
