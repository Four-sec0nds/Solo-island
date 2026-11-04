import AppKit
import SwiftUI
import WebKit

@MainActor
final class MusicBrowserWindow: NSWindowController, NSWindowDelegate {
    private let service: WebMusicService
    init(service: WebMusicService) {
        self.service = service
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: 700),
            styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        panel.title = "Музыка — Solo Island"; panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 680, height: 520)
        panel.contentView = NSHostingView(rootView: MusicBrowserContent(service: service))
        super.init(window: panel); panel.delegate = self
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    func present() {
        guard let window else { return }
        if !window.isVisible, let screen = NSScreen.main {
            let available = screen.visibleFrame
            window.setContentSize(NSSize(width: min(940, available.width - 60), height: min(700, available.height - 60)))
            window.center()
        }
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func windowWillClose(_ notification: Notification) { service.onPlayerClosed?() }
}

@MainActor
private struct MusicBrowserContent: View {
    @ObservedObject var service: WebMusicService
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Button { (service.popup ?? service.webView).goBack() } label: { Image(systemName: "chevron.left") }
                Button { (service.popup ?? service.webView).reload() } label: { Image(systemName: "arrow.clockwise") }
                Image(systemName: "lock.fill").font(.system(size: 10))
                Text((service.popup ?? service.webView).url?.host ?? service.provider?.title ?? "Вход в сервис")
                    .font(.system(size: 12)).lineLimit(1)
                Spacer()
                if service.loading { ProgressView().controlSize(.small) }
                if service.popup != nil { Button("К сервису") { service.popup = nil } }
                Button("В браузере") { service.openInBrowser() }
            }.buttonStyle(.plain).padding(14)
            if let error = service.error {
                Text(error).font(.system(size: 11)).foregroundStyle(.orange).padding(8)
            }
            EmbeddedMusicWebsite(webView: service.popup ?? service.webView)
                .id(ObjectIdentifier(service.popup ?? service.webView))
            Text("Вход сохраняется в Solo Island. После выбора трека управление доступно в островке.")
                .font(.system(size: 11)).foregroundStyle(.secondary).padding(10)
        }.background(IslandPalette.background).foregroundStyle(IslandPalette.text).preferredColorScheme(.dark)
    }
}
