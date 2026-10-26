import AppKit
import TaktCore

/// Retains the bundled chime so completion never needs to load audio from disk.
final class CompletionFeedback {
    private let chime: NSSound? = Bundle.main.url(forResource: "Completion", withExtension: "wav")
        .flatMap { NSSound(contentsOf: $0, byReference: false) }

    func play(_ preferences: Preferences) {
        if preferences.completionHapticsEnabled ?? true {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        if preferences.completionSoundEnabled ?? true, let chime {
            chime.stop()
            chime.volume = 0.5
            chime.play()
        }
    }
}
