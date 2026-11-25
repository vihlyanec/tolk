import AppKit
import WebKit
import Testing
@testable import Takt

@MainActor private final class NoteMessages: NSObject, WKScriptMessageHandler {
    var ready = false
    var tagCommits = 0
    var conversion: [String: String]?
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if (message.body as? [String: String])?["type"] == "ready" { ready = true }
        if (message.body as? [String: String])?["type"] == "commitTags" { tagCommits += 1 }
        if let value = message.body as? [String: String], value["type"] == "convertTask" { conversion = value }
    }
}
@Test @MainActor func richNotesRenderEditAndRoundTripMarkdownInOneDocument() async throws {
    _ = NSApplication.shared
    let messages = NoteMessages(), config = WKWebViewConfiguration()
    config.websiteDataStore = .nonPersistent()
    config.userContentController.add(messages, name: "note")
    config.userContentController.addUserScript(WKUserScript(source: RichNoteEditor.script, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
    let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 700, height: 500), configuration: config)
    defer { config.userContentController.removeScriptMessageHandler(forName: "note") }
    let markdown = "## План\n\n**Жирный** и *курсив*\n\n- [x] Готово\n- [ ] Проверить\n\n| Имя | Статус |\n| --- | --- |\n| Тест | Готово |\n\n[Ссылка](https://example.com)\n\n```swift\nlet x = 1\n```"
    let html = MarkdownHTML.document(markdown, dark: true).replacingOccurrences(of: "<body>", with: "<body><main id='editor' contenteditable='true'>").replacingOccurrences(of: "</body>", with: "</main><div id='suggestions'></div></body>")
    web.loadHTMLString(html, baseURL: nil)
    for _ in 0..<100 where !messages.ready { try await Task.sleep(for: .milliseconds(50)) }
    #expect(messages.ready)
    guard messages.ready else { return }
    let loaded = try await web.callAsyncJavaScript("return {bold:!!document.querySelector('strong'), table:!!document.querySelector('table'), checked:document.querySelector('input').checked, text:window.noteMarkdown()}", arguments: [:], in: nil, contentWorld: .page) as? [String: Any]
    #expect(loaded?["bold"] as? Bool == true && loaded?["table"] as? Bool == true && loaded?["checked"] as? Bool == true)
    let text = try #require(loaded?["text"] as? String)
    #expect(text.contains("**Жирный**") && text.contains("- [x] Готово") && text.contains("| Имя | Статус |") && text.contains("https://example.com"))
    let edited = try await web.callAsyncJavaScript("window.setNote('<p>Проверка</p>'); const s=getSelection(),r=document.createRange(); r.selectNodeContents(document.querySelector('#editor p'));s.removeAllRanges();s.addRange(r);window.formatNote('**','**');return {html:document.getElementById('editor').innerHTML,text:window.noteMarkdown()}", arguments: [:], in: nil, contentWorld: .page) as? [String: String]
    #expect(edited?["text"] == "**Проверка**")
    #expect(edited?["html"]?.contains("<b>") == true || edited?["html"]?.contains("<strong>") == true)
    let table = try await web.callAsyncJavaScript("window.formatNote('| Колонка',''); return window.noteMarkdown()", arguments: [:], in: nil, contentWorld: .page) as? String
    #expect(table?.contains("| Колонка 1 | Колонка 2 |") == true)
    let typed = try await web.callAsyncJavaScript("window.setNote('<p><br></p>');const r=document.createRange(),s=getSelection();r.selectNodeContents(document.querySelector('#editor p'));r.collapse(true);s.removeAllRanges();s.addRange(r);document.getElementById('editor').focus();document.execCommand('insertText',false,'**Сразу**');return {html:document.getElementById('editor').innerHTML,text:window.noteMarkdown()}", arguments: [:], in: nil, contentWorld: .page) as? [String: String]
    #expect(typed?["text"] == "**Сразу**")
    #expect(typed?["html"]?.contains("<strong>") == true)

    _ = try await web.callAsyncJavaScript("window.setNote('<p>#конечный </p>');document.getElementById('editor').dispatchEvent(new InputEvent('input',{bubbles:true,inputType:'insertText',data:' '}));return window.noteMarkdown()", arguments: [:], in: nil, contentWorld: .page)
    for _ in 0..<20 where messages.tagCommits == 0 { try await Task.sleep(for: .milliseconds(20)) }
    #expect(messages.tagCommits > 0)
    _ = try await web.callAsyncJavaScript("""
        window.setNote('<p>Первый</p><div class="task">☐ <span>Позвонить</span></div><div class="task">☐ <span>Позвонить</span></div>');
        const cursor = document.createRange(), selection = getSelection();
        cursor.selectNodeContents(document.querySelectorAll('.task span')[1]); cursor.collapse(true);
        document.getElementById('editor').focus(); selection.removeAllRanges(); selection.addRange(cursor);
        window.convertTaskLine();
        """, arguments: [:], in: nil, contentWorld: .page)
    for _ in 0..<30 where messages.conversion == nil { try await Task.sleep(for: .milliseconds(20)) }
    #expect(messages.conversion?["line"] == "- [ ] Позвонить")
    #expect(messages.conversion?["occurrence"] == "1")
    #expect(messages.conversion?["title"] == "Позвонить")

    messages.conversion = nil
    _ = try await web.callAsyncJavaScript("""
        window.setNote('<p>Позвонить <strong>в сервис завтра</strong> и записать ответ</p>');
        const cursor = document.createRange(), selection = getSelection();
        const line = document.querySelector('#editor p'), text = line.querySelector('strong').firstChild;
        cursor.setStart(text, 'в сервис'.length); cursor.collapse(true);
        document.getElementById('editor').focus(); selection.removeAllRanges(); selection.addRange(cursor);
        line.dispatchEvent(new KeyboardEvent('keydown', {key:'Enter', metaKey:true, shiftKey:true, bubbles:true, cancelable:true}));
        """, arguments: [:], in: nil, contentWorld: .page)
    for _ in 0..<30 where messages.conversion == nil { try await Task.sleep(for: .milliseconds(20)) }
    #expect(messages.conversion?["title"] == "Позвонить в сервис")
    #expect(messages.conversion?["line"] == "Позвонить **в сервис завтра** и записать ответ")
    #expect(messages.conversion?["suffix"] == " **завтра** и записать ответ")

    let taskUUID = UUID().uuidString.lowercased()
    let restored = try await web.callAsyncJavaScript("""
        window.setNote('<p><a class="linked-task" href="tolk-task://item/'+taskID+'">Позвонить</a> завтра</p>', taskID);
        const selection=getSelection(), link=document.querySelector('a');
        return selection.isCollapsed && selection.anchorNode===link.parentNode && selection.anchorOffset===1;
        """, arguments: ["taskID": taskUUID], in: nil, contentWorld: .page) as? Bool
    #expect(restored == true)
}
