import AppKit
import SwiftUI
import WebKit
import IslandCore

@MainActor
final class WebAgentBrowser: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate, NSWindowDelegate {
    private weak var agents: AgentService?
    private let provider: AgentProvider
    private var activeSessions: [UUID: String] = [:]
    private let observerSource: String?
    private var acceptingEvents = true
    private var preview = false
    let webView: WKWebView
    let window: NSWindow
    init(provider: AgentProvider, agents: AgentService) {
        self.provider = provider; self.agents = agents
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = CommandLine.arguments.contains("--render-preview") ? .nonPersistent() : .default()
        observerSource = Bundle.main.url(forResource: "observer", withExtension: "js", subdirectory: "BrowserExtension")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        if let script = observerSource {
            configuration.userContentController.addUserScript(.init(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        webView = WKWebView(frame: .zero, configuration: configuration)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 720),
            styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        super.init()
        configuration.userContentController.add(WeakAgentMessage(self), name: "soloAgent")
        webView.navigationDelegate = self; webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        window.title = (provider == .claude ? "Claude" : "ChatGPT / Codex") + " — Solo Island"
        window.isReleasedWhenClosed = false; window.delegate = self; window.minSize = NSSize(width: 720, height: 540)
        window.contentView = webView
    }
    func present() {
        acceptingEvents = true
        if webView.url == nil && !preview {
            webView.load(URLRequest(url: URL(string: provider == .claude ? "https://claude.ai/" : "https://chatgpt.com/")!))
        }
        if !window.isVisible {
            if let available = NSScreen.main?.visibleFrame {
                window.setContentSize(NSSize(width: min(980, available.width - 60), height: min(720, available.height - 60)))
            }
            window.center()
        }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        webView.evaluateJavaScript("window.__soloAgentObserver?.resume(); true;", completionHandler: nil)
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard acceptingEvents, message.frameInfo.isMainFrame, let object = message.body as? [String: Any],
              let bytes = try? JSONSerialization.data(withJSONObject: object),
              let event = try? WebAgentEvent.decode(bytes), event.provider == provider,
              (message.frameInfo.securityOrigin.host == event.host || (preview && CommandLine.arguments.contains("--render-preview"))) else { return }
        if event.state == .start || event.state == .working { activeSessions[event.session] = event.host }
        else { activeSessions.removeValue(forKey: event.session) }
        agents?.receiveWeb(bytes)
    }
    func windowWillClose(_ notification: Notification) {
        acceptingEvents = false
        webView.evaluateJavaScript("window.__soloAgentObserver?.suspend(); true;", completionHandler: nil)
        for (session, host) in activeSessions {
            if let bytes = try? JSONSerialization.data(withJSONObject: ["provider": provider.rawValue, "host": host,
                "session": session.uuidString, "state": "interrupted"]) { agents?.receiveWeb(bytes) }
        }
        activeSessions.removeAll()
        agents?.webConnection(provider, status: "Окно закрыто")
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        agents?.webConnection(provider, status: "Подключаем наблюдение…")
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard acceptingEvents else { return }
        let host = webView.url?.host ?? ""
        let expected = provider == .claude ? ["claude.ai", "www.claude.ai"] : ["chatgpt.com", "www.chatgpt.com"]
        guard preview || expected.contains(host) else { agents?.webConnection(provider, status: "Войдите на сайте сервиса"); return }
        Task { [weak self, weak webView] in
            guard let self, let webView else { return }
            do {
                let installed = try await webView.evaluateJavaScript("window.__soloAgentObserver?.installed === true") as? Bool ?? false
                self.agents?.webConnection(self.provider, status: installed ? "Наблюдение включено" : "Не удалось подключить наблюдение")
            } catch { self.agents?.webConnection(self.provider, status: "Не удалось подключить наблюдение") }
        }
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { agents?.webConnection(provider, status: "Не удалось загрузить сайт") }
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let scheme = navigationAction.request.url?.scheme
        decisionHandler(["https", "about", "blob"].contains(scheme ?? "") ? .allow : .cancel)
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, url.scheme == "https" { webView.load(URLRequest(url: url)) }
        return nil
    }
    func loadPreviewFixture() {
        guard CommandLine.arguments.contains("--render-preview") else { return }
        preview = true
        let host = provider == .claude ? "claude.ai" : "chatgpt.com"
        let route = provider == .claude ? "/api/organizations/test/chat_conversations/test/completion" : "/backend-api/f/conversation"
        // Use the unmodified bundled observer against local DOM, fetch, Response
        // and ReadableStream. Only location is scoped to the supported fixture
        // host; no accounts, remote requests or ready-made events are used.
        webView.configuration.userContentController.removeAllUserScripts()
        let script = "(() => { const location = {hostname: '\(host)', origin: 'https://\(host)', href: 'https://\(host)/'};\n" + (observerSource ?? "") + "\n})();"
        webView.configuration.userContentController.addUserScript(.init(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        webView.loadHTMLString("""
        <html><body style="background:#100b18;color:#efe9f7;font:18px system-ui;padding:40px">
        <h1>Локальная проверка веб-агента</h1><button id="begin" onclick="begin()">Начать</button><button id="end" onclick="end()">Завершить</button>
        <script>
        window.fixtureMode = 'stream'; window.fixtureState = 'in_progress'; window.fixtureCompleted = false;
        window.fetch = async () => window.fixtureMode === 'task'
          ? new Response(JSON.stringify({id:'local-task',task_status_display:{latest_turn_status_display:{turn_status:window.fixtureState}}}))
          : new Response(new ReadableStream({start(controller){window.fixtureController=controller;}}));
        window.begin = () => { window.fixtureCompleted=false; window.fixtureJob=(async()=>{
          const response=await fetch('https://\(host)'+(window.fixtureMode==='task'?'/backend-api/wham/tasks/local-task':'\(route)'),{method:window.fixtureMode==='task'?'GET':'POST'});
          if(window.fixtureMode==='task') { await response.json(); return; }
          window.fixtureController.enqueue(new TextEncoder().encode('local-stream'));
          const reader=response.body.pipeThrough(new TextDecoderStream()).getReader(); let text='';
          while(true){const value=await reader.read();if(value.done)break;text+=value.value;} window.fixtureCompleted=text==='local-stream';
        })(); };
        window.end = () => { if(window.fixtureMode==='task') {window.fixtureState='completed';begin();} else window.fixtureController.close(); };
        </script></body></html>
        """, baseURL: nil)
    }
}

@MainActor
private final class WeakAgentMessage: NSObject, WKScriptMessageHandler {
    weak var browser: WebAgentBrowser?
    init(_ browser: WebAgentBrowser) { self.browser = browser }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        browser?.userContentController(userContentController, didReceive: message)
    }
}
