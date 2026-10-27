import AppKit
import SwiftUI
import WebKit
import Combine
import IslandCore

@MainActor
final class WebMusicService: NSObject, ObservableObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    @Published private(set) var provider: MusicProvider?
    @Published private(set) var track = NowPlaying()
    @Published private(set) var loading = false
    @Published var error: String?
    @Published var popup: WKWebView?
    @Published private(set) var artwork: NSImage?
    private var frame: WKFrameInfo?
    private var continuity = NowPlayingContinuity()
    private var expiry: Task<Void, Never>?
    private var artworkTask: Task<Void, Never>?
    private var artworkURL: String?
    private var artworkRevision = UUID()
    private var loaded = false
    private var previewFixture = false
    lazy var webView: WKWebView = {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = CommandLine.arguments.contains("--render-preview") ? .nonPersistent() : .default()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.userContentController.addUserScript(.init(source: WebPlayerScript.source, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        config.userContentController.add(WeakWebMessageHandler(self), name: "soloPlayer")
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = self; view.uiDelegate = self
        view.allowsBackForwardNavigationGestures = true
        return view
    }()
    func configure(_ value: MusicProvider) {
        guard provider != value || !loaded else { return }
        expiry?.cancel(); artworkTask?.cancel(); artworkRevision = UUID()
        previewFixture = false; provider = value; track = NowPlaying(); continuity = NowPlayingContinuity()
        artwork = nil; artworkURL = nil; frame = nil; error = nil; popup = nil
        loaded = true; webView.load(URLRequest(url: value.url))
    }
    func stop() { expiry?.cancel(); artworkTask?.cancel(); if loaded { webView.stopLoading() } }
    func reload() { if loaded { error = nil; webView.reload() } }
    func openInBrowser() { if let provider { NSWorkspace.shared.open(provider.url) } }
    func resetSession() {
        guard loaded else { return }
        // This is Solo Island's WebKit store, independent of Safari and other browsers.
        WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) { [weak self] in
            Task { @MainActor in guard let self, let provider = self.provider else { return }; self.loaded = false; self.configure(provider) }
        }
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "soloPlayer", let provider else { return }
        let preview = previewFixture && message.frameInfo.isMainFrame && CommandLine.arguments.contains("--render-preview")
        guard provider.acceptsPlaybackHost(message.frameInfo.securityOrigin.host) || preview,
              let body = message.body as? [String: Any],
              let title = body["title"] as? String else { return }
        var next = NowPlaying()
        next.title = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(512))
        next.artist = (body["artist"] as? String).map { String($0.prefix(512)) }
        next.playing = body["playing"] as? Bool ?? false
        next.bundleIdentifier = "app.solo.island.web.\(provider.rawValue)"
        func number(_ key: String) -> Double? {
            guard let value = body[key] as? Double, value.isFinite, value >= 0 else { return nil }; return value
        }
        next.duration = number("duration"); next.elapsedTime = number("elapsedTime")
        next.playbackRate = number("playbackRate") ?? 1
        // A silent child frame must not replace the active player frame.
        if next.hasTrack {
            if next.isPlaying || !track.isPlaying || frame?.isMainFrame == message.frameInfo.isMainFrame {
                frame = message.frameInfo
            } else { return }
        } else if frame?.isMainFrame != message.frameInfo.isMainFrame { return }
        if let visible = continuity.receive(next, at: Date()) {
            expiry?.cancel(); expiry = nil; track = visible
            updateArtwork(body["artworkURL"] as? String)
        } else if expiry == nil {
            expiry = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 2_050_000_000)
                guard !Task.isCancelled, let self else { return }
                if let empty = self.continuity.expire(at: Date()) { self.track = empty; self.artwork = nil }
                self.expiry = nil
            }
        }
    }
    private func updateArtwork(_ address: String?) {
        guard address != artworkURL else { return }
        artworkURL = address; artworkTask?.cancel(); artworkRevision = UUID()
        guard let address, let url = URL(string: address), url.scheme == "https" else { artwork = nil; return }
        let revision = artworkRevision
        artworkTask = Task { @MainActor [weak self] in
            do {
                let config = URLSessionConfiguration.ephemeral; config.timeoutIntervalForRequest = 12
                let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
                let (data, response) = try await session.data(from: url)
                guard !Task.isCancelled, let self, self.artworkRevision == revision,
                      (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 5 * 1024 * 1024 else { return }
                self.artwork = NSImage(data: data)
            } catch { /* Artwork is optional; retain playback controls. */ }
        }
    }
    func command(_ action: String, value: Double? = nil) {
        guard loaded else { return }
        let safeActions = ["toggle-play-pause", "next-track", "previous-track", "seek"]
        guard safeActions.contains(action) else { return }
        let seconds: Any
        if let value, value.isFinite && value >= 0 { seconds = value } else { seconds = NSNull() }
        webView.callAsyncJavaScript("return await window.__soloIsland?.command(action, seconds) ?? 'unavailable';",
                                   arguments: ["action": action, "seconds": seconds], in: frame, in: .page) { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success(let value):
                    if value as? String == "unavailable" { self?.error = "Откройте веб-плеер: этот сайт не передал нужную команду." }
                    else { self?.error = nil }
                case .failure: self?.error = "Команда недоступна на этой странице. Откройте веб-плеер."
                }
            }
        }
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { loading = true; error = nil }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loading = false }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { navigationFailed(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { navigationFailed(error) }
    private func navigationFailed(_ failure: Error) {
        loading = false
        if (failure as NSError).code != NSURLErrorCancelled { error = "Страница не загрузилась. Проверьте сеть или откройте сервис в браузере." }
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if ["https", "about", "blob"].contains(url.scheme ?? "") { decisionHandler(.allow) }
        else { decisionHandler(.cancel) }
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard navigationAction.targetFrame == nil, navigationAction.request.url?.scheme == "https" else { return nil }
        let child = WKWebView(frame: .zero, configuration: configuration)
        child.navigationDelegate = self; child.uiDelegate = self; popup = child
        return child
    }
    func webViewDidClose(_ webView: WKWebView) { if popup === webView { popup = nil } }
}

/// WKUserContentController retains handlers; keep the service out of that cycle.
@MainActor
private final class WeakWebMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WebMusicService?
    init(_ target: WebMusicService) { self.target = target }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

struct EmbeddedMusicWebsite: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

extension WebMusicService {
    /// Offline test audio and metadata. It never visits a provider or reads a user session.
    func loadPreviewFixture() {
        guard CommandLine.arguments.contains("--render-preview") else { return }
        previewFixture = true; provider = .yandex; loaded = true
        var data = Data()
        func string(_ text: String) { data.append(contentsOf: text.utf8) }
        func uint32(_ value: UInt32) { var v = value.littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
        func uint16(_ value: UInt16) { var v = value.littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
        let size: UInt32 = 8 * 8000 * 2
        string("RIFF"); uint32(36 + size); string("WAVEfmt "); uint32(16); uint16(1); uint16(1)
        uint32(8000); uint32(16000); uint16(2); uint16(16); string("data"); uint32(size)
        data.append(Data(repeating: 0, count: Int(size)))
        let html = """
        <!doctype html><html><meta name="viewport" content="width=device-width"><body style="background:#100a1a;color:#eee;font:18px system-ui;padding:24px">
        <h2>Демонстрационный веб-сеанс</h2><p data-testid="context-item-info-title">Веб-трек</p>
        <p data-testid="context-item-info-subtitles">Тест нативного моста</p>
        <audio controls loop src="data:audio/wav;base64,\(data.base64EncodedString())"></audio>
        <script>
        if (navigator.mediaSession && window.MediaMetadata) {
          navigator.mediaSession.metadata = new MediaMetadata({title:'Веб-трек',artist:'Тест нативного моста'});
          navigator.mediaSession.setActionHandler('nexttrack', () => {
            navigator.mediaSession.metadata = new MediaMetadata({title:'Следующий веб-трек',artist:'Тест нативного моста'});
            document.querySelector('[data-testid="context-item-info-title"]').textContent='Следующий веб-трек';
            window.__soloIsland.send();
          });
        }
        </script></body></html>
        """
        webView.loadHTMLString(html, baseURL: MusicProvider.yandex.url)
    }
}
