import Foundation

public enum Hashtags {
    /// Whitespace separates commands. Markdown headings and URL fragments aren't tags.
    public static func names(in text: String, terminatedOnly: Bool = false) -> [String] {
        let pattern = #"(?<![\p{L}\p{N}_/])#(?:"([^"\n]+)"|([\p{L}\p{N}_-]+))"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        var clean = text
        for ignored in [#"(?s)```.*?(?:```|$)|~~~.*?(?:~~~|$)"#, #"`[^`]*`"#, #"https?://[^\s]+"#] {
            if let pattern = try? NSRegularExpression(pattern: ignored) {
                let matches = pattern.matches(in: clean, range: NSRange(clean.startIndex..., in: clean))
                for match in matches.reversed() { if let range = Range(match.range, in: clean) { clean.replaceSubrange(range, with: String(repeating: " ", count: match.range.length)) } }
            }
        }
        let source = clean as NSString
        return regex.matches(in: clean, range: NSRange(location: 0, length: source.length)).compactMap { match in
            if terminatedOnly && NSMaxRange(match.range) == source.length { return nil }
            let range = match.range(at: match.range(at: 1).location == NSNotFound ? 2 : 1)
            return source.substring(with: range)
        }
    }
    public static func searchTerms(in query: String) -> (text: String, tags: [String]) {
        guard let regex = try? NSRegularExpression(pattern: #"(?<!\S)#(?:"([^"\n]+)"|([\p{L}\p{N}_-]+))"#) else { return (query, []) }
        var plain = query
        let ns = query as NSString
        let matches = regex.matches(in: query, range: NSRange(location: 0, length: ns.length))
        let names = matches.map { ns.substring(with: $0.range(at: $0.range(at: 1).location == NSNotFound ? 2 : 1)) }
        for match in matches.reversed() { if let range = Range(match.range, in: plain) { plain.removeSubrange(range) } }
        return (plain.trimmingCharacters(in: .whitespacesAndNewlines), names)
    }
    public static func command(_ name: String) -> String { name.contains(where: \.isWhitespace) ? "#\"\(name)\"" : "#" + name }
}
