import AppKit
import SwiftUI
import WebKit
import IslandCore

@MainActor
final class WebAgentBrowser: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate, NSWindowDelegate {
    private weak var agents: AgentService?
    private let provider: AgentProvider
    private var session: UUID?
    private var active = false
    private var preview = false
    let webView: WKWebView
    let window: NSWindow
    init(provider: AgentProvider, agents: AgentService) {
        self.provider = provider; self.agents = agents
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = CommandLine.arguments.contains("--render-preview") ? .nonPersistent() : .default()
        if let url = Bundle.main.url(forResource: "observer", withExtension: "js", subdirectory: "BrowserExtension"),
           let script = try? String(contentsOf: url, encoding: .utf8) {
            configuration.userContentController.addUserScript(.init(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
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
        if webView.url == nil && !preview {
            webView.load(URLRequest(url: URL(string: provider == .claude ? "https://claude.ai/" : "https://chatgpt.com/")!))
        }
        if !window.isVisible {
            if let available = NSScreen.main?.visibleFrame {
                window.setContentSize(NSSize(width: min(980, available.width - 60), height: min(720, available.height - 60)))
            }
            window.center()
        }
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let object = message.body as? [String: Any],
              let bytes = try? JSONSerialization.data(withJSONObject: object),
              let event = try? WebAgentEvent.decode(bytes), event.provider == provider,
              (message.frameInfo.securityOrigin.host == event.host || (preview && CommandLine.arguments.contains("--render-preview"))) else { return }
        session = event.session; active = event.state == .start || event.state == .working; agents?.receiveWeb(bytes)
    }
    func windowWillClose(_ notification: Notification) {
        guard active, let session else { return }
        active = false
        let host = provider == .claude ? "claude.ai" : "chatgpt.com"
        if let bytes = try? JSONSerialization.data(withJSONObject: ["provider": provider.rawValue, "host": host,
            "session": session.uuidString, "state": "interrupted"]) { agents?.receiveWeb(bytes) }
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
        webView.loadHTMLString("<html><body style='background:#100b18;color:#efe9f7;font:18px system-ui;padding:40px'><h1>Веб-агент · проверка подключения</h1><p>Локальная тестовая страница. Аккаунты и интернет не используются.</p></body></html>", baseURL: nil)
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
