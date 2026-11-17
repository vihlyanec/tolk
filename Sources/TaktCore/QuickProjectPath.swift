import Foundation

/// Syntax only: persisted projects remain UUIDs and sections remain strings.
public enum QuickProjectPath {
    public struct Match: Sendable {
        public let range: NSRange
        public let project: Project
        public let section: String?
        public let missingSection: Bool
    }

    public static func command(_ project: String, section: String? = nil) -> String {
        "/" + component(project) + (section.map { "/" + component($0) } ?? "")
    }

    private static func component(_ name: String) -> String {
        guard name.contains(where: { "/\"\\\n\r".contains($0) }) else { return name }
        return quoted(name)
    }

    private static func quoted(_ name: String) -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = .withoutEscapingSlashes
        return String(decoding: try! encoder.encode(name), as: UTF8.self)
    }

    private static func pattern(_ name: String) -> String {
        let quoted = quoted(name)
        let variants = name.contains(where: { "/\"\\\n\r".contains($0) }) ? [quoted] : [quoted, name]
        return "(?:" + variants.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|") + ")"
    }

    private static func prefix(_ pattern: String, in text: String) -> NSRange? {
        try? NSRegularExpression(pattern: "^(?:" + pattern + ")", options: [.caseInsensitive])
            .firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length))?.range
    }

    public static func matches(in text: String, projects: [Project]) -> [Match] {
        let source = text as NSString
        let starts = try! NSRegularExpression(pattern: #"(?<!\S)/"#)
        var result: [Match] = []
        for start in starts.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            guard !result.contains(where: { NSLocationInRange(start.range.location, $0.range) }) else { continue }
            let tail = source.substring(from: NSMaxRange(start.range))
            let candidates = projects.filter { $0.kind == .task && !$0.archived }.compactMap { project -> (Project, NSRange)? in
                guard let range = prefix(pattern(project.name) + #"(?=/|\s|$)"#, in: tail) else { return nil }
                return (project, range)
            }
            guard let (project, head) = candidates.max(by: { $0.1.length < $1.1.length }) else { continue }
            var length = 1 + head.length
            var section: String?, missing = false
            let remainder = (tail as NSString).substring(from: head.length)
            if remainder.hasPrefix("/") {
                let sectionText = String(remainder.dropFirst())
                let sections = project.sections.compactMap { name -> (String, NSRange)? in
                    guard let range = prefix(pattern(name) + #"(?=\s|$)"#, in: sectionText) else { return nil }
                    return (name, range)
                }
                if let found = sections.max(by: { $0.1.length < $1.1.length }) {
                    section = found.0; length += 1 + found.1.length
                } else {
                    // An unknown unquoted component ends at whitespace, just like other commands.
                    let unknown = prefix(#"(?:"(?:\\.|[^"\\])*"|[^\s]+)?"#, in: sectionText)
                    length += 1 + (unknown?.length ?? 0); missing = true
                }
            }
            result.append(Match(range: NSRange(location: start.range.location, length: length), project: project, section: section, missingSection: missing))
        }
        return result
    }

    /// The whole unfinished path, including spaces; a slash inside a URL is not a command.
    public static func completionRange(in text: String) -> NSRange? {
        guard text.last?.isWhitespace != true else { return nil }
        var start: Int?, quoted = false, escaped = false
        var offset = 0, previousWhitespace = true
        for character in text {
            if character == "/" && !quoted && previousWhitespace { start = offset }
            if start != nil {
                if escaped { escaped = false }
                else if character == "\\" { escaped = true }
                else if character == "\"" { quoted.toggle() }
            }
            previousWhitespace = character.isWhitespace; offset += String(character).utf16.count
        }
        return start.map { NSRange(location: $0, length: (text as NSString).length - $0) }

    }

    public struct Completion: Sendable {
        public let project: Project
        public let section: String?
        public let command: String
    }
    public static func completions(for query: String, projects: [Project]) -> [Completion] {
        let active = projects.filter { $0.kind == .task && !$0.archived }
        // Resolve the project before suggesting stages, including the legacy quoted spelling.
        let heads = active.compactMap { project -> (Project, NSRange)? in
            guard let range = prefix("/" + pattern(project.name) + "/", in: query) else { return nil }
            return (project, range)
        }
        if let (project, range) = heads.max(by: { $0.1.length < $1.1.length }) {
            let tail = (query as NSString).substring(from: range.length).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            return project.sections.filter { tail.isEmpty || $0.localizedCaseInsensitiveContains(tail) }.map {
                Completion(project: project, section: $0, command: command(project.name, section: $0))
            }
        }
        let name = String(query.dropFirst()).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        return active.filter { name.isEmpty || $0.name.localizedCaseInsensitiveContains(name) }.map {
            Completion(project: $0, section: nil, command: command($0.name))
        }
    }
}
