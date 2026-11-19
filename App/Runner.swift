import Foundation
import WebKit
import UniformTypeIdentifiers

/// Serves project files to WKWebView under shaghil-run://<project-id>/<path>.
/// Each project gets its own origin, so localStorage / IndexedDB persist per project.
final class RunSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "shaghil-run"
    static let shared = RunSchemeHandler()

    static func entryURL(_ id: String) -> URL {
        URL(string: "\(scheme)://\(id)/")!
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url, let id = url.host?.lowercased() else {
            task.didFailWithError(URLError(.badURL)); return
        }
        var path = url.path
        if path.hasPrefix("/") { path.removeFirst() }
        path = path.removingPercentEncoding ?? path

        NSLog("SHAGHIL scheme start \(url.absoluteString)")
        let store = ProjectStore.shared
        var data: Data?
        var mime = "text/html"

        if path.isEmpty || path == "index.html" {
            if let p = store.project(id) {
                if p.files.contains("index.html") {
                    data = store.read("index.html", in: id).data(using: .utf8)
                } else {
                    data = Runner.wrapper(for: p).data(using: .utf8)
                }
            }
        } else {
            let fileURL = SharedStore.filesURL(for: id).appendingPathComponent(path)
            data = try? Data(contentsOf: fileURL)
            mime = Runner.mime(for: path)
        }

        guard let body = data else {
            let resp = HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/plain"])!
            task.didReceive(resp)
            task.didReceive("Not found: \(path)".data(using: .utf8)!)
            task.didFinish()
            return
        }
        let headers = [
            "Content-Type": mime.hasPrefix("text/") || mime.contains("javascript") || mime.contains("json") ? "\(mime); charset=utf-8" : mime,
            "Content-Length": "\(body.count)",
            "Cache-Control": "no-store",
            "Access-Control-Allow-Origin": "*"
        ]
        let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
        task.didReceive(resp)
        task.didReceive(body)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

enum Runner {
    static func mime(for path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "html", "htm": return "text/html"
        case "css": return "text/css"
        case "js", "mjs": return "text/javascript"
        case "json": return "application/json"
        case "svg": return "image/svg+xml"
        case "md", "txt", "py", "swift", "ts": return "text/plain"
        default:
            return UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
        }
    }

    /// Console + widget bridge injected at document start.
    static func bridgeScript(stateJSON: String) -> String {
        """
        (function(){
          if (window.__shaghil) return; window.__shaghil = true;
          function fmt(a){ try { if (a instanceof Error) return a.name + ': ' + a.message; return (typeof a === 'object' && a !== null) ? JSON.stringify(a, null, 1) : String(a); } catch(e) { return String(a); } }
          function post(level, args){ try { window.webkit.messageHandlers.console.postMessage({level: level, msg: Array.prototype.map.call(args, fmt).join(' ')}); } catch(e){} }
          ['log','info','warn','error','debug'].forEach(function(l){ var o = console[l]; console[l] = function(){ post(l, arguments); if (o) o.apply(console, arguments); }; });
          window.addEventListener('error', function(e){ post('error', [ (e.message || 'Error') + (e.lineno ? ' (سطر ' + e.lineno + (e.filename ? ' · ' + e.filename.split('/').pop() : '') + ')' : '') ]); });
          window.addEventListener('unhandledrejection', function(e){ post('error', ['Promise: ' + ((e.reason && e.reason.message) || e.reason)]); });
          window.shaghil = {
            state: \(stateJSON),
            widget: function(d){ try { window.webkit.messageHandlers.widget.postMessage(JSON.parse(JSON.stringify(d || {}))); this.state = Object.assign(this.state || {}, d); } catch(e){ post('error', ['shaghil.widget: ' + e.message]); } }
          };
        })();
        """
    }

    private static let baseStyle = """
    <meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
    <style>
    :root{color-scheme:light dark}
    body{font-family:-apple-system,system-ui,sans-serif;margin:0;padding:16px;padding-top:max(16px,env(safe-area-inset-top));line-height:1.5}
    pre,code{font-family:ui-monospace,Menlo,monospace;font-size:13px}
    </style>
    """

    static func wrapper(for p: Project) -> String {
        let main = p.mainFile
        switch p.language {
        case .javascript:
            let scripts = p.files.filter { $0.hasSuffix(".js") && $0 != "widget.js" }
                .map { "<script src=\"\($0)\"></script>" }.joined(separator: "\n")
            let css = p.files.filter { $0.hasSuffix(".css") }.map { "<link rel=\"stylesheet\" href=\"\($0)\">" }.joined()
            return """
            <!doctype html><html><head>\(baseStyle)\(css)
            <style>#__out{font-family:ui-monospace,Menlo,monospace;font-size:13px;white-space:pre-wrap;direction:ltr;text-align:left}
            #__out div{padding:6px 2px;border-bottom:1px solid rgba(127,127,127,.15)} #__out .error{color:#e5484d} #__out .warn{color:#d39b00}</style>
            </head><body><div id="__out"></div>
            <script>(function(){var out=document.getElementById('__out');['log','info','warn','error'].forEach(function(l){var o=console[l];console[l]=function(){var d=document.createElement('div');d.className=l;d.textContent=Array.prototype.map.call(arguments,function(a){try{return typeof a==='object'?JSON.stringify(a,null,2):String(a)}catch(e){return String(a)}}).join(' ');out.appendChild(d);o.apply(console,arguments)}});window.addEventListener('error',function(e){var d=document.createElement('div');d.className='error';d.textContent='⚠︎ '+e.message;out.appendChild(d)})})();</script>
            \(scripts)
            </body></html>
            """
        case .css:
            return """
            <!doctype html><html><head>\(baseStyle)<link rel="stylesheet" href="\(main)"></head><body>
            <header><h1>عنوان رئيسي</h1><nav><a href="#">رابط</a> · <a href="#">رابط آخر</a></nav></header>
            <main class="container"><section class="card"><h2>بطاقة</h2><p>هذه صفحة تجريبية لمعاينة ملف CSS. <strong>نص عريض</strong> و<em>مائل</em>.</p>
            <button class="btn">زر</button> <button class="btn primary">زر أساسي</button></section>
            <ul><li>عنصر أول</li><li>عنصر ثانٍ</li></ul>
            <form><input placeholder="حقل إدخال"> <select><option>خيار</option></select></form>
            <table><tr><th>عمود</th><th>عمود</th></tr><tr><td>1</td><td>2</td></tr></table></main>
            <footer><small>تذييل</small></footer></body></html>
            """
        case .svg:
            return """
            <!doctype html><html><head>\(baseStyle)<style>body{display:flex;align-items:center;justify-content:center;min-height:90vh}img{max-width:100%;max-height:90vh}</style></head>
            <body><img src="\(main)"></body></html>
            """
        case .json:
            return """
            <!doctype html><html><head>\(baseStyle)<style>
            body{direction:ltr} .k{color:#a0459c} .s{color:#c41a16} .n{color:#1c00cf} .b{color:#0b6e99}
            @media (prefers-color-scheme:dark){.k{color:#ff7ab2}.s{color:#fc6a5d}.n{color:#d9c97c}.b{color:#5dd8ff}}
            details{margin-left:14px} summary{cursor:pointer}</style></head><body><div id="v"></div>
            <script>
            function esc(s){return String(s).replace(/[&<>]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;'}[c]))}
            function r(v){ if(v===null) return '<span class="b">null</span>';
              if(Array.isArray(v)) return '<details open><summary>Array ['+v.length+']</summary>'+v.map((x,i)=>'<div><span class="n">'+i+'</span>: '+r(x)+'</div>').join('')+'</details>';
              if(typeof v==='object') { var k=Object.keys(v); return '<details open><summary>{ '+k.length+' }</summary>'+k.map(x=>'<div><span class="k">"'+esc(x)+'"</span>: '+r(v[x])+'</div>').join('')+'</details>'; }
              if(typeof v==='string') return '<span class="s">"'+esc(v)+'"</span>';
              if(typeof v==='number') return '<span class="n">'+v+'</span>';
              return '<span class="b">'+v+'</span>'; }
            fetch('\(main)').then(x=>x.text()).then(t=>{ try { document.getElementById('v').innerHTML = r(JSON.parse(t)); } catch(e) { console.error('JSON غير صالح: ' + e.message); document.getElementById('v').innerHTML='<pre>'+esc(t)+'</pre>'; } });
            </script></body></html>
            """
        case .markdown:
            return """
            <!doctype html><html><head>\(baseStyle)<style>body{max-width:760px;margin:auto} pre{background:rgba(127,127,127,.12);padding:12px;border-radius:10px;overflow:auto} code{background:rgba(127,127,127,.12);padding:1px 4px;border-radius:4px} blockquote{border-inline-start:3px solid #888;margin:0;padding-inline-start:12px;color:#777} img{max-width:100%}</style></head><body><article id="md"></article>
            <script>
            function esc(s){return s.replace(/[&<>]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;'}[c]))}
            function inline(s){return esc(s).replace(/`([^`]+)`/g,'<code>$1</code>').replace(/!\\[([^\\]]*)\\]\\(([^)]+)\\)/g,'<img alt="$1" src="$2">').replace(/\\[([^\\]]+)\\]\\(([^)]+)\\)/g,'<a href="$2">$1</a>').replace(/\\*\\*([^*]+)\\*\\*/g,'<strong>$1</strong>').replace(/\\*([^*]+)\\*/g,'<em>$1</em>')}
            function md(t){var L=t.split('\\n'),h='',i=0,list=null;
              function close(){if(list){h+='</'+list+'>';list=null}}
              while(i<L.length){var l=L[i];
                if(/^```/.test(l)){close();var c=[];i++;while(i<L.length&&!/^```/.test(L[i])){c.push(L[i]);i++}h+='<pre><code>'+esc(c.join('\\n'))+'</code></pre>';i++;continue}
                var m;
                if(m=l.match(/^(#{1,6})\\s+(.*)/)){close();h+='<h'+m[1].length+'>'+inline(m[2])+'</h'+m[1].length+'>'}
                else if(m=l.match(/^\\s*[-*+]\\s+(.*)/)){if(list!=='ul'){close();h+='<ul>';list='ul'}h+='<li>'+inline(m[1])+'</li>'}
                else if(m=l.match(/^\\s*\\d+\\.\\s+(.*)/)){if(list!=='ol'){close();h+='<ol>';list='ol'}h+='<li>'+inline(m[1])+'</li>'}
                else if(m=l.match(/^>\\s?(.*)/)){close();h+='<blockquote>'+inline(m[1])+'</blockquote>'}
                else if(/^\\s*(-{3,}|\\*{3,})\\s*$/.test(l)){close();h+='<hr>'}
                else if(l.trim()===''){close()}
                else{close();h+='<p>'+inline(l)+'</p>'}
                i++}
              close();return h}
            fetch('\(main)').then(x=>x.text()).then(t=>{document.getElementById('md').innerHTML=md(t); document.dir = /[\\u0600-\\u06FF]/.test(t) ? 'rtl' : 'ltr';});
            </script></body></html>
            """
        default:
            return """
            <!doctype html><html><head>\(baseStyle)</head><body><pre>\(main)</pre></body></html>
            """
        }
    }
}
