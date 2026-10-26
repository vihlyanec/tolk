import SwiftUI
import WebKit

/// A small, escaped Markdown renderer; raw HTML never executes in a note.
nonisolated enum MarkdownHTML {
    static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
    static func safeURL(_ value: String) -> URL? {
        guard let url = URL(string: value), ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }
    static func inline(_ source: String) -> String {
        let pattern = #"`([^`]+)`|!?\[([^\]]+)\]\(([^\s)]+)\)|https?://[^\s<>]+|\*\*(.+?)\*\*|__(.+?)__|~~(.+?)~~|\*([^*]+)\*|_([^_]+)_"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return escape(source) }
        let ns = source as NSString
        var html = "", end = 0
        for match in regex.matches(in: source, range: NSRange(location: 0, length: ns.length)) {
            html += escape(ns.substring(with: NSRange(location: end, length: match.range.location - end)))
            func value(_ n: Int) -> String? { match.range(at: n).location == NSNotFound ? nil : ns.substring(with: match.range(at: n)) }
            let raw = ns.substring(with: match.range)
            if let code = value(1) { html += "<code>\(escape(code))</code>" }
            else if let label = value(2), let target = value(3), let url = safeURL(target) {
                if raw.hasPrefix("!") { html += "<a href=\"\(escape(url.absoluteString))\"><img alt=\"\(escape(label))\" src=\"\(escape(url.absoluteString))\"></a>" }
                else { html += "<a href=\"\(escape(url.absoluteString))\">\(inline(label))</a>" }
            } else if raw.hasPrefix("http"), let url = safeURL(raw.trimmingCharacters(in: CharacterSet(charactersIn: ".,;!?)"))) {
                let suffix = String(raw.dropFirst(url.absoluteString.count))
                html += "<a href=\"\(escape(url.absoluteString))\">\(escape(url.absoluteString))</a>" + escape(suffix)
            } else if let bold = value(4) ?? value(5) { html += "<strong>\(inline(bold))</strong>" }
            else if let strike = value(6) { html += "<del>\(inline(strike))</del>" }
            else if let italic = value(7) ?? value(8) { html += "<em>\(inline(italic))</em>" }
            else { html += escape(raw) }
            end = NSMaxRange(match.range)
        }
        return html + escape(ns.substring(from: end))
    }
    static func body(_ markdown: String) -> String {
        let lines = markdown.components(separatedBy: .newlines)
        var output = "", i = 0
        func cells(_ line: String) -> [String] {
            var parts = line.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.first == "" { parts.removeFirst() }; if parts.last == "" { parts.removeLast() }
            return parts
        }
        while i < lines.count {
            let line = lines[i], trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { i += 1; continue }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                let fence = String(trimmed.prefix(3)); var code: [String] = []; i += 1
                while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(fence) { code.append(lines[i]); i += 1 }
                output += "<pre><code>\(escape(code.joined(separator: "\n")))</code></pre>"; i += 1; continue
            }
            if i + 1 < lines.count && line.contains("|") {
                let separators = cells(lines[i + 1])
                if !separators.isEmpty && separators.allSatisfy({ $0.range(of: #"^:?-{3,}:?$"#, options: .regularExpression) != nil }) {
                    output += "<div class='table-wrap'><table><thead><tr>" + cells(line).map { "<th>\(inline($0))</th>" }.joined() + "</tr></thead><tbody>"; i += 2
                    while i < lines.count && lines[i].contains("|") && !lines[i].isEmpty {
                        output += "<tr>" + cells(lines[i]).map { "<td>\(inline($0))</td>" }.joined() + "</tr>"; i += 1
                    }
                    output += "</tbody></table></div>"; continue
                }
            }
            if let heading = trimmed.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
                let level = trimmed[heading].filter { $0 == "#" }.count
                output += "<h\(level)>\(inline(String(trimmed[heading.upperBound...])))</h\(level)>"
            } else if ["---", "***", "___"].contains(trimmed) { output += "<hr>" }
            else if trimmed.hasPrefix(">") { output += "<blockquote>\(inline(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)))</blockquote>" }
            else if let range = trimmed.range(of: #"^[-*+]\s+\[([ xX])\]\s*"#, options: .regularExpression) {
                let checked = trimmed[range].lowercased().contains("[x]")
                output += "<div class='task'>\(checked ? "☑" : "☐") <span\(checked ? " class='done'" : "")>\(inline(String(trimmed[range.upperBound...])))</span></div>"
            } else if let range = trimmed.range(of: #"^([-*+]|\d+[.)])\s+"#, options: .regularExpression) {
                let marker = String(trimmed[range]).trimmingCharacters(in: .whitespaces)
                let indent = min(6, line.prefix(while: { $0 == " " }).count / 2)
                output += "<div class='list' style='margin-left:\(indent * 16)px'><span class='marker'>\(marker.first?.isNumber == true ? escape(marker) : "•")</span><span>\(inline(String(trimmed[range.upperBound...])))</span></div>"
            } else { output += "<p>\(inline(line))</p>" }
            i += 1
        }
        return output
    }
    static func document(_ markdown: String, dark: Bool) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src https: http:; script-src 'none'"><style>
        :root { color-scheme: \(dark ? "dark" : "light"); } *{box-sizing:border-box} body{margin:0;padding:4px 6px 24px;font:14px/1.65 -apple-system,BlinkMacSystemFont,sans-serif;color:\(dark ? "#e5e5e7" : "#232326");overflow-wrap:anywhere;background:transparent} h1,h2,h3,h4,h5,h6{line-height:1.25;margin:20px 0 10px} h1{font-size:28px} h2{font-size:23px} h3{font-size:19px} p{margin:0 0 8px;white-space:pre-wrap} a{color:\(dark ? "#82a8ff" : "#295cd1");text-decoration:underline;text-underline-offset:3px} code{font:12px/1.6 ui-monospace,Menlo,monospace;background:\(dark ? "#ffffff12" : "#00000009");padding:2px 5px;border-radius:4px} pre{overflow-x:auto;background:\(dark ? "#ffffff09" : "#00000006");padding:12px;border-radius:8px} pre code{padding:0;background:none;white-space:pre} blockquote{margin:10px 0;padding:4px 12px;border-left:3px solid #598bff;color:\(dark ? "#b9bbc2" : "#62656b")} .list,.task{display:flex;gap:8px;margin:4px 0}.marker{min-width:18px;text-align:right}.done{text-decoration:line-through;opacity:.6} .table-wrap{overflow-x:auto}table{border-collapse:collapse;margin:12px 0;min-width:100%}td,th{border:1px solid \(dark ? "#ffffff30" : "#00000025");padding:7px 10px;text-align:left}th{background:\(dark ? "#ffffff0c" : "#00000005")}hr{border:0;border-top:1px solid #8885;margin:16px 0}img{max-width:100%;height:auto;border-radius:6px}
        </style></head><body>\(body(markdown))</body></html>
        """
    }
}

struct MarkdownPreview: NSViewRepresentable {
    let text: String
    @Environment(\.colorScheme) private var scheme
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.setValue(false, forKey: "drawsBackground")
        view.navigationDelegate = context.coordinator
        view.setAccessibilityLabel("Форматированный текст")
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {
        let html = MarkdownHTML.document(text, dark: scheme == .dark)
        guard context.coordinator.html != html else { return }
        context.coordinator.html = html; view.loadHTMLString(html, baseURL: nil)
    }
    final class Coordinator: NSObject, WKNavigationDelegate {
        var html = ""
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated {
                if let url = navigationAction.request.url, MarkdownHTML.safeURL(url.absoluteString) != nil { NSWorkspace.shared.open(url) }
                decisionHandler(.cancel)
            } else { decisionHandler(navigationAction.request.url?.scheme == "about" ? .allow : .cancel) }
        }
    }
}
