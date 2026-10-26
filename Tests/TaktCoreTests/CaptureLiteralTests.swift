import Foundation
import Testing
@testable import TaktCore

@Test(arguments: ["сегодня", "завтра", "через месяц", "через пол часа", "28.10", "в 16:30", "важно", "#работа", "/Работа", "на 45 минут"])
func rejectedCaptureCommandBecomesTitleText(_ phrase: String) throws {
    let project = Project(name: "Работа"), tag = Tag(name: "работа")
    let text = "Купить " + phrase
    let original = QuickParser.parse(text, projects: [project], tags: [tag])
    let command = try #require(QuickLiteralToken.tokenToLiteralize(parsed: original, selection: NSRange(location: (text as NSString).length, length: 0), backward: true))
    let literal = QuickLiteralToken(command)
    let parsed = QuickParser.parse(text, projects: [project], tags: [tag], literalRanges: [literal.range])
    #expect(parsed.title == text)
    #expect(parsed.tokens.isEmpty)
    #expect(parsed.schedule == .unscheduled)
    #expect(parsed.projectID == nil && parsed.tagIDs.isEmpty && parsed.priority == 0)
    #expect(!parsed.hasExplicitDuration)
}

@Test func spaceKeepsAcceptedOrRejectedRecognitionAndOnlyOneOccurrenceIsRejected() throws {
    let text = "Дела сегодня сегодня"
    let parsed = QuickParser.parse(text, projects: [], tags: [])
    let last = try #require(parsed.tokens.last)
    let literal = QuickLiteralToken(last)
    let withSpace = text + " "
    let rebased = QuickLiteralToken.rebased([literal], from: text, to: withSpace)
    let plain = QuickParser.parse(withSpace, projects: [], tags: [], literalRanges: QuickLiteralToken.ranges(rebased, in: withSpace))
    #expect(plain.tokens.count == 1 && plain.title == "Дела сегодня")
    #expect(QuickParser.parse(withSpace, projects: [], tags: []).tokens.count == 2)
    #expect(QuickLiteralToken.tokenToLiteralize(parsed: parsed, selection: NSRange(location: (withSpace as NSString).length, length: 0), backward: true) == nil)
}

@Test func literalTracksEmojiAndEditsBeforeItButWordEditsAllowRecognitionAgain() throws {
    let text = "📝 Дело сегодня"
    let parsed = QuickParser.parse(text, projects: [], tags: [])
    let literal = QuickLiteralToken(try #require(parsed.tokens.last))
    let prefixed = "⚡️ " + text
    let shifted = QuickLiteralToken.rebased([literal], from: text, to: prefixed)
    #expect(shifted.count == 1 && shifted[0].matches(prefixed))
    #expect(shifted[0].location == literal.location + ("⚡️ " as NSString).length)
    let expanded = prefixed + "шний"
    #expect(QuickLiteralToken.rebased(shifted, from: prefixed, to: expanded).isEmpty)
    let replaced = text.replacingOccurrences(of: "сегодня", with: "завтра")
    #expect(QuickLiteralToken.rebased([literal], from: text, to: replaced).isEmpty)
    #expect(!QuickParser.parse(replaced, projects: [], tags: []).tokens.isEmpty)
}

@Test func literalDraftRoundTripsAndEmptyOrReplacedDraftDoesNotReuseIt() throws {
    let text = "Дело завтра"
    let token = try #require(QuickParser.parse(text, projects: [], tags: []).tokens.last)
    var preferences = Preferences(); preferences.quickDraft = text; preferences.quickDraftLiterals = [QuickLiteralToken(token)]
    let restored = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences))
    #expect(QuickLiteralToken.ranges(restored.quickDraftLiterals ?? [], in: text) == [token.range])
    #expect(QuickLiteralToken.ranges(restored.quickDraftLiterals ?? [], in: "").isEmpty)
    #expect(QuickLiteralToken.ranges(restored.quickDraftLiterals ?? [], in: "Дело сегодня").isEmpty)
    #expect(QuickLiteralToken.rebased(restored.quickDraftLiterals ?? [], from: text, to: "").isEmpty)
}
