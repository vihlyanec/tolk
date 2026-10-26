import Foundation
import TaktCore

enum CaptureSubmitAction { case applySuggestion, finishToken, create, stay }
enum CaptureBehavior {
    static func submitAction(text: String, parsed: ParsedTask, suggestionCount: Int) -> CaptureSubmitAction {
        if suggestionCount > 0 { return .applySuggestion }
        let end = (text as NSString).length
        if parsed.tokens.contains(where: { NSMaxRange($0.range) == end && [.tag, .project, .priority].contains($0.kind) }) { return .finishToken }
        let token = text.split(separator: " ", omittingEmptySubsequences: false).last.map(String.init) ?? ""
        if ["!", "/", "#"].contains(token) { return .stay }
        return .create
    }
}
