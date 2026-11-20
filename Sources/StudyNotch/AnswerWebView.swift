import SwiftUI
import WebKit

/// Shows the answer as Markdown with typeset math. The text is replaced as it streams in and the
/// view reports its own height so the island can grow with it.
struct AnswerWebView: NSViewRepresentable {
    var markdown: String
    @Binding var height: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "height")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.setValue(false, forKey: "drawsBackground")
        view.navigationDelegate = context.coordinator
        context.coordinator.web = view
        view.loadHTMLString(Self.page, baseURL: nil)
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.push(markdown)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: AnswerWebView
        weak var web: WKWebView?
        private var ready = false
        private var shown: String?

        init(_ parent: AnswerWebView) {
            self.parent = parent
        }

        func push(_ markdown: String) {
            guard ready, markdown != shown else { return }
            shown = markdown
            guard let data = try? JSONSerialization.data(withJSONObject: [markdown]),
                  let json = String(data: data, encoding: .utf8) else { return }
            web?.evaluateJavaScript("render(\(json)[0])", completionHandler: nil)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            ready = true
            push(parent.markdown)
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let value = message.body as? Double else { return }
            DispatchQueue.main.async {
                if abs(self.parent.height - CGFloat(value)) > 0.5 { self.parent.height = CGFloat(value) }
            }
        }
    }

    // The math and Markdown libraries load from a public CDN for now; without a connection the
    // answer still shows as plain text.
    static let page = #"""
    <!doctype html>
    <html>
    <head>
    <meta charset="utf-8">
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.css">
    <script src="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/marked@12.0.2/marked.min.js"></script>
    <style>
      html, body { margin: 0; padding: 0; background: transparent; }
      body { color: #f2f3f5; font: 14px/1.6 -apple-system, "Apple SD Gothic Neo", sans-serif; -webkit-font-smoothing: antialiased; }
      #c > :first-child { margin-top: 0; }
      #c > :last-child { margin-bottom: 0; }
      p, ul, ol { margin: 0 0 8px; }
      ul, ol { padding-left: 20px; }
      h1, h2, h3 { font-size: 15px; margin: 10px 0 6px; }
      code { font: 12.5px ui-monospace, Menlo, monospace; background: rgba(255,255,255,.1); padding: 1px 4px; border-radius: 4px; }
      pre { background: rgba(255,255,255,.08); padding: 8px; border-radius: 6px; overflow-x: auto; }
      pre code { background: none; padding: 0; }
      a { color: #9db8ff; }
      .katex-display { margin: 8px 0; overflow-x: auto; overflow-y: hidden; }
      ::selection { background: rgba(157,184,255,.4); }
    </style>
    </head>
    <body>
    <div id="c"></div>
    <script>
      function esc(s) { return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;'); }
      function render(md) {
        var math = [];
        function keep(tex, display) { math.push({ t: tex, d: display }); return '@@M' + (math.length - 1) + '@@'; }
        md = md.replace(/\$\$([\s\S]+?)\$\$/g, function (m, a) { return keep(a, true); });
        md = md.replace(/\\\[([\s\S]+?)\\\]/g, function (m, a) { return keep(a, true); });
        md = md.replace(/\\\(([\s\S]+?)\\\)/g, function (m, a) { return keep(a, false); });
        md = md.replace(/\$([^\$\n]+?)\$/g, function (m, a) { return keep(a, false); });
        var html = window.marked ? marked.parse(md) : esc(md).replace(/\n/g, '<br>');
        html = html.replace(/@@M(\d+)@@/g, function (m, i) {
          var x = math[+i];
          if (!window.katex) return esc(x.t);
          try { return katex.renderToString(x.t, { displayMode: x.d, throwOnError: false }); }
          catch (e) { return esc(x.t); }
        });
        var box = document.getElementById('c');
        box.innerHTML = html;
        window.webkit.messageHandlers.height.postMessage(Math.ceil(box.getBoundingClientRect().height));
      }
    </script>
    </body>
    </html>
    """#
}
