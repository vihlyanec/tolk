import SwiftUI
import WebKit
import TaktCore

/// A single editable document. Markdown remains the portable, backwards-compatible source.
struct RichNoteEditor: NSViewRepresentable {
    @Binding var text: String
    var action: EditorAction?
    var tags: [Tag] = []
    var editable = true
    @Environment(\.colorScheme) private var scheme
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.userContentController.add(context.coordinator, name: "note")
        config.userContentController.addUserScript(WKUserScript(source: Self.script, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let web = WKWebView(frame: .zero, configuration: config)
        web.setValue(false, forKey: "drawsBackground")
        web.navigationDelegate = context.coordinator
        web.setAccessibilityLabel("Текст заметки")
        return web
    }
    static func dismantleNSView(_ web: WKWebView, coordinator: Coordinator) {
        web.configuration.userContentController.removeScriptMessageHandler(forName: "note")
    }
    func updateNSView(_ web: WKWebView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        if !coordinator.loaded {
            coordinator.loaded = true; coordinator.lastText = text
            var html = MarkdownHTML.document(text, dark: scheme == .dark)
            html = html.replacingOccurrences(of: "<body>", with: "<body><main id='editor' contenteditable='\(editable)' role='textbox' aria-label='Текст заметки' aria-multiline='true' spellcheck='true'>")
                .replacingOccurrences(of: "</body>", with: "</main><div id='suggestions' contenteditable='false' role='listbox'></div></body>")
                .replacingOccurrences(of: "</style>", with: Self.styles + "</style>")
            web.loadHTMLString(html, baseURL: nil)
        } else if coordinator.ready, coordinator.lastText != text {
            coordinator.lastText = text
            web.callAsyncJavaScript("window.setNote(html)", arguments: ["html": MarkdownHTML.body(text)], in: nil, in: .page) { _ in }
        }
        if coordinator.ready {
            let dark = scheme == .dark
            web.callAsyncJavaScript("window.noteConfig(tags, editable, dark)", arguments: ["tags": tags.map { ["name": $0.name, "color": SemanticTint.vibrantHex($0.color)] }, "editable": editable, "dark": dark], in: nil, in: .page) { _ in }
            if let action, action.id != coordinator.lastAction {
                coordinator.lastAction = action.id
                web.callAsyncJavaScript("window.formatNote(before, after)", arguments: ["before": action.before, "after": action.after], in: nil, in: .page) { _ in }
            }
        }
    }
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var parent: RichNoteEditor
        var loaded = false, ready = false
        var lastText = ""
        var lastAction: UUID?
        init(_ parent: RichNoteEditor) { self.parent = parent }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let value = message.body as? [String: String] else { return }
            if value["type"] == "ready" { ready = true; parent.updateConfiguration(message.webView); return }
            if value["type"] == "change", let text = value["text"], text != lastText {
                lastText = text; parent.text = text
            }
            if value["type"] == "link", let raw = value["url"], let url = MarkdownHTML.safeURL(raw) { NSWorkspace.shared.open(url) }
        }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            if action.navigationType == .linkActivated, let url = action.request.url, MarkdownHTML.safeURL(url.absoluteString) != nil { NSWorkspace.shared.open(url) }
            decisionHandler(action.request.url?.scheme == "about" ? .allow : .cancel)
        }
    }
    private func updateConfiguration(_ web: WKWebView?) {
        web?.callAsyncJavaScript("window.noteConfig(tags, editable, dark)", arguments: ["tags": tags.map { ["name": $0.name, "color": SemanticTint.vibrantHex($0.color)] }, "editable": editable, "dark": scheme == .dark], in: nil, in: .page) { _ in }
    }
    private static let styles = """
    :root{--ink:#232326;--link:#295cd1;--line:#8885} @media(prefers-color-scheme:dark){:root{--ink:#e5e5e7;--link:#82a8ff}}body{color:var(--ink)}a{color:var(--link)}#editor{min-height:calc(100vh - 40px);outline:none;caret-color:var(--ink)}#editor:empty:before{content:'Начните писать…';color:#888;pointer-events:none}#editor:focus{outline:none}#suggestions{display:none;position:fixed;z-index:5;max-height:180px;overflow:auto;border:1px solid var(--line);border-radius:8px;padding:4px;background:Canvas;color:CanvasText;box-shadow:0 8px 24px #0003}#suggestions button{display:block;text-align:left;border:0;background:none;color:inherit;padding:6px 12px;width:100%;font:inherit}#suggestions button.selected{background:#598bff30;border-radius:4px}input[type=checkbox]{accent-color:#598bff}li{margin:4px 0}pre{white-space:pre-wrap}td,th{min-width:70px}.task{display:block}.task input{margin-right:8px}
    """
    // All inserted content is escaped or built through DOM APIs. Pasted HTML never executes.
    static let script = #"""
    (()=>{
      const editor=document.getElementById('editor'), menu=document.getElementById('suggestions');
      let savedRange=null,tags=[],choices=[],choice=0,tagRange=null,composing=false;
      const send=(type,data={})=>window.webkit.messageHandlers.note.postMessage({type,...data});
      const escape=s=>s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
      function serialize(node){
        if(node.nodeType===3)return node.textContent.replace(/\u00a0/g,' ').replace(/\u200b/g,'');
        if(node.nodeType!==1)return '';
        const name=node.tagName.toLowerCase(), children=()=>Array.from(node.childNodes).map(serialize).join('');
        if(name==='input')return '';
        if(name==='br')return '\n';
        if(name==='strong'||name==='b')return '**'+children()+'**';
        if(name==='em'||name==='i')return '*'+children()+'*';
        if(name==='del'||name==='s'||name==='strike')return '~~'+children()+'~~';
        if(name==='a')return node.querySelector('img')?children():'['+children()+']('+node.getAttribute('href')+')';
        if(name==='img')return '!['+(node.alt||'')+']('+node.getAttribute('src')+')';
        if(name==='pre')return '\n```\n'+node.textContent.replace(/\n$/,'')+'\n```\n\n';
        if(name==='code')return '`'+children()+'`';
        if(/^h[1-6]$/.test(name))return '#'.repeat(Number(name[1]))+' '+children().trim()+'\n\n';
        if(name==='blockquote')return children().trim().split('\n').map(s=>'> '+s).join('\n')+'\n\n';
        if(name==='hr')return '\n---\n\n';
        if(name==='table'){
          const rows=Array.from(node.rows).map(row=>'| '+Array.from(row.cells).map(cell=>serialize(cell).trim().replace(/\|/g,'\\|').replace(/\n/g,'<br>')).join(' | ')+' |');
          if(rows.length)rows.splice(1,0,'| '+Array.from(node.rows[0].cells).map(()=>'---').join(' | ')+' |');
          return rows.join('\n')+'\n\n';
        }
        if(name==='li'){
          const index=Array.from(node.parentNode.children).indexOf(node)+1;
          return (node.parentNode.tagName==='OL'?index+'. ':'- ')+children().trim()+'\n';
        }
        if(name==='ul'||name==='ol')return children()+'\n';
        if(node.classList.contains('list')){
          const marker=node.querySelector('.marker');
          return (marker&&/^\d/.test(marker.textContent)?marker.textContent:'-')+' '+Array.from(node.children).filter(n=>n!==marker).map(serialize).join('').trim()+'\n';
        }
        if(node.classList.contains('task')){
          const input=node.querySelector('input'), span=node.querySelector('span');
          return '- ['+((input?input.checked:node.textContent.startsWith('☑'))?'x':' ')+'] '+(span?serialize(span):children().replace(/^[☐☑]\s*/,''))+'\n';
        }
        if(name==='p'||name==='div')return children()+'\n';
        return children();
      }
      const markdown=()=>serialize(editor).replace(/\n{3,}/g,'\n\n').replace(/\n+$/,'');
      function changed(){send('change',{text:markdown()});}
      function restore(){const current=getSelection();if(current.rangeCount&&editor.contains(current.anchorNode))savedRange=current.getRangeAt(0).cloneRange();editor.focus();const s=getSelection();if(savedRange&&editor.contains(savedRange.commonAncestorContainer)){s.removeAllRanges();s.addRange(savedRange);}else{const r=document.createRange();r.selectNodeContents(editor);r.collapse(false);s.removeAllRanges();s.addRange(r);}}
      document.addEventListener('selectionchange',()=>{const s=getSelection();if(s.rangeCount&&editor.contains(s.anchorNode))savedRange=s.getRangeAt(0).cloneRange();});
      function normalize(){editor.querySelectorAll('.task').forEach(row=>{if(row.querySelector('input'))return;const box=document.createElement('input');box.type='checkbox';box.checked=row.textContent.startsWith('☑');box.setAttribute('aria-label','Выполнить пункт');if(row.firstChild?.nodeType===3)row.firstChild.remove();row.prepend(box);});}
      window.setNote=html=>{editor.innerHTML=html;normalize();savedRange=null;};
      window.noteConfig=(newTags,editable,dark)=>{tags=newTags;editor.contentEditable=String(editable);document.documentElement.style.colorScheme=dark?'dark':'light';document.documentElement.style.setProperty('--ink',dark?'#e5e5e7':'#232326');document.documentElement.style.setProperty('--link',dark?'#82a8ff':'#295cd1');};
      window.formatNote=(before,after)=>{
        restore();const selection=getSelection(), selected=selection.toString();
        if(before==='**')document.execCommand('bold');
        else if(before==='*')document.execCommand('italic');
        else if(before==='~~')document.execCommand('strikeThrough');
        else if(before==='## ')document.execCommand('formatBlock',false,'h2');
        else if(before==='- ')document.execCommand('insertUnorderedList');
        else if(before==='1. ')document.execCommand('insertOrderedList');
        else if(before==='> ')document.execCommand('formatBlock',false,'blockquote');
        else if(before==='```\n')document.execCommand('formatBlock',false,'pre');
        else if(before==='`')document.execCommand('insertHTML',false,'<code>'+escape(selected||'Код')+'</code>');
        else if(before==='- [ ] ')document.execCommand('insertHTML',false,'<div class="task"><input type="checkbox" aria-label="Выполнить пункт"><span>'+escape(selected||'Пункт')+'</span></div><p><br></p>');
        else if(before==='['){const url=after.slice(2,-1);if(/^(https?:|mailto:)/i.test(url))document.execCommand('insertHTML',false,'<a href="'+escape(url)+'">'+escape(selected||url)+'</a>');}
        else if(before.startsWith('| Колонка'))document.execCommand('insertHTML',false,'<table><thead><tr><th>Колонка 1</th><th>Колонка 2</th></tr></thead><tbody><tr><td><br></td><td><br></td></tr></tbody></table><p><br></p>');
        else if(before.includes('---'))document.execCommand('insertHorizontalRule');
        changed();
      };
      function hideTags(){menu.style.display='none';choices=[];tagRange=null;}
      function acceptTag(index){if(!tagRange||!choices[index])return;const range=tagRange.cloneRange();const s=getSelection();s.removeAllRanges();s.addRange(range);const tag=choices[index];document.execCommand('insertHTML',false,'<span style="color:#'+tag.color+'">#'+escape(tag.name.includes(' ')?'"'+tag.name+'"':tag.name)+'</span>&nbsp;');hideTags();changed();}
      function suggest(){
        hideTags();const s=getSelection();if(!s.rangeCount||!s.isCollapsed||s.anchorNode.nodeType!==3)return;
        const value=s.anchorNode.textContent.slice(0,s.anchorOffset),match=value.match(/(?:^|\s)(#[^\s#]*)$/);if(!match)return;
        choices=tags.filter(t=>t.name.toLocaleLowerCase().includes(match[1].slice(1).toLocaleLowerCase())).slice(0,8);if(!choices.length)return;
        tagRange=s.getRangeAt(0).cloneRange();tagRange.setStart(s.anchorNode,s.anchorOffset-match[1].length);choice=0;menu.replaceChildren();
        choices.forEach((tag,index)=>{const button=document.createElement('button');button.textContent='#'+tag.name;button.style.color='#'+tag.color;button.className=index===0?'selected':'';button.onmousedown=e=>{e.preventDefault();acceptTag(index);};menu.append(button);});
        const rect=s.getRangeAt(0).getBoundingClientRect();menu.style.left=Math.max(4,Math.min(innerWidth-180,rect.left))+'px';menu.style.top=Math.min(innerHeight-190,rect.bottom+4)+'px';menu.style.display='block';
      }
      // Recognize Markdown delimiters as they are finished, without switching modes.
      function inlineTyping(){
        const s=getSelection();if(!s.rangeCount||!s.isCollapsed||s.anchorNode.nodeType!==3)return;
        const node=s.anchorNode,offset=s.anchorOffset,prefix=node.textContent.slice(0,offset);
        if(node.parentElement.closest('code,pre,a'))return;
        const match=prefix.match(/(\*\*([^*]+)\*\*|~~([^~]+)~~|(?<!\*)\*([^*]+)\*|`([^`]+)`|https?:\/\/[^\s<>]+)(\s?)$/);if(!match||(!match[6]&&match[1].startsWith('http')))return;
        const range=document.createRange();range.setStart(node,offset-match[0].length);range.setEnd(node,offset);s.removeAllRanges();s.addRange(range);
        let html;if(match[2])html='<strong>'+escape(match[2])+'</strong>';else if(match[3])html='<del>'+escape(match[3])+'</del>';else if(match[4])html='<em>'+escape(match[4])+'</em>';else if(match[5])html='<code>'+escape(match[5])+'</code>';else html='<a href="'+escape(match[1])+'">'+escape(match[1])+'</a>';
        document.execCommand('insertHTML',false,html+(match[6]?'&nbsp;':'&#8203;'));
      }
      editor.addEventListener('compositionstart',()=>composing=true);editor.addEventListener('compositionend',()=>{composing=false;changed();suggest();});
      editor.addEventListener('input',()=>{if(composing)return;inlineTyping();changed();suggest();});
      editor.addEventListener('change',e=>{if(e.target.type==='checkbox'){e.target.toggleAttribute('checked',e.target.checked);const span=e.target.parentElement.querySelector('span');span?.classList.toggle('done',e.target.checked);changed();}});
      editor.addEventListener('paste',e=>{e.preventDefault();document.execCommand('insertText',false,e.clipboardData.getData('text/plain'));});
      editor.addEventListener('click',e=>{const link=e.target.closest('a');if(link&&!e.altKey){e.preventDefault();send('link',{url:link.href});}});
      editor.addEventListener('keydown',e=>{
        if(choices.length){if(['ArrowDown','ArrowUp'].includes(e.key)){e.preventDefault();choice=(choice+(e.key==='ArrowDown'?1:-1)+choices.length)%choices.length;Array.from(menu.children).forEach((b,i)=>b.className=i===choice?'selected':'');return;}if(e.key==='Enter'||e.key==='Tab'){e.preventDefault();acceptTag(choice);return;}if(e.key==='Escape'){e.preventDefault();hideTags();return;}}
        if(e.key===' '){const s=getSelection();if(s.isCollapsed&&s.anchorNode?.nodeType===3){const text=s.anchorNode.textContent.slice(0,s.anchorOffset);let command=null,value=null;if(/^#{1,6}$/.test(text)){command='formatBlock';value='h'+text.length;}else if(text==='- [ ]'){command='check';}else if(text==='-'||text==='*'){command='insertUnorderedList';}else if(text==='1.'){command='insertOrderedList';}else if(text==='>'){command='formatBlock';value='blockquote';}else if(text==='```'){command='formatBlock';value='pre';}if(command){e.preventDefault();const r=document.createRange();r.setStart(s.anchorNode,0);r.setEnd(s.anchorNode,s.anchorOffset);s.removeAllRanges();s.addRange(r);document.execCommand('delete');if(command==='check')window.formatNote('- [ ] ','');else document.execCommand(command,false,value);changed();}}}
      });
      normalize();send('ready');window.noteMarkdown=markdown;
    })();
    """#
}
