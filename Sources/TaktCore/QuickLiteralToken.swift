import Foundation

/// A deliberate opt-out for one occurrence, rather than for every equal word in a draft.
public struct QuickLiteralToken: Codable, Equatable, Sendable {
    public var location: Int
    public var length: Int
    public var value: String
    public var range: NSRange { NSRange(location: location, length: length) }
    public init(_ token: QuickToken) { location = token.range.location; length = token.range.length; value = token.value }
    public func matches(_ text: String) -> Bool {
        guard location >= 0, length > 0, location <= (text as NSString).length,
              length <= (text as NSString).length - location, let r = Range(range, in: text) else { return false }
        return String(text[r]) == value
    }
    public static func ranges(_ tokens: [Self], in text: String) -> [NSRange] { tokens.filter { $0.matches(text) }.map(\.range) }
    public static func suppressesSuggestions(_ tokens: [Self], in text: String) -> Bool {
        tokens.contains { $0.matches(text) && NSMaxRange($0.range) == (text as NSString).length }
    }
    public static func rebased(_ tokens: [Self], from old: String, to new: String) -> [Self] {
        guard old != new else { return tokens.filter { $0.matches(new) } }
        let before = Array(old.utf16), after = Array(new.utf16)
        var start = 0, suffix = 0
        while start < min(before.count, after.count), before[start] == after[start] { start += 1 }
        while suffix < min(before.count - start, after.count - start), before[before.count - suffix - 1] == after[after.count - suffix - 1] { suffix += 1 }
        let oldEnd = before.count - suffix, newEnd = after.count - suffix, delta = after.count - before.count
        return tokens.compactMap { original in
            guard original.matches(old) else { return nil }
            var token = original
            let end = NSMaxRange(token.range)
            if oldEnd <= token.location { token.location += delta }
            else if start >= end {
                // A space commits a literal token. Continuing the word allows recognition again.
                if start == end && oldEnd == start && newEnd > start,
                   let r = Range(NSRange(location: start, length: newEnd - start), in: new),
                   new[r].first?.isWhitespace != true { return nil }
            } else { return nil }
            return token.matches(new) ? token : nil
        }
    }
    public static func tokenToLiteralize(parsed: ParsedTask, selection: NSRange, backward: Bool) -> QuickToken? {
        guard selection.length == 0, selection.location != NSNotFound else { return nil }
        return parsed.tokens.first { backward ? NSMaxRange($0.range) == selection.location : $0.range.location == selection.location }
    }
}
